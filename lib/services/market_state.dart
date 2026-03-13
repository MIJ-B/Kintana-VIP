import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

const int kDerivAppId = 129691;

// ── Hybrid Signal Situation
enum JPSituation {
  pureWick,      // S1: wick only outside ACC, body inside → 85%
  bodyRevert,    // S2: body outside but N+1 reverts inside → 70%
  breakout,      // S3: body outside + continues → SKIP 20%
  fvgRetest,     // S4: Fair Value Gap → wait retest → 65%
  ifvg,          // S5: Inverse FVG → trap → 80%
}

// ── Signal AMD (hybrid)
class JPSignal {
  final int idx;
  final String type;        // 'BUY' or 'SELL'
  final double price;
  final JPPhase phase;
  final bool confirmed;
  final String filterNote;
  final JPSituation situation;
  final int confidence;     // 0-100
  final String entryTiming; // 'aggressive' | 'conservative' | 'wait_retest' | 'skip'
  final double? fvgLow;     // for S4/S5 FVG zone
  final double? fvgHigh;

  const JPSignal({
    required this.idx,
    required this.type,
    required this.price,
    required this.phase,
    this.confirmed = true,
    this.filterNote = '',
    this.situation = JPSituation.pureWick,
    this.confidence = 85,
    this.entryTiming = 'aggressive',
    this.fvgLow,
    this.fvgHigh,
  });
}

// ── Phase AMD détectée
class JPPhase {
  final AccZone acc;
  final int manipIdx;
  final String manipDir; // 'up' or 'down'
  final String distDir;  // 'up' or 'down'
  const JPPhase({required this.acc, required this.manipIdx, required this.manipDir, required this.distDir});
}

// ── Accumulation zone
class AccZone {
  final int startIdx;
  final int endIdx;
  final double high;
  final double low;
  final double mid;
  final double atr;
  const AccZone({required this.startIdx, required this.endIdx, required this.high, required this.low, required this.mid, required this.atr});
}

class MarketState extends ChangeNotifier {
  // ── Symbol
  String sym = 'frxXAUUSD';
  String sname = 'Gold / US Dollar';
  int tf = 900;

  // ── Prices
  double? price;
  double? prevPrice;
  double? open0;
  double? bidPrice;
  double? askPrice;

  // ── Candles
  List<Candle> candles = [];

  // ── View
  double zoom = 60;
  double offset = 0;
  double yOffset = 0;

  // ── WS
  WebSocketChannel? _ws;
  bool wsOk = false;
  bool _reconnecting = false;
  int _rid = 1;

  // ── Replay
  bool isReplay = false;
  List<Candle> replayAll = [];
  List<_ReplayTick> replayTicks = [];
  int replayIdx = 0;
  int replayTickIdx = 0;
  bool replayPlaying = false;
  Timer? replayTimer;
  int replaySpeed = 400;

  // ── Trades
  List<Trade> trades = [];

  // ── JOROpredict (GainzAlpha v3 AMD Engine — exact copy from HTML)
  bool joropredictActive = false;
  List<JPSignal> jpSignals = [];      // gainzSignals
  List<JPPhase>  jpPhases  = [];      // _gainzPhases
  JPSignal? activeJPSig;              // _activeGainzSig

  // ── Settings
  bool trailingStop = false;
  double trailingDist = 0.5;
  bool jpAutoTPSL = false;
  double jpTPAtr = 2.0;
  double jpSLAtr = 1.0;
  bool jpAlarm = false;
  String groqKey = '';
  String groqModel = 'llama-3.3-70b-versatile';

  MarketState() { _loadPrefs(); }

