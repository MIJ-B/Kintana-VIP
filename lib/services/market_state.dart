import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

const int kDerivAppId = 129691;

// LTF map: HTF granularity -> LTF granularity (seconds)
const Map<int, int> kLTFMap = {
  60:    120,   // M1  -> M2
  120:   120,   // M2  -> M2
  300:   120,   // M5  -> M2
  900:   300,   // M15 -> M5
  1800:  300,   // M30 -> M5
  3600:  300,   // H1  -> M5
  14400: 900,   // H4  -> M15
  86400: 3600,  // D1  -> H1
};

class MarketState extends ChangeNotifier {
  // -- Symbol
  String sym   = 'frxXAUUSD';
  String sname = 'Gold / US Dollar';
  int tf = 900;

  // -- Prices
  double? price;
  double? prevPrice;
  double? open0;
  double? bidPrice;
  double? askPrice;

  // -- Candles (HTF)
  List<Candle> candles = [];

  // -- LTF candles for confirmation
  List<Candle> ltfCandles = [];
  int get ltfTf => kLTFMap[tf] ?? 300;
  WebSocketChannel? _ltfWs;

  // -- View
  double zoom    = 60;
  double offset  = 0;
  double yOffset = 0;

  // -- WS
  WebSocketChannel? _ws;
  bool wsOk       = false;
  bool _reconnecting = false;
  int  _rid = 1;

  // -- Replay
  bool isReplay    = false;
  List<Candle> replayAll   = [];
  List<_ReplayTick> replayTicks = [];
  int  replayIdx     = 0;
  int  replayTickIdx = 0;
  bool replayPlaying = false;
  Timer? replayTimer;
  int  replaySpeed = 400;

  // -- Trades
  List<Trade> trades = [];

  // -- Settings
  bool trailingStop  = false;
  double trailingDist = 0.5;
  String groqKey   = '';
  String groqModel = 'llama-3.3-70b-versatile';

  // -- Supply & Demand
  bool sdActive = false;
  List<SDZone> sdZones = [];
  int _sdIdCounter = 1;
  int sdWins   = 0;
  int sdLosses = 0;
  double get sdWinRate =>
      (sdWins + sdLosses) == 0 ? 0 : sdWins / (sdWins + sdLosses) * 100;
  String? sdLastResultMsg;

  // -- Alarm state
  bool alarmRinging  = false;  // true = alarm is sounding
  String alarmReason = '';     // reason shown on stop button

  // Callback injected by chart_screen to trigger audio + vibration
  VoidCallback? onAlarmStart;

  MarketState() { _loadPrefs(); }

  // ============================================================
  // -- Candle helpers
  // ============================================================
  List<Candle> getCandles() {
    if (!isReplay) return candles;
    if (replayTicks.isEmpty) {
      return replayAll.sublist(0, replayIdx.clamp(0, replayAll.length));
    }
    final tickIdx  = replayTickIdx.clamp(0, replayTicks.length - 1);
    final curTick  = replayTicks[tickIdx];
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

  double calcATR({int period = 10, List<Candle>? src}) {
    final c = src ?? getCandles();
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
    zoom   = zoom.clamp(5.0, n.toDouble());
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

  // ============================================================
  // -- WebSocket HTF
  // ============================================================
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
    _send({'ticks_history': sym, 'end': 'latest', 'count': 300,
           'style': 'candles', 'granularity': tf});
    _send({'ticks_history': sym, 'end': 'latest', 'count': 1,
           'style': 'candles', 'granularity': tf, 'subscribe': 1});
    wsOk = true;
    _connectLTF();
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
      Future.delayed(const Duration(seconds: 3), () {
        _reconnecting = false; connect();
      });
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
      _checkSDZones(price!);
      notifyListeners();
    }
    if (d['candles'] != null) {
      candles = (d['candles'] as List)
          .map((c) => Candle.fromMap(c as Map<String, dynamic>))
          .toList();
      open0  = candles.isNotEmpty ? candles.first.open : null;
      zoom   = min(60, candles.length.toDouble());
      offset = max(0, candles.length - zoom.round()).toDouble();
      if (sdActive) detectSDZones();
      notifyListeners();
    }
    if (d['ohlc'] != null) {
      final o     = d['ohlc'] as Map<String, dynamic>;
      final epoch = (o['open_time'] as num).toInt();
      final cn = Candle(
        time:  epoch,
        open:  double.parse(o['open'].toString()),
        high:  double.parse(o['high'].toString()),
        low:   double.parse(o['low'].toString()),
        close: double.parse(o['close'].toString()),
      );
      final idx = candles.indexWhere((c) => c.time == epoch);
      if (idx >= 0) candles[idx] = cn;
      else { candles.add(cn); if (candles.length > 500) candles.removeAt(0); }
      if (sdActive) detectSDZones();
      notifyListeners();
    }
  }

