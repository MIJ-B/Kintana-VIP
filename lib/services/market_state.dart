import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

const int kDerivAppId = 129691;

class MarketState extends ChangeNotifier {
  // ── Symbol
  String sym = 'frxXAUUSD';
  String sname = 'Gold / US Dollar';
  int tf = 900; // seconds

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
  Candle? _liveCandle;

  // ── Trades
  List<Trade> trades = [];

  // ── JOROpredict signals
  bool joropredictActive = false;
  List<_JPSignal> jpSignals = [];
  JOROSignal? activeJPSig;

  // ── Settings
  bool trailingStop = false;
  double trailingDist = 0.5;
  bool jpAutoTPSL = false;
  double jpTPAtr = 2.0;
  double jpSLAtr = 1.0;
  bool jpAlarm = false;
  Map<int, bool> tfAlarms = {};
  String groqKey = '';
  String groqModel = 'llama-3.3-70b-versatile';

  // ── Constructor
  MarketState() {
    _loadPrefs();
  }

  // ── Helpers
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

    // Build current candle from ticks
    final candleTicks = replayTicks
        .sublist(0, tickIdx + 1)
        .where((t) => t.candleIdx == candleIdx)
        .toList();

    if (candleTicks.isEmpty) return [...done, base];

    final prices = candleTicks.map((t) => t.price).toList();
    final liveCand = Candle(
      time: base.time,
      open: base.open,
      high: prices.reduce(max),
      low: prices.reduce(min),
      close: prices.last,
    );
    return [...done, liveCand];
  }

  double calcATR({int period = 10}) {
    final c = getCandles();
    if (c.length < 2) return 0;
    final p = min(period, c.length - 1);
    double s = 0;
    for (int i = c.length - p; i < c.length; i++) {
      s += max(c[i].high - c[i].low,
          max((c[i].high - c[i - 1].close).abs(),
              (c[i].low - c[i - 1].close).abs()));
    }
    return s / p;
  }

  void clampView(List<Candle> c) {
    final n = c.length;
    if (n == 0) { zoom = 60; offset = 0; return; }
    zoom = zoom.clamp(5, n.toDouble());
    final maxOffset = max(0, n - 3).toDouble();
    offset = offset.clamp(0, maxOffset);
  }

  ({int s, int e, int count}) visibleRange() {
    final c = getCandles();
    if (c.isEmpty) return (s: 0, e: 0, count: 0);
    clampView(c);
    final s = offset.round().clamp(0, c.length - 1);
    final e = (s + zoom.round() - 1).clamp(s, c.length - 1);
    return (s: s, e: e, count: e - s + 1);
  }

  // ── WebSocket
  void connect() {
    if (isReplay) return;
    _ws?.sink.close();
    wsOk = false;
    _ws = WebSocketChannel.connect(
      Uri.parse('wss://ws.binaryws.com/websockets/v3?app_id=$kDerivAppId'),
    );
    _ws!.stream.listen(
      (raw) => _onMsg(jsonDecode(raw as String)),
      onDone: _onClose,
      onError: (_) => _onClose(),
    );
    _send({'ticks': sym, 'subscribe': 1});
    _send({'ticks_history': sym, 'end': 'latest', 'count': 300, 'style': 'candles', 'granularity': tf});
    _send({'ticks_history': sym, 'end': 'latest', 'count': 1, 'style': 'candles', 'granularity': tf, 'subscribe': 1});
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
      Future.delayed(const Duration(seconds: 3), () {
        _reconnecting = false;
        connect();
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
        if (price! < l.low) l.low = price!;
      }
      _runTrailingStop(price!);
      _checkPendingSignals(price!);
      notifyListeners();
    }

    if (d['candles'] != null) {
      candles = (d['candles'] as List)
          .map((c) => Candle.fromMap(c as Map<String, dynamic>))
          .toList();
      open0 = candles.isNotEmpty ? candles.first.open : null;
      zoom = min(60, candles.length.toDouble());
      offset = max(0, candles.length - zoom.round()).toDouble();
      notifyListeners();
    }

    if (d['ohlc'] != null) {
      final o = d['ohlc'] as Map<String, dynamic>;
      final epoch = (o['open_time'] as num).toInt();
      final cn = Candle(
        time: epoch,
        open: double.parse(o['open'].toString()),
        high: double.parse(o['high'].toString()),
        low: double.parse(o['low'].toString()),
        close: double.parse(o['close'].toString()),
      );
      final idx = candles.indexWhere((c) => c.time == epoch);
      if (idx >= 0) {
        candles[idx] = cn;
      } else {
        candles.add(cn);
        if (candles.length > 500) candles.removeAt(0);
      }
      notifyListeners();
    }
  }

  // ── Change symbol
  void changeSymbol(Market m) {
    sym = m.symbol;
    sname = m.name;
    offset = 0;
    price = null;
    prevPrice = null;
    open0 = null;
    candles.clear();
    if (isReplay) {
      replayAll.clear();
      replayIdx = 0;
      notifyListeners();
      return;
    }
    notifyListeners();
    if (wsOk) {
      _send({'forget_all': 'ticks'});
      _send({'forget_all': 'candles'});
      Future.delayed(const Duration(milliseconds: 200), () {
        _send({'ticks': sym, 'subscribe': 1});
        _send({'ticks_history': sym, 'end': 'latest', 'count': 300, 'style': 'candles', 'granularity': tf});
        _send({'ticks_history': sym, 'end': 'latest', 'count': 1, 'style': 'candles', 'granularity': tf, 'subscribe': 1});
      });
    }
  }

  // ── Change timeframe
  void changeTimeframe(int newTf) {
    tf = newTf;
    candles.clear();
    offset = 0;
    notifyListeners();
    if (!isReplay && wsOk) {
      _send({'forget_all': 'candles'});
      Future.delayed(const Duration(milliseconds: 200), () {
        _send({'ticks_history': sym, 'end': 'latest', 'count': 300, 'style': 'candles', 'granularity': tf});
        _send({'ticks_history': sym, 'end': 'latest', 'count': 1, 'style': 'candles', 'granularity': tf, 'subscribe': 1});
      });
    }
  }

  // ── Zoom
  void zoomAround(double factor, double pivotScreenFraction) {
    final c = getCandles();
    if (c.isEmpty) return;
    clampView(c);
    final pivotCandle = offset + pivotScreenFraction * zoom;
    final newZoom = (zoom / factor).clamp(5, c.length.toDouble());
    offset = pivotCandle - pivotScreenFraction * newZoom;
    zoom = newZoom;
    clampView(c);
    notifyListeners();
  }

  void zoomIn(double pivotFrac) => zoomAround(1.4, pivotFrac);
  void zoomOut(double pivotFrac) => zoomAround(1 / 1.4, pivotFrac);
  void zoomReset() {
    final c = getCandles();
    zoom = min(60, c.length.toDouble());
    offset = max(0, c.length - zoom.round()).toDouble();
    yOffset = 0;
    notifyListeners();
  }

  void panLeft() {
    final step = max(1, (zoom * 0.15).round());
    offset = max(0, offset - step);
    notifyListeners();
  }

  void panRight() {
    final c = getCandles();
    final step = max(1, (zoom * 0.15).round());
    offset = min(c.length - zoom.round().toDouble(), offset + step);
    notifyListeners();
  }

  // ── Replay
  void switchToReplay() {
    isReplay = true;
    _stopReplay();
    replayAll.clear();
    replayTicks.clear();
    replayIdx = 0;
    replayTickIdx = 0;
    _ws?.sink.close();
    wsOk = false;
    notifyListeners();
  }

  void switchToLive() {
    isReplay = false;
    _stopReplay();
    replayAll.clear();
    candles.clear();
    offset = 0;
    connect();
    notifyListeners();
  }

  Future<void> loadReplayData(String dateStr) async {
    final dt = DateTime.parse('${dateStr}T00:00:00Z');
    final startEpoch = dt.millisecondsSinceEpoch ~/ 1000;
    final endEpoch = startEpoch + 86400;

    replayAll.clear();
    replayTicks.clear();
    replayIdx = 0;
    replayTickIdx = 0;
    _liveCandle = null;
    offset = 0;
    notifyListeners();

    final ws = WebSocketChannel.connect(
      Uri.parse('wss://ws.binaryws.com/websockets/v3?app_id=$kDerivAppId'),
    );
    final comp = Completer<void>();

    ws.stream.listen((raw) {
      final d = jsonDecode(raw as String) as Map<String, dynamic>;
      if (d['error'] != null) {
        comp.completeError(d['error']['message']);
        return;
      }
      if (d['candles'] != null) {
        final loadedCandles = (d['candles'] as List)
            .map((c) => Candle.fromMap(c as Map<String, dynamic>))
            .toList();
        replayAll = loadedCandles;
        replayTicks = _generateTicks(loadedCandles);
        replayIdx = 0;
        replayTickIdx = 0;
        zoom = min(60, loadedCandles.length.toDouble());
        offset = 0;
        notifyListeners();
        ws.sink.close();
        comp.complete();
      }
    }, onError: (e) => comp.completeError(e));

    ws.sink.add(jsonEncode({
      'ticks_history': sym,
      'start': startEpoch,
      'end': endEpoch,
      'count': 1000,
      'style': 'candles',
      'granularity': tf,
      'req_id': 1,
    }));

    await comp.future;
  }

  List<_ReplayTick> _generateTicks(List<Candle> candles) {
    final ticks = <_ReplayTick>[];
    final rng = Random();
    for (int ci = 0; ci < candles.length; ci++) {
      final c = candles[ci];
      final n = 15 + rng.nextInt(6);
      final bull = c.close >= c.open;
      final p0 = c.open;
      final p1 = bull ? c.open - (c.open - c.low) * 0.3 : c.open + (c.high - c.open) * 0.3;
      final p2 = bull ? c.high : c.low;
      final p3 = bull ? c.low : c.high;
      final p4 = c.close;
      final keyPts = [p0, p1, p2, p3, p4];
      final seg = (n / (keyPts.length - 1)).floor();
      int ti = 0;
      for (int si = 0; si < keyPts.length - 1; si++) {
        final from = keyPts[si];
        final to = keyPts[si + 1];
        final steps = si == keyPts.length - 2 ? n - ti : seg;
        for (int s = 0; s < steps && ti < n; s++, ti++) {
          final t = steps > 1 ? s / (steps - 1) : 0.0;
          final noise = (rng.nextDouble() - 0.5) * (c.high - c.low) * 0.04;
          double px = from + (to - from) * t + noise;
          px = px.clamp(c.low, c.high);
          ticks.add(_ReplayTick(
            time: c.time + (s * (tf / n)).floor(),
            price: px,
            candleIdx: ci,
          ));
        }
      }
      if (ticks.isNotEmpty && ticks.last.candleIdx == ci) {
        ticks[ticks.length - 1] = _ReplayTick(
          time: ticks.last.time,
          price: c.close,
          candleIdx: ci,
        );
      }
    }
    return ticks;
  }

  void toggleReplayPlay() {
    if (replayPlaying) {
      _stopReplay();
    } else {
      _startReplay();
    }
  }

  void _startReplay() {
    if (replayTickIdx >= replayTicks.length - 1) {
      replayTickIdx = 0;
    }
    replayPlaying = true;
    notifyListeners();
    _playTick();
  }

  void _stopReplay() {
    replayPlaying = false;
    replayTimer?.cancel();
    notifyListeners();
  }

  void _playTick() {
    if (!replayPlaying) return;
    _advanceTick();
    if (replayPlaying) {
      replayTimer = Timer(Duration(milliseconds: (replaySpeed / 4).round()), _playTick);
    }
  }

  void _advanceTick() {
    if (replayTicks.isEmpty) return;
    if (replayTickIdx < replayTicks.length - 1) {
      replayTickIdx++;
      final tick = replayTicks[replayTickIdx];
      replayIdx = tick.candleIdx + 1;

      // Check JOROpredict signals
      if (joropredictActive) _checkJPSignals();
      // Check trades
      final candlePrice = replayAll[tick.candleIdx].close;
      _runTrailingStop(candlePrice);
      _checkPendingSignals(candlePrice);
    } else {
      _stopReplay();
    }
    notifyListeners();
  }

  void replayStepBack() {
    if (replayTickIdx > 0) replayTickIdx--;
    notifyListeners();
  }

  void replaySeek(double pct) {
    replayTickIdx = (pct * (replayTicks.length - 1)).round().clamp(0, replayTicks.length - 1);
    if (replayTicks.isNotEmpty) {
      replayIdx = replayTicks[replayTickIdx].candleIdx + 1;
    }
    notifyListeners();
  }

  double get replayProgress {
    if (replayTicks.isEmpty) return 0;
    return replayTickIdx / (replayTicks.length - 1);
  }

  DateTime? get replayCurrentTime {
    if (replayTicks.isEmpty || replayTickIdx >= replayTicks.length) return null;
    return DateTime.fromMillisecondsSinceEpoch(replayTicks[replayTickIdx].time * 1000);
  }

  // ── JOROpredict (AMD algorithm)
  void toggleJOROpredict() {
    joropredictActive = !joropredictActive;
    if (joropredictActive) _runJPAlgorithm();
    notifyListeners();
  }

  void _runJPAlgorithm() {
    final c = getCandles();
    final sigs = <_JPSignal>[];
    final n = c.length;
    if (n < 15) return;

    double atrAt(int i) {
      final period = min(10, i);
      double s = 0;
      int ct = 0;
      for (int k = max(1, i - period); k <= i; k++) {
        s += max(c[k].high - c[k].low,
            max((c[k].high - c[k - 1].close).abs(),
                (c[k].low - c[k - 1].close).abs()));
        ct++;
      }
      return ct > 0 ? s / ct : c[i].high - c[i].low;
    }

    for (int i = 15; i < n; i++) {
      final aV = atrAt(i);
      for (int accLen = 4; accLen <= 20 && i - accLen >= 0; accLen++) {
        final slice = c.sublist(i - accLen, i);
        final hi = slice.map((x) => x.high).reduce(max);
        final lo = slice.map((x) => x.low).reduce(min);
        if ((hi - lo) > aV * 1.5) break;
        final mc = c[i];
        if (mc.high > hi + aV * 0.15 && mc.close < hi && mc.close > lo) {
          sigs.add(_JPSignal(type: 'SELL', price: mc.high, idx: i));
          break;
        }
        if (mc.low < lo - aV * 0.15 && mc.close > lo && mc.close < hi) {
          sigs.add(_JPSignal(type: 'BUY', price: mc.low, idx: i));
          break;
        }
      }
    }
    jpSignals = sigs;
  }

  void refreshJPSignals() {
    if (joropredictActive) _runJPAlgorithm();
  }

  void _checkJPSignals() {
    // Called on replay tick advance
    _runJPAlgorithm();
  }

  // ── Trailing stop
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
      if (inZone) {
        t.status = 'open';
        changed = true;
      }
    }
    if (changed) { saveTrades(); notifyListeners(); }
  }

  // ── Check SL/TP on price update
  void checkSLTP(double price) {
    bool changed = false;
    for (final t in trades.where((t) => t.status == 'open')) {
      if (t.sl != null) {
        if (t.direction == 'long' && price <= t.sl!) {
          t.status = 'closed_sl'; t.pnl = t.calcFloatPnl(price); changed = true;
        } else if (t.direction == 'short' && price >= t.sl!) {
          t.status = 'closed_sl'; t.pnl = t.calcFloatPnl(price); changed = true;
        }
      }
      if (t.tp1 != null && t.status == 'open') {
        if (t.direction == 'long' && price >= t.tp1!) {
          t.status = 'closed_tp'; t.pnl = t.calcFloatPnl(price); changed = true;
        } else if (t.direction == 'short' && price <= t.tp1!) {
          t.status = 'closed_tp'; t.pnl = t.calcFloatPnl(price); changed = true;
        }
      }
    }
    if (changed) { saveTrades(); notifyListeners(); }
  }

  // ── Trade management
  void addTrade(Trade t) {
    trades.insert(0, t);
    saveTrades();
    notifyListeners();
  }

  void removeTrade(int id) {
    trades.removeWhere((t) => t.id == id);
    saveTrades();
    notifyListeners();
  }

  void clearAllTrades() {
    trades.clear();
    saveTrades();
    notifyListeners();
  }

  // ── Persistence
  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    groqKey = p.getString('groqKey') ?? '';
    groqModel = p.getString('groqModel') ?? 'llama-3.3-70b-versatile';
    trailingStop = p.getBool('trailingStop') ?? false;
    trailingDist = p.getDouble('trailingDist') ?? 0.5;
    jpAutoTPSL = p.getBool('jpAutoTPSL') ?? false;
    jpTPAtr = p.getDouble('jpTPAtr') ?? 2.0;
    jpSLAtr = p.getDouble('jpSLAtr') ?? 1.0;
    jpAlarm = p.getBool('jpAlarm') ?? false;
    final tradesJson = p.getString('kintana_trades') ?? '[]';
    trades = (jsonDecode(tradesJson) as List)
        .map((j) => Trade.fromJson(j as Map<String, dynamic>))
        .toList();
    connect();
    notifyListeners();
  }

  Future<void> saveTrades() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('kintana_trades', jsonEncode(trades.map((t) => t.toJson()).toList()));
  }

  Future<void> saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('groqKey', groqKey);
    await p.setString('groqModel', groqModel);
    await p.setBool('trailingStop', trailingStop);
    await p.setDouble('trailingDist', trailingDist);
    await p.setBool('jpAutoTPSL', jpAutoTPSL);
    await p.setDouble('jpTPAtr', jpTPAtr);
    await p.setDouble('jpSLAtr', jpSLAtr);
    await p.setBool('jpAlarm', jpAlarm);
  }

  @override
  void dispose() {
    _ws?.sink.close();
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

class _JPSignal {
  final String type;
  final double price;
  final int idx;
  const _JPSignal({required this.type, required this.price, required this.idx});
}