  // ─────────────────────────────────────────────
  // ── Candles helpers
  // ─────────────────────────────────────────────
  List<Candle> getCandles() {
    if (!isReplay) return candles;
    if (replayTicks.isEmpty) {
      return replayAll.sublist(0, replayIdx.clamp(0, replayAll.length));
    }
    final tickIdx = replayTickIdx.clamp(0, replayTicks.length - 1);
    final curTick = replayTicks[tickIdx];
    final candleIdx = curTick.candleIdx.clamp(0, replayAll.length - 1);
    final done = replayAll.sublist(0, candleIdx);
    final base = replayAll[candleIdx];
    final candleTicks = replayTicks
        .sublist(0, tickIdx + 1)
        .where((t) => t.candleIdx == candleIdx)
        .toList();
    if (candleTicks.isEmpty) return [...done, base];
    final prices = candleTicks.map((t) => t.price).toList();
    final liveCand = Candle(
      time: base.time, open: base.open,
      high: prices.reduce(max), low: prices.reduce(min), close: prices.last,
    );
    return [...done, liveCand];
  }

  // ── ATR(10) — exact copy from HTML _calcATRForCandles
  double calcATR({int period = 10}) {
    final c = getCandles();
    if (c.length < 2) return 0;
    final p = min(period, c.length - 1);
    double s = 0;
    for (int i = c.length - p; i < c.length; i++) {
      s += max(c[i].high - c[i].low,
          max((c[i].high - c[i-1].close).abs(), (c[i].low - c[i-1].close).abs()));
    }
    return s / p;
  }

  void clampView(List<Candle> c) {
    final n = c.length;
    if (n == 0) { zoom = 60; offset = 0; return; }
    zoom = zoom.clamp(5.0, n.toDouble());
    final maxOffset = max(0, n - 3).toDouble();
    offset = offset.clamp(0.0, maxOffset);
  }

  ({int s, int e, int count}) visibleRange() {
    final c = getCandles();
    if (c.isEmpty) return (s: 0, e: 0, count: 0);
    clampView(c);
    final s = offset.round().clamp(0, c.length - 1);
    final e = (s + zoom.round() - 1).clamp(s, c.length - 1);
    return (s: s, e: e, count: e - s + 1);
  }

  // ─────────────────────────────────────────────
  // ── WebSocket
  // ─────────────────────────────────────────────
  void connect() {
    if (isReplay) return;
    _ws?.sink.close();
    wsOk = false;
    _ws = WebSocketChannel.connect(
      Uri.parse('wss://ws.binaryws.com/websockets/v3?app_id=$kDerivAppId'),
    );
    _ws!.stream.listen(
      (raw) => _onMsg(jsonDecode(raw as String)),
      onDone: _onClose, onError: (_) => _onClose(),
    );
    _send({'ticks': sym, 'subscribe': 1});
    _send({'ticks_history': sym, 'end': 'latest', 'count': 300, 'style': 'candles', 'granularity': tf});
    _send({'ticks_history': sym, 'end': 'latest', 'count': 1,   'style': 'candles', 'granularity': tf, 'subscribe': 1});
    wsOk = true;
    notifyListeners();
  }

  void _send(Map<String, dynamic> obj) {
    if (_ws == null) return;
    obj['req_id'] = _rid++;
    _ws!.sink.add(jsonEncode(obj));
  }

  void _onClose() {
    wsOk = false;
    notifyListeners();
    if (!isReplay && !_reconnecting) {
      _reconnecting = true;
      Future.delayed(const Duration(seconds: 3), () { _reconnecting = false; connect(); });
    }
  }

  void _onMsg(Map<String, dynamic> d) {
    if (d['error'] != null) return;
    if (d['tick'] != null) {
      final t = d['tick'] as Map<String, dynamic>;
      prevPrice = price;
      price = (t['quote'] as num).toDouble();
      open0 ??= price;
      bidPrice = t['bid'] != null ? (t['bid'] as num).toDouble() : null;
      askPrice = t['ask'] != null ? (t['ask'] as num).toDouble() : null;
      if (candles.isNotEmpty) {
        final l = candles.last;
        l.close = price!;
        if (price! > l.high) l.high = price!;
        if (price! < l.low)  l.low  = price!;
      }
      _runTrailingStop(price!);
      _checkPendingSignals(price!);
      if (joropredictActive) computeJPSignals();
      notifyListeners();
    }
    if (d['candles'] != null) {
      candles = (d['candles'] as List).map((c) => Candle.fromMap(c as Map<String, dynamic>)).toList();
      open0 = candles.isNotEmpty ? candles.first.open : null;
      zoom   = min(60, candles.length.toDouble());
      offset = max(0, candles.length - zoom.round()).toDouble();
      if (joropredictActive) computeJPSignals();
      notifyListeners();
    }
    if (d['ohlc'] != null) {
      final o = d['ohlc'] as Map<String, dynamic>;
      final epoch = (o['open_time'] as num).toInt();
      final cn = Candle(
        time: epoch,
        open:  double.parse(o['open'].toString()),
        high:  double.parse(o['high'].toString()),
        low:   double.parse(o['low'].toString()),
        close: double.parse(o['close'].toString()),
      );
      final idx = candles.indexWhere((c) => c.time == epoch);
      if (idx >= 0) candles[idx] = cn;
      else { candles.add(cn); if (candles.length > 500) candles.removeAt(0); }
      if (joropredictActive) computeJPSignals();
      notifyListeners();
    }
  }