  // ============================================================
  // -- WebSocket LTF (lower timeframe confirmation)
  // ============================================================
  void _connectLTF() {
    if (isReplay) return;
    _ltfWs?.sink.close();
    ltfCandles.clear();
    final ltf = ltfTf;
    final ws = WebSocketChannel.connect(
      Uri.parse('wss://ws.binaryws.com/websockets/v3?app_id=$kDerivAppId'),
    );
    _ltfWs = ws;
    int rid2 = 9000;
    ws.stream.listen((raw) {
      final d = jsonDecode(raw as String) as Map<String, dynamic>;
      if (d['error'] != null) return;
      if (d['candles'] != null) {
        ltfCandles = (d['candles'] as List)
            .map((c) => Candle.fromMap(c as Map<String, dynamic>))
            .toList();
        if (sdActive) _checkLTFConfirmation();
        notifyListeners();
      }
      if (d['ohlc'] != null) {
        final o     = d['ohlc'] as Map<String, dynamic>;
        final epoch = (o['open_time'] as num).toInt();
        final cn = Candle(
          time:  epoch,
          open:  double.parse(o['open'].toString()),
          high:  double.parse(o['high'].toString()),
          low:   double.parse(o['low'].toString()),
          close: double.parse(o['close'].toString()),
        );
        final idx = ltfCandles.indexWhere((c) => c.time == epoch);
        if (idx >= 0) ltfCandles[idx] = cn;
        else { ltfCandles.add(cn); if (ltfCandles.length > 200) ltfCandles.removeAt(0); }
        if (sdActive) _checkLTFConfirmation();
        notifyListeners();
      }
    }, onError: (_) {});
    ws.sink.add(jsonEncode({'ticks_history': sym, 'end': 'latest',
        'count': 100, 'style': 'candles', 'granularity': ltf,
        'subscribe': 1, 'req_id': rid2++}));
  }

  void changeSymbol(Market m) {
    sym = m.symbol; sname = m.name; offset = 0;
    price = null; prevPrice = null; open0 = null;
    candles.clear(); ltfCandles.clear();
    sdZones.clear();
    if (isReplay) { replayAll.clear(); replayIdx = 0; notifyListeners(); return; }
    notifyListeners();
    if (wsOk) {
      _send({'forget_all': 'ticks'});
      _send({'forget_all': 'candles'});
      Future.delayed(const Duration(milliseconds: 200), () {
        _send({'ticks': sym, 'subscribe': 1});
        _send({'ticks_history': sym, 'end': 'latest', 'count': 300,
               'style': 'candles', 'granularity': tf});
        _send({'ticks_history': sym, 'end': 'latest', 'count': 1,
               'style': 'candles', 'granularity': tf, 'subscribe': 1});
        _connectLTF();
      });
    }
  }

  void changeTimeframe(int newTf) {
    tf = newTf; candles.clear(); ltfCandles.clear();
    offset = 0; sdZones.clear();
    notifyListeners();
    if (!isReplay && wsOk) {
      _send({'forget_all': 'candles'});
      Future.delayed(const Duration(milliseconds: 200), () {
        _send({'ticks_history': sym, 'end': 'latest', 'count': 300,
               'style': 'candles', 'granularity': tf});
        _send({'ticks_history': sym, 'end': 'latest', 'count': 1,
               'style': 'candles', 'granularity': tf, 'subscribe': 1});
        _connectLTF();
      });
    }
  }

  // ============================================================
  // -- Zoom / Pan
  // ============================================================
  void zoomAround(double factor, double pivotScreenFraction) {
    final c = getCandles();
    if (c.isEmpty) return;
    clampView(c);
    final pivotCandle = offset + pivotScreenFraction * zoom;
    final newZoom = (zoom / factor).clamp(5.0, c.length.toDouble()) as double;
    offset = pivotCandle - pivotScreenFraction * newZoom;
    zoom   = newZoom;
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
    final c    = getCandles();
    final step = max(1, (zoom * 0.15).round());
    offset = min((c.length - zoom.round()).toDouble(), offset + step);
    notifyListeners();
  }

  // ============================================================
  // -- Replay
  // ============================================================
  void switchToReplay() {
    isReplay = true; _stopReplay();
    replayAll.clear(); replayTicks.clear();
    replayIdx = 0; replayTickIdx = 0;
    _ws?.sink.close(); _ltfWs?.sink.close();
    wsOk = false;
    notifyListeners();
  }

  void switchToLive() {
    isReplay = false; _stopReplay();
    replayAll.clear(); candles.clear(); ltfCandles.clear();
    offset = 0; sdZones.clear();
    connect(); notifyListeners();
  }

  Future<void> loadReplayData(String dateStr) async {
    final dt         = DateTime.parse('${dateStr}T00:00:00Z');
    final startEpoch = dt.millisecondsSinceEpoch ~/ 1000;
    final endEpoch   = startEpoch + 86400;
    replayAll.clear(); replayTicks.clear();
    replayIdx = 0; replayTickIdx = 0; offset = 0;
    notifyListeners();
    final ws   = WebSocketChannel.connect(
        Uri.parse('wss://ws.binaryws.com/websockets/v3?app_id=$kDerivAppId'));
    final comp = Completer<void>();
    ws.stream.listen((raw) {
      final d = jsonDecode(raw as String) as Map<String, dynamic>;
      if (d['error'] != null) { comp.completeError(d['error']['message']); return; }
      if (d['candles'] != null) {
        final loaded = (d['candles'] as List)
            .map((c) => Candle.fromMap(c as Map<String, dynamic>))
            .toList();
        replayAll   = loaded;
        replayTicks = _generateTicks(loaded);

        // -- Generate simulated LTF candles for replay
        ltfCandles = _generateLTFCandles(loaded, ltfTf, tf);

        replayIdx   = 0; replayTickIdx = 0;
        zoom   = min(60, loaded.length.toDouble());
        offset = 0;
        if (sdActive) detectSDZones();
        notifyListeners();
        ws.sink.close(); comp.complete();
      }
    }, onError: (e) => comp.completeError(e));
    ws.sink.add(jsonEncode({'ticks_history': sym, 'start': startEpoch,
        'end': endEpoch, 'count': 1000, 'style': 'candles',
        'granularity': tf, 'req_id': 1}));
    await comp.future;
  }

  // -- Generate simulated LTF candles from HTF candles for replay
  List<Candle> _generateLTFCandles(List<Candle> htf, int ltf, int htfTf) {
    if (htf.isEmpty) return [];
    final ratio  = (htfTf / ltf).round().clamp(2, 20);
    final result = <Candle>[];
    final rng    = Random();
    for (final c in htf) {
      for (int i = 0; i < ratio; i++) {
        final t     = c.time + i * ltf;
        final frac  = i / ratio;
        final noise = (c.high - c.low) * 0.1;
        final o = c.open + (c.close - c.open) * frac + (rng.nextDouble() - 0.5) * noise;
        final cl = c.open + (c.close - c.open) * ((i + 1) / ratio) + (rng.nextDouble() - 0.5) * noise;
        final hi = max(o, cl) + rng.nextDouble() * noise * 0.5;
        final lo = min(o, cl) - rng.nextDouble() * noise * 0.5;
        result.add(Candle(
          time: t, open: o.clamp(c.low, c.high),
          high: hi.clamp(c.low, c.high * 1.001),
          low:  lo.clamp(c.low * 0.999, c.high),
          close: cl.clamp(c.low, c.high),
        ));
      }
    }
    return result;
  }