  void changeSymbol(Market m) {
    sym = m.symbol; sname = m.name; offset = 0;
    price = null; prevPrice = null; open0 = null; candles.clear();
    jpSignals.clear(); jpPhases.clear(); activeJPSig = null;
    if (isReplay) { replayAll.clear(); replayIdx = 0; notifyListeners(); return; }
    notifyListeners();
    if (wsOk) {
      _send({'forget_all': 'ticks'});
      _send({'forget_all': 'candles'});
      Future.delayed(const Duration(milliseconds: 200), () {
        _send({'ticks': sym, 'subscribe': 1});
        _send({'ticks_history': sym, 'end': 'latest', 'count': 300, 'style': 'candles', 'granularity': tf});
        _send({'ticks_history': sym, 'end': 'latest', 'count': 1,   'style': 'candles', 'granularity': tf, 'subscribe': 1});
      });
    }
  }

  void changeTimeframe(int newTf) {
    tf = newTf; candles.clear(); offset = 0;
    jpSignals.clear(); jpPhases.clear(); activeJPSig = null;
    notifyListeners();
    if (!isReplay && wsOk) {
      _send({'forget_all': 'candles'});
      Future.delayed(const Duration(milliseconds: 200), () {
        _send({'ticks_history': sym, 'end': 'latest', 'count': 300, 'style': 'candles', 'granularity': tf});
        _send({'ticks_history': sym, 'end': 'latest', 'count': 1,   'style': 'candles', 'granularity': tf, 'subscribe': 1});
      });
    }
  }

  // ─────────────────────────────────────────────
  // ── Zoom / Pan
  // ─────────────────────────────────────────────
  void zoomAround(double factor, double pivotScreenFraction) {
    final c = getCandles();
    if (c.isEmpty) return;
    clampView(c);
    final pivotCandle = offset + pivotScreenFraction * zoom;
    final newZoom = (zoom / factor).clamp(5.0, c.length.toDouble()) as double;
    offset = pivotCandle - pivotScreenFraction * newZoom;
    zoom = newZoom;
    clampView(c);
    notifyListeners();
  }

  void zoomIn(double f)  => zoomAround(1.4, f);
  void zoomOut(double f) => zoomAround(1 / 1.4, f);
  void zoomReset() {
    final c = getCandles();
    zoom   = min(60, c.length.toDouble());
    offset = max(0, c.length - zoom.round()).toDouble();
    yOffset = 0;
    notifyListeners();
  }

  void panLeft() {
    final step = max(1, (zoom * 0.15).round());
    offset = max(0.0, offset - step);
    notifyListeners();
  }
  void panRight() {
    final c = getCandles();
    final step = max(1, (zoom * 0.15).round());
    offset = min((c.length - zoom.round()).toDouble(), offset + step);
    notifyListeners();
  }

  // ─────────────────────────────────────────────
  // ── Replay
  // ─────────────────────────────────────────────
  void switchToReplay() {
    isReplay = true; _stopReplay();
    replayAll.clear(); replayTicks.clear();
    replayIdx = 0; replayTickIdx = 0;
    jpSignals.clear(); jpPhases.clear(); activeJPSig = null;
    _ws?.sink.close(); wsOk = false;
    notifyListeners();
  }

  void switchToLive() {
    isReplay = false; _stopReplay();
    replayAll.clear(); candles.clear(); offset = 0;
    jpSignals.clear(); jpPhases.clear(); activeJPSig = null;
    connect(); notifyListeners();
  }

  Future<void> loadReplayData(String dateStr) async {
    final dt = DateTime.parse('${dateStr}T00:00:00Z');
    final startEpoch = dt.millisecondsSinceEpoch ~/ 1000;
    final endEpoch   = startEpoch + 86400;
    replayAll.clear(); replayTicks.clear();
    replayIdx = 0; replayTickIdx = 0; offset = 0;
    notifyListeners();
    final ws   = WebSocketChannel.connect(Uri.parse('wss://ws.binaryws.com/websockets/v3?app_id=$kDerivAppId'));
    final comp = Completer<void>();
    ws.stream.listen((raw) {
      final d = jsonDecode(raw as String) as Map<String, dynamic>;
      if (d['error'] != null) { comp.completeError(d['error']['message']); return; }
      if (d['candles'] != null) {
        final loaded = (d['candles'] as List).map((c) => Candle.fromMap(c as Map<String, dynamic>)).toList();
        replayAll   = loaded;
        replayTicks = _generateTicks(loaded);
        replayIdx   = 0; replayTickIdx = 0;
        zoom   = min(60, loaded.length.toDouble());
        offset = 0;
        if (joropredictActive) computeJPSignals();
        notifyListeners();
        ws.sink.close(); comp.complete();
      }
    }, onError: (e) => comp.completeError(e));
    ws.sink.add(jsonEncode({'ticks_history': sym, 'start': startEpoch, 'end': endEpoch, 'count': 1000, 'style': 'candles', 'granularity': tf, 'req_id': 1}));
    await comp.future;
  }

  // ── Generate ticks from candles (exact copy from HTML generateTicksFromCandles)
  List<_ReplayTick> _generateTicks(List<Candle> candles) {
    final ticks = <_ReplayTick>[];
    final rng   = Random();
    for (int ci = 0; ci < candles.length; ci++) {
      final c   = candles[ci];
      final n   = 15 + rng.nextInt(6); // 15-20 ticks
      final bull = c.close >= c.open;
      final p0  = c.open;
      final p1  = bull ? c.open - (c.open - c.low) * 0.3 : c.open + (c.high - c.open) * 0.3;
      final p2  = bull ? c.high : c.low;
      final p3  = bull ? c.low  : c.high;
      final p4  = c.close;
      final keyPts = [p0, p1, p2, p3, p4];
      final seg = (n / (keyPts.length - 1)).floor();
      int ti = 0;
      for (int si = 0; si < keyPts.length - 1; si++) {
        final from  = keyPts[si];
        final to    = keyPts[si + 1];
        final steps = si == keyPts.length - 2 ? n - ti : seg;
        for (int s = 0; s < steps && ti < n; s++, ti++) {
          final t     = steps > 1 ? s / (steps - 1) : 0.0;
          final noise = (rng.nextDouble() - 0.5) * (c.high - c.low) * 0.04;
          double px   = from + (to - from) * t + noise;
          px = px.clamp(c.low, c.high);
          ticks.add(_ReplayTick(time: c.time + (s * (tf / n)).floor(), price: px, candleIdx: ci));
        }
      }
      if (ticks.isNotEmpty && ticks.last.candleIdx == ci) {
        ticks[ticks.length - 1] = _ReplayTick(time: ticks.last.time, price: c.close, candleIdx: ci);
      }
    }
    return ticks;
  }

  void toggleReplayPlay() => replayPlaying ? _stopReplay() : _startReplay();

  void _startReplay() {
    if (replayTickIdx >= replayTicks.length - 1) replayTickIdx = 0;
    replayPlaying = true; notifyListeners(); _playTick();
  }

  void _stopReplay() {
    replayPlaying = false; replayTimer?.cancel(); notifyListeners();
  }

  void _playTick() {
    if (!replayPlaying) return;
    _advanceTick();
    if (replayPlaying) replayTimer = Timer(Duration(milliseconds: (replaySpeed / 4).round()), _playTick);
  }