  List<_ReplayTick> _generateTicks(List<Candle> candles) {
    final ticks = <_ReplayTick>[];
    final rng   = Random();
    for (int ci = 0; ci < candles.length; ci++) {
      final c   = candles[ci];
      final n   = 15 + rng.nextInt(6);
      final bull = c.close >= c.open;
      final p0  = c.open;
      final p1  = bull ? c.open - (c.open - c.low) * 0.3 : c.open + (c.high - c.open) * 0.3;
      final p2  = bull ? c.high : c.low;
      final p3  = bull ? c.low  : c.high;
      final p4  = c.close;
      final keyPts = [p0, p1, p2, p3, p4];
      final seg    = (n / (keyPts.length - 1)).floor();
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
          ticks.add(_ReplayTick(
              time: c.time + (s * (tf / n)).floor(),
              price: px, candleIdx: ci));
        }
      }
      if (ticks.isNotEmpty && ticks.last.candleIdx == ci) {
        ticks[ticks.length - 1] = _ReplayTick(
            time: ticks.last.time, price: c.close, candleIdx: ci);
      }
    }
    return ticks;
  }

  void toggleReplayPlay() =>
      replayPlaying ? _stopReplay() : _startReplay();

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
    if (replayPlaying) {
      replayTimer = Timer(
          Duration(milliseconds: (replaySpeed / 4).round()), _playTick);
    }
  }

  void _advanceTick() {
    if (replayTicks.isEmpty) return;
    if (replayTickIdx < replayTicks.length - 1) {
      replayTickIdx++;
      final tick = replayTicks[replayTickIdx];
      replayIdx  = tick.candleIdx + 1;
      final candlePrice = replayAll[tick.candleIdx].close;
      _runTrailingStop(candlePrice);
      _checkPendingSignals(candlePrice);
      _checkSDZones(candlePrice);
      // Sync LTF candles for replay position
      _syncReplayLTF(tick.candleIdx);
    } else {
      _stopReplay();
    }
    notifyListeners();
  }

  void _syncReplayLTF(int htfIdx) {
    // LTF candles up to current replay HTF index
    if (ltfCandles.isEmpty) return;
    final ratio = (tf / ltfTf).round().clamp(2, 20);
    final ltfIdx = (htfIdx * ratio).clamp(0, ltfCandles.length - 1);
    // Nothing to do - ltfCandles already generated for full range
    // _checkLTFConfirmation uses the full list; filter by current time
    if (sdActive) _checkLTFConfirmationAt(htfIdx);
  }

  void replaySeek(double pct) {
    replayTickIdx = (pct * (replayTicks.length - 1))
        .round()
        .clamp(0, max(0, replayTicks.length - 1));
    if (replayTicks.isNotEmpty) {
      replayIdx = replayTicks[replayTickIdx].candleIdx + 1;
    }
    notifyListeners();
  }

  double get replayProgress =>
      replayTicks.isEmpty ? 0 : replayTickIdx / (replayTicks.length - 1);

  DateTime? get replayCurrentTime {
    if (replayTicks.isEmpty || replayTickIdx >= replayTicks.length) return null;
    return DateTime.fromMillisecondsSinceEpoch(
        replayTicks[replayTickIdx].time * 1000);
  }

  // ============================================================
  // -- Trade management
  // ============================================================
  void addTrade(Trade t)   { trades.insert(0, t); saveTrades(); notifyListeners(); }
  void removeTrade(int id) { trades.removeWhere((t) => t.id == id); saveTrades(); notifyListeners(); }
  void clearAllTrades()    { trades.clear(); saveTrades(); notifyListeners(); }

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

  // ============================================================
  // -- SUPPLY & DEMAND ENGINE
  // ============================================================

  void toggleSD() {
    sdActive = !sdActive;
    if (sdActive) {
      detectSDZones();
      if (!isReplay) _connectLTF();
    } else {
      sdZones.clear();
      alarmRinging = false;
    }
    notifyListeners();
  }

  // -- Step 1: Detect Supply & Demand zones from HTF candles
  void detectSDZones() {
    sdZones.clear();
    final c = getCandles();
    if (c.length < 10) return;
    final n = c.length;

    double atrVal = calcATR(src: c);
    if (atrVal == 0) atrVal = c.last.high - c.last.low;

    for (int i = 1; i < n - 1; i++) {
      final cv    = c[i];
      final body  = (cv.close - cv.open).abs();
      final range = cv.high - cv.low;
      if (range == 0) continue;

      // Relaxed: strong if body dominant OR significant size
      final isStrong = (body > range * 0.45) || (body > atrVal * 0.5);
      if (!isStrong) continue;

      final next2 = c[i + 2];

      // -- SUPPLY zone (bearish origin)
      if (cv.close < cv.open) {
        final momentum = (cv.close - next2.low).abs();
        if (momentum < atrVal * 0.2) continue;
        final zHigh = max(cv.open, cv.close);
        final zLow  = min(cv.open, cv.close);
        sdZones.add(SDZone(
          id: _sdIdCounter++, type: SDZoneType.supply,
          zoneHigh: zHigh, zoneLow: zLow,
          originIdx: i, originClose: cv.close,
        ));
      }

      // -- DEMAND zone (bullish origin)
      if (cv.close > cv.open) {
        final momentum = (next2.high - cv.close).abs();
        if (momentum < atrVal * 0.2) continue;
        final zHigh = max(cv.open, cv.close);
        final zLow  = min(cv.open, cv.close);
        sdZones.add(SDZone(
          id: _sdIdCounter++, type: SDZoneType.demand,
          zoneHigh: zHigh, zoneLow: zLow,
          originIdx: i, originClose: cv.close,
        ));
      }
    }
    // Keep only the 8 most recent zones to avoid clutter
    if (sdZones.length > 8) {
      sdZones = sdZones.sublist(sdZones.length - 8);
    }
    notifyListeners();
  }

  // -- Step 2: Price enters zone (HTF tick check)
  void _checkSDZones(double currentPrice) {
    if (!sdActive || sdZones.isEmpty) return;
    bool changed = false;
    for (final zone in sdZones) {
      if (zone.status == SDZoneStatus.hitTP ||
          zone.status == SDZoneStatus.hitSL ||
          zone.status == SDZoneStatus.expired) continue;
      if (zone.status == SDZoneStatus.waiting && zone.priceInZone(currentPrice)) {
        zone.status = SDZoneStatus.entered;
        changed = true;
      }
      // Check TP / SL hit
      if (zone.status == SDZoneStatus.confirmed &&
          zone.entry != null && zone.sl != null && zone.tp != null) {
        bool hitTP = false, hitSL = false;
        if (zone.isBuy) {
          hitTP = currentPrice >= zone.tp!;
          hitSL = currentPrice <= zone.sl!;
        } else {
          hitTP = currentPrice <= zone.tp!;
          hitSL = currentPrice >= zone.sl!;
        }
        if (hitTP || hitSL) {
          zone.won    = hitTP;
          zone.status = hitTP ? SDZoneStatus.hitTP : SDZoneStatus.hitSL;
          if (hitTP) sdWins++; else sdLosses++;
          sdLastResultMsg = '${hitTP ? "TP HIT" : "SL HIT"} - ${zone.isBuy ? "BUY" : "SELL"} zone @ ${fp(zone.entry!)}\nWin Rate: ${sdWinRate.toStringAsFixed(1)}% (${sdWins}W / ${sdLosses}L)';
          changed = true;
          _saveSDStats();
        }
      }
    }
    if (changed) notifyListeners();
  }

  // -- Step 3: LTF confirmation scan (live)
  void _checkLTFConfirmation() {
    _checkLTFConfirmationAt(null);
  }

  void _checkLTFConfirmationAt(int? htfReplayIdx) {
    if (!sdActive || sdZones.isEmpty || ltfCandles.isEmpty) return;
    final atr = calcATR();
    bool changed = false;
    final int lastLTF;
    if (htfReplayIdx != null) {
      // Replay: use LTF candles up to equivalent time
      final ratio = (tf / ltfTf).round().clamp(2, 20);
      lastLTF = min(ltfCandles.length - 1, htfReplayIdx * ratio + ratio - 1);
    } else {
      lastLTF = ltfCandles.length - 1;
    }
    if (lastLTF < 0) return;

    for (final zone in sdZones) {
      if (zone.status != SDZoneStatus.entered) continue;
      if (zone.ltfConfirmed) continue;

      // Scan last 5 LTF candles for rejection pattern
      final from = max(0, lastLTF - 4);
      for (int i = from; i <= lastLTF; i++) {
        final ltf = ltfCandles[i];
        final inZone = ltf.low <= zone.zoneHigh && ltf.high >= zone.zoneLow;
        if (!inZone) continue;

        final body    = (ltf.close - ltf.open).abs();
        final range   = ltf.high - ltf.low;
        if (range == 0) continue;
        final isBull  = ltf.close > ltf.open;
        final isBear  = ltf.close < ltf.open;
        final isPinBar    = body < range * 0.4;
        final isEngulfing = body > range * 0.7;
        final isReversal  =
            (zone.isBuy  && (isPinBar || (isEngulfing && isBull))) ||
            (zone.isSell && (isPinBar || (isEngulfing && isBear)));

        if (isReversal) {
          zone.ltfConfirmed  = true;
          zone.ltfConfirmIdx = i;
          // Set entry / SL / TP
          if (zone.isBuy) {
            zone.entry = zone.zoneLow + zone.zoneSize * 0.5;
            zone.sl    = zone.zoneLow - atr * 0.3;
            zone.tp    = zone.entry!  + atr * 2.5;
          } else {
            zone.entry = zone.zoneHigh - zone.zoneSize * 0.5;
            zone.sl    = zone.zoneHigh + atr * 0.3;
            zone.tp    = zone.entry!   - atr * 2.5;
          }
          zone.status = SDZoneStatus.confirmed;
          changed = true;
          // Trigger alarm
          _triggerAlarm('${zone.isBuy ? "BUY" : "SELL"} signal confirmed @ ${fp(zone.entry!)}');
          break;
        }
      }
    }
    if (changed) notifyListeners();
  }

  // ============================================================
  // -- Alarm
  // ============================================================
  void _triggerAlarm(String reason) {
    alarmRinging = true;
    alarmReason  = reason;
    onAlarmStart?.call();
    notifyListeners();
  }

  void stopAlarm() {
    alarmRinging = false;
    alarmReason  = '';
    notifyListeners();
  }

  // ============================================================
  // -- Persistence
  // ============================================================
  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    groqKey      = p.getString('groqKey')    ?? '';
    groqModel    = p.getString('groqModel')  ?? 'llama-3.3-70b-versatile';
    trailingStop = p.getBool('trailingStop') ?? false;
    trailingDist = p.getDouble('trailingDist') ?? 0.5;
    final tradesJson = p.getString('kintana_trades') ?? '[]';
    trades = (jsonDecode(tradesJson) as List)
        .map((j) => Trade.fromJson(j as Map<String, dynamic>))
        .toList();
    await _loadSDStats();
    connect();
    notifyListeners();
  }

  Future<void> saveTrades() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('kintana_trades',
        jsonEncode(trades.map((t) => t.toJson()).toList()));
  }

  Future<void> saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('groqKey',      groqKey);
    await p.setString('groqModel',    groqModel);
    await p.setBool('trailingStop',   trailingStop);
    await p.setDouble('trailingDist', trailingDist);
  }

  Future<void> _saveSDStats() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('sdWins',   sdWins);
    await p.setInt('sdLosses', sdLosses);
  }

  Future<void> _loadSDStats() async {
    final p = await SharedPreferences.getInstance();
    sdWins   = p.getInt('sdWins')   ?? 0;
    sdLosses = p.getInt('sdLosses') ?? 0;
  }

  void clearSDResult(int zoneId) {
    sdZones.removeWhere((z) =>
        z.id == zoneId &&
        (z.status == SDZoneStatus.hitTP || z.status == SDZoneStatus.hitSL));
    notifyListeners();
  }

  // EMA helper (used by joro_screen context builder)
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

  @override
  void dispose() {
    _ws?.sink.close();
    _ltfWs?.sink.close();
    replayTimer?.cancel();
    super.dispose();
  }
}


class _ReplayTick {
  final int time;
  final double price;
  final int candleIdx;
  const _ReplayTick({required this.time, required this.price, required this.candleIdx});
}