  void _advanceTick() {
    if (replayTicks.isEmpty) return;
    if (replayTickIdx < replayTicks.length - 1) {
      replayTickIdx++;
      final tick = replayTicks[replayTickIdx];
      replayIdx = tick.candleIdx + 1;
      final candlePrice = replayAll[tick.candleIdx].close;
      _runTrailingStop(candlePrice);
      _checkPendingSignals(candlePrice);
      if (joropredictActive) computeJPSignals();
    } else {
      _stopReplay();
    }
    notifyListeners();
  }

  void replaySeek(double pct) {
    replayTickIdx = (pct * (replayTicks.length - 1)).round().clamp(0, max(0, replayTicks.length - 1));
    if (replayTicks.isNotEmpty) replayIdx = replayTicks[replayTickIdx].candleIdx + 1;
    notifyListeners();
  }

  double get replayProgress => replayTicks.isEmpty ? 0 : replayTickIdx / (replayTicks.length - 1);

  DateTime? get replayCurrentTime {
    if (replayTicks.isEmpty || replayTickIdx >= replayTicks.length) return null;
    return DateTime.fromMillisecondsSinceEpoch(replayTicks[replayTickIdx].time * 1000);
  }

  // ─────────────────────────────────────────────
  // ── JOROpredict — AMD Engine
  //    EXACT COPY from HTML computeGainzSignals()
  // ─────────────────────────────────────────────
  void toggleJOROpredict() {
    joropredictActive = !joropredictActive;
    jpSignals.clear(); jpPhases.clear(); activeJPSig = null;
    if (joropredictActive) computeJPSignals();
    notifyListeners();
  }

  void computeJPSignals() {
    jpSignals = [];
    jpPhases  = [];
    // _gainzPrediction = null; // not used in Flutter

    final c = getCandles();
    if (c.length < 20) return;
    final n = c.length;

    // ── ATR(10) — exact copy from HTML atr(i)
    double atrAt(int i) {
      const per = 10;
      final from = max(1, i - per + 1);
      double s = 0; int ct = 0;
      for (int k = from; k <= i; k++) {
        s += max(c[k].high - c[k].low,
            max((c[k].high - c[k-1].close).abs(), (c[k].low - c[k-1].close).abs()));
        ct++;
      }
      return ct > 0 ? s / ct : (c[i].high - c[i].low == 0 ? 1 : c[i].high - c[i].low);
    }

    // ── Detect ACCUMULATION zones — exact copy from HTML detectAccumulation()
    // ── detectAccumulation — EXACT COPY from HTML computeGainzSignals > detectAccumulation(5)
    List<AccZone> detectAccumulation({int minBars = 4, int maxBars = 30}) {
      final results = <AccZone>[];
      for (int i = 5; i < n - minBars; i++) {
        final a = atrAt(i);
        // Mesure range sur fenêtre glissante — exact copy from HTML
        for (int len = minBars; len <= min(maxBars, n - i - 2); len++) {
          final window = c.sublist(i, i + len);
          final hi = window.map((x) => x.high).reduce(max);
          final lo = window.map((x) => x.low).reduce(min);
          final rangeSize = hi - lo;
          // Range étroit = accumulation si < 1.5 ATR — exact copy
          if (rangeSize < a * 1.5) {
            // Vérifier que la barre suivante n'est pas encore dans le range
            if (i + len < n) {
              results.add(AccZone(
                startIdx: i, endIdx: i + len - 1,
                high: hi, low: lo, mid: (hi + lo) / 2, atr: a,
              ));
            }
            break; // prendre la fenêtre la plus longue possible — exact copy
          }
          // rangeSize >= a*1.5 → loop continues (exact copy: no break here)
        }
      }
      // Dédupliquer: garder seulement zones non-chevauchantes
      final deduped = <AccZone>[];
      for (final z in results) {
        final overlap = deduped.any((d) => z.startIdx <= d.endIdx && z.endIdx >= d.startIdx);
        if (!overlap) deduped.add(z);
      }
      return deduped;
    }

    final accZones = detectAccumulation();

    for (final acc in accZones) {
      final endIdx = acc.endIdx;
      if (endIdx + 1 >= n) continue;

      // ── Phase 2: chercher MANIPULATION juste après la zone — exact copy from HTML
      int    manipIdx = -1;
      String manipDir = '';

      final searchEnd = min(n - 1, endIdx + 8);
      for (int j = endIdx + 1; j <= searchEnd; j++) {
        final cv        = c[j];
        final breakUp   = cv.high > acc.high + acc.atr * 0.15;
        final breakDown = cv.low  < acc.low  - acc.atr * 0.15;
        final returnUp  = cv.close < acc.high + acc.atr * 0.2;
        final returnDown= cv.close > acc.low  - acc.atr * 0.2;

        // Fakeout UP: perce le haut mais close revient → manipulation bearish
        if (breakUp && returnUp && cv.close < cv.open) {
          manipIdx = j; manipDir = 'up'; break;
        }
        // Fakeout DOWN: perce le bas mais close revient → manipulation bullish
        if (breakDown && returnDown && cv.close > cv.open) {
          manipIdx = j; manipDir = 'down'; break;
        }
      }

      if (manipIdx == -1) continue;

      // ── Fakeout UP  → SELL / Fakeout DOWN → BUY
      final sigType  = manipDir == 'up' ? 'SELL' : 'BUY';
      final sigPrice = manipDir == 'up'
          ? c[manipIdx].high
          : c[manipIdx].low;

      final mc = c[manipIdx];
      final isBullManip = mc.close > mc.open;

      // ══════════════════════════════════════════════════
      // ── HYBRID SITUATION DETECTION
      // ══════════════════════════════════════════════════

      // ── S1: Pure Wick — body stays inside ACC, only wick pierces
      // Body = entre open et close
      final bodyTop    = max(mc.open, mc.close);
      final bodyBot    = min(mc.open, mc.close);
      final bodyInside = manipDir == 'up'
          ? bodyTop <= acc.high + acc.atr * 0.1   // body reste dans/près zone haute
          : bodyBot >= acc.low  - acc.atr * 0.1;  // body reste dans/près zone basse
      final wickPierces = manipDir == 'up'
          ? mc.high > acc.high + acc.atr * 0.15
          : mc.low  < acc.low  - acc.atr * 0.15;

      // ── S5: Inverse FVG (IFVG) — gap between C-1 and C+1 inversé
      // C[i-1].low > C[i+1].high (bullish IFVG) ou C[i-1].high < C[i+1].low (bearish IFVG)
      bool hasIFVG = false;
      double? ifvgLow, ifvgHigh;
      if (manipIdx >= 1 && manipIdx + 1 < n) {
        final prev = c[manipIdx - 1];
        final next = c[manipIdx + 1];
        if (sigType == 'BUY' && prev.low > next.high) {
          // Bullish IFVG: gap down = trap, true direction UP
          hasIFVG = true;
          ifvgLow  = next.high;
          ifvgHigh = prev.low;
        } else if (sigType == 'SELL' && prev.high < next.low) {
          // Bearish IFVG: gap up = trap, true direction DOWN
          hasIFVG = true;
          ifvgLow  = prev.high;
          ifvgHigh = next.low;
        }
      }

      // ── S4: Fair Value Gap (FVG) — gap DANS la direction du breakout
      // = distribution forte, entry seulement au retest du gap
      bool hasFVG = false;
      double? fvgLow, fvgHigh;
      if (manipIdx >= 1 && manipIdx + 1 < n) {
        final prev = c[manipIdx - 1];
        final next = c[manipIdx + 1];
        if (sigType == 'SELL' && prev.high < next.low) {
          // FVG bearish: gap up = momentum SELL fort → wait retest
          hasFVG = true;
          fvgLow  = prev.high;
          fvgHigh = next.low;
        } else if (sigType == 'BUY' && prev.low > next.high) {
          // FVG bullish: gap down = momentum BUY fort → wait retest
          hasFVG = true;
          fvgLow  = next.high;
          fvgHigh = prev.low;
        }
      }

      // ── S3 / S2: Body outside check + N+1 confirmation
      bool bodyOutside = false;
      bool nextReverts = false;
      if (manipDir == 'up') {
        bodyOutside = bodyTop > acc.high + acc.atr * 0.1;
        if (manipIdx + 1 < n) {
          final next = c[manipIdx + 1];
          nextReverts = next.close < acc.high + acc.atr * 0.2;
        }
      } else {
        bodyOutside = bodyBot < acc.low - acc.atr * 0.1;
        if (manipIdx + 1 < n) {
          final next = c[manipIdx + 1];
          nextReverts = next.close > acc.low - acc.atr * 0.2;
        }
      }

      // ── Determine situation + confidence + entry
      JPSituation situation;
      int confidence;
      String entryTiming;
      bool confirmed;
      String filterNote = '';

      if (hasIFVG) {
        // S5 — strongest manipulation trap
        situation   = JPSituation.ifvg;
        confidence  = 80;
        entryTiming = 'aggressive';
        confirmed   = true;
      } else if (bodyInside && wickPierces) {
        // S1 — classic pure wick stop hunt
        situation   = JPSituation.pureWick;
        confidence  = 85;
        entryTiming = 'aggressive';
        confirmed   = true;
      } else if (bodyOutside && nextReverts) {
        // S2 — body outside but N+1 pulls back inside
        situation   = JPSituation.bodyRevert;
        confidence  = 70;
        entryTiming = 'conservative';
        confirmed   = true;
      } else if (hasFVG) {
        // S4 — FVG: wait for retest before entry
        situation   = JPSituation.fvgRetest;
        confidence  = 65;
        entryTiming = 'wait_retest';
        confirmed   = true; // valid but needs patience
      } else if (bodyOutside && !nextReverts) {
        // S3 — breakout continuation: SKIP
        situation   = JPSituation.breakout;
        confidence  = 20;
        entryTiming = 'skip';
        confirmed   = false;
        filterNote  = 'Breakout continuation — distribution, not manipulation';
      } else {
        // Fallback — treat as S1 with lower confidence
        situation   = JPSituation.pureWick;
        confidence  = 60;
        entryTiming = 'aggressive';
        confirmed   = true;
      }

      final phase = JPPhase(
        acc: acc, manipIdx: manipIdx, manipDir: manipDir,
        distDir: manipDir == 'up' ? 'down' : 'up',
      );
      jpSignals.add(JPSignal(
        idx: manipIdx, type: sigType, price: sigPrice,
        phase: phase,
        confirmed: confirmed,
        filterNote: filterNote,
        situation: situation,
        confidence: confidence,
        entryTiming: entryTiming,
        fvgLow:  hasFVG || hasIFVG ? (fvgLow  ?? ifvgLow)  : null,
        fvgHigh: hasFVG || hasIFVG ? (fvgHigh ?? ifvgHigh) : null,
      ));
      jpPhases.add(phase);
    }
  }

  void setActiveJPSig(JPSignal? sig) {
    activeJPSig = (activeJPSig != null && sig != null && activeJPSig!.idx == sig.idx) ? null : sig;
    notifyListeners();
  }

  // ── EMA — exact copy from HTML calcEMA()
  static List<double?> calcEMA(List<double> data, int period) {
    final k   = 2 / (period + 1);
    final ema = <double?>[];
    double? prev;
    for (int i = 0; i < data.length; i++) {
      if (prev == null) {
        if (i < period - 1) { ema.add(null); continue; }
        final sma = data.sublist(0, period).reduce((a, b) => a + b) / period;
        ema.add(sma); prev = sma; continue;
      }
      final val = data[i] * k + prev * (1 - k);
      ema.add(val); prev = val;
    }
    return ema;
  }

  // ── RSI — exact copy from HTML calcRSI()
  static List<double?> calcRSI(List<double> closes, int period) {
    final rsi = List<double?>.filled(period, null);
    double gains = 0, losses = 0;
    for (int i = 1; i <= period; i++) {
      final d = closes[i] - closes[i - 1];
      if (d >= 0) gains += d; else losses += -d;
    }
    double avgG = gains / period, avgL = losses / period;
    rsi.add(avgL == 0 ? 100 : 100 - 100 / (1 + avgG / avgL));
    for (int i = period + 1; i < closes.length; i++) {
      final d = closes[i] - closes[i - 1];
      final g = d > 0 ? d : 0.0;
      final l = d < 0 ? -d : 0.0;
      avgG = (avgG * (period - 1) + g) / period;
      avgL = (avgL * (period - 1) + l) / period;
      rsi.add(avgL == 0 ? 100 : 100 - 100 / (1 + avgG / avgL));
    }
    return rsi;
  }

  // ─────────────────────────────────────────────
  // ── Trailing stop — exact copy from HTML runTrailingStop()
  // ─────────────────────────────────────────────
  void _runTrailingStop(double price) {
    if (!trailingStop) return;
    bool changed = false;
    final dist = trailingDist / 100;
    for (final t in trades.where((t) => t.status == 'open' && t.sl != null)) {
      if (t.direction == 'long') {
        final ns = price * (1 - dist);
        if (ns > t.sl!) { t.sl = double.parse(ns.toStringAsFixed(6)); t.slTrailed = true; changed = true; }
      } else {
        final ns = price * (1 + dist);
        if (ns < t.sl!) { t.sl = double.parse(ns.toStringAsFixed(6)); t.slTrailed = true; changed = true; }
      }
    }
    if (changed) saveTrades();
  }

  void _checkPendingSignals(double price) {
    bool changed = false;
    for (final t in trades.where((t) => t.status == 'pending')) {
      bool inZone;
      if (t.entryZoneLow != null && t.entryZoneHigh != null) {
        inZone = price >= t.entryZoneLow! && price <= t.entryZoneHigh!;
      } else {
        inZone = (price - t.entry).abs() / t.entry < 0.001;
      }
      if (inZone) { t.status = 'open'; changed = true; }
    }
    if (changed) { saveTrades(); notifyListeners(); }
  }

  // ─────────────────────────────────────────────
  // ── Trade management
  // ─────────────────────────────────────────────
  void addTrade(Trade t)    { trades.insert(0, t); saveTrades(); notifyListeners(); }
  void removeTrade(int id)  { trades.removeWhere((t) => t.id == id); saveTrades(); notifyListeners(); }
  void clearAllTrades()     { trades.clear(); saveTrades(); notifyListeners(); }

  // ─────────────────────────────────────────────
  // ── Persistence
  // ─────────────────────────────────────────────
  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    groqKey       = p.getString('groqKey')   ?? '';
    groqModel     = p.getString('groqModel') ?? 'llama-3.3-70b-versatile';
    trailingStop  = p.getBool('trailingStop')  ?? false;
    trailingDist  = p.getDouble('trailingDist') ?? 0.5;
    jpAutoTPSL    = p.getBool('jpAutoTPSL')   ?? false;
    jpTPAtr       = p.getDouble('jpTPAtr')    ?? 2.0;
    jpSLAtr       = p.getDouble('jpSLAtr')    ?? 1.0;
    jpAlarm       = p.getBool('jpAlarm')      ?? false;
    final tradesJson = p.getString('kintana_trades') ?? '[]';
    trades = (jsonDecode(tradesJson) as List).map((j) => Trade.fromJson(j as Map<String, dynamic>)).toList();
    connect();
    notifyListeners();
  }

  Future<void> saveTrades() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('kintana_trades', jsonEncode(trades.map((t) => t.toJson()).toList()));
  }

  Future<void> saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('groqKey',    groqKey);
    await p.setString('groqModel',  groqModel);
    await p.setBool('trailingStop', trailingStop);
    await p.setDouble('trailingDist', trailingDist);
    await p.setBool('jpAutoTPSL',   jpAutoTPSL);
    await p.setDouble('jpTPAtr',    jpTPAtr);
    await p.setDouble('jpSLAtr',    jpSLAtr);
    await p.setBool('jpAlarm',      jpAlarm);
  }

  @override
  void dispose() { _ws?.sink.close(); replayTimer?.cancel(); super.dispose(); }
}

class _ReplayTick {
  final int time;
  final double price;
  final int candleIdx;
  const _ReplayTick({required this.time, required this.price, required this.candleIdx});
}
