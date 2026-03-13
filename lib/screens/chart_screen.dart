import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/market_state.dart';
import '../models/models.dart';
import '../theme/kintana_theme.dart';
import '../widgets/candle_chart_painter.dart';

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});
  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> with TickerProviderStateMixin {
  double? _mouseX, _mouseY;
  double? _dragStartX;
  double? _dragStartOffset;
  double? _pinchStartDist;
  double? _pinchStartZoom;
  double? _pinchMidFrac;
  final List<JPHitArea> _hitAreas = [];
  int? _activeJPIdx;
  bool _showReplayBar = false;
  final _replayDateCtrl = TextEditingController(text: '2025-01-01');
  bool _replayLoading = false;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _replayDateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<MarketState>();
    final candles = s.getCandles();

    return Column(
      children: [
        _buildChartControls(s),
        if (_showReplayBar || s.isReplay) _buildReplayBar(s),
        _buildStatsBar(s),
        Expanded(child: _buildChart(s, candles)),
      ],
    );
  }

  // ── Chart controls (TF buttons)
  Widget _buildChartControls(MarketState s) {
    const tfs = [
      {'label': '1m', 'value': 60},
      {'label': '5m', 'value': 300},
      {'label': '15m', 'value': 900},
      {'label': '30m', 'value': 1800},
      {'label': '1H', 'value': 3600},
      {'label': '4H', 'value': 14400},
      {'label': 'D', 'value': 86400},
    ];
    const chartTypes = ['Candles', 'Line'];

    return Container(
      height: 42,
      color: KintanaTheme.bg2,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // TF group
          Container(
            decoration: BoxDecoration(
              color: KintanaTheme.card,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: KintanaTheme.b1),
            ),
            padding: const EdgeInsets.all(2),
            child: Row(
              children: tfs.map((tf) {
                final active = s.tf == tf['value'];
                return GestureDetector(
                  onTap: () => s.changeTimeframe(tf['value'] as int),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: active ? KintanaTheme.acc : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: active ? [BoxShadow(color: KintanaTheme.acc.withOpacity(0.4), blurRadius: 8)] : null,
                    ),
                    child: Text(
                      tf['label'] as String,
                      style: KintanaTheme.mono(
                        size: 9,
                        color: active ? KintanaTheme.bg : KintanaTheme.t3,
                        weight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 5),
          // Divider
          Container(width: 1, height: 18, color: KintanaTheme.b2),
          const SizedBox(width: 5),
          // JOROpredict toggle
          GestureDetector(
            onTap: () {
              s.toggleJOROpredict();
              HapticFeedback.lightImpact();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: s.joropredictActive
                    ? KintanaTheme.purple.withOpacity(0.2)
                    : KintanaTheme.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: s.joropredictActive
                      ? KintanaTheme.purple.withOpacity(0.7)
                      : KintanaTheme.b2,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_graph_rounded,
                      size: 10,
                      color: s.joropredictActive ? KintanaTheme.purpleL : KintanaTheme.t3),
                  const SizedBox(width: 4),
                  Text(
                    'JOROpredict',
                    style: KintanaTheme.mono(
                      size: 9,
                      color: s.joropredictActive ? KintanaTheme.purpleL : KintanaTheme.t3,
                      weight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Replay mode toggle
          GestureDetector(
            onTap: () {
              setState(() => _showReplayBar = !_showReplayBar);
              if (!s.isReplay && _showReplayBar) {
                // Don't switch yet — wait for user to tap mode badge
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: s.isReplay ? KintanaTheme.purple.withOpacity(0.15) : KintanaTheme.card2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: s.isReplay ? KintanaTheme.purple.withOpacity(0.5) : KintanaTheme.b2,
                ),
              ),
              child: Text(
                s.isReplay ? '🎬 REPLAY' : '● LIVE',
                style: KintanaTheme.mono(
                  size: 9,
                  color: s.isReplay ? KintanaTheme.purpleL : KintanaTheme.green,
                  weight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats bar
  Widget _buildStatsBar(MarketState s) {
    final candles = s.getCandles();
    final sessionHigh = candles.isEmpty ? null : candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final sessionLow = candles.isEmpty ? null : candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final spread = (s.askPrice != null && s.bidPrice != null)
        ? (s.askPrice! - s.bidPrice!).toStringAsFixed(5)
        : '—';

    return Container(
      height: 34,
      color: KintanaTheme.bg2.withOpacity(0.9),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _statItem('BID', fp(s.bidPrice)),
            _statItem('ASK', fp(s.askPrice)),
            _statItem('SPREAD', spread),
            _statItem('HIGH', fp(sessionHigh), KintanaTheme.green),
            _statItem('LOW', fp(sessionLow), KintanaTheme.red),
            _statItem('BARS', candles.length.toString()),
            _statItem('ATR', fp(s.calcATR())),
            if (!s.isReplay) _candleTimerItem(s),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, [Color? valueColor]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: KintanaTheme.b1, width: 1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: KintanaTheme.mono(size: 7, color: KintanaTheme.t3)),
          Text(value, style: KintanaTheme.mono(size: 10, color: valueColor ?? KintanaTheme.t1, weight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _candleTimerItem(MarketState s) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, _) {
        final tf = s.tf;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final remaining = tf - (now % tf);
        final pct = remaining / tf;
        final mm = (remaining ~/ 60).toString().padLeft(2, '0');
        final ss = (remaining % 60).toString().padLeft(2, '0');
        final color = pct < 0.1 ? KintanaTheme.red : pct < 0.2 ? KintanaTheme.yellow : KintanaTheme.green;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('NEXT', style: KintanaTheme.mono(size: 7, color: KintanaTheme.t3)),
              Text('$mm:$ss', style: KintanaTheme.mono(size: 10, color: color, weight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }

  // ── Replay bar
  Widget _buildReplayBar(MarketState s) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: const Color(0xF7150E28),
        border: Border(
          bottom: BorderSide(color: KintanaTheme.purple.withOpacity(0.4), width: 2),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text('🎬 REPLAY', style: KintanaTheme.mono(size: 8, color: KintanaTheme.purple, letterSpacing: 1.5)),
            const SizedBox(width: 8),
            // Date input
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime(2025, 1, 1),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().subtract(const Duration(days: 1)),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.dark(primary: KintanaTheme.purple),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) {
                  _replayDateCtrl.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: KintanaTheme.card,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: KintanaTheme.purple.withOpacity(0.4)),
                ),
                child: ValueListenableBuilder(
                  valueListenable: _replayDateCtrl,
                  builder: (_, v, __) => Text(
                    _replayDateCtrl.text,
                    style: KintanaTheme.mono(size: 10, color: KintanaTheme.t1),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 5),
            // Load button
            GestureDetector(
              onTap: _replayLoading ? null : () async {
                setState(() => _replayLoading = true);
                if (!s.isReplay) s.switchToReplay();
                try {
                  await s.loadReplayData(_replayDateCtrl.text);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: KintanaTheme.red),
                    );
                  }
                }
                if (mounted) setState(() => _replayLoading = false);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: KintanaTheme.purple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: KintanaTheme.purple.withOpacity(0.5)),
                ),
                child: _replayLoading
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: KintanaTheme.purpleL, strokeWidth: 1.5))
                    : Text('LOAD', style: KintanaTheme.mono(size: 9, color: KintanaTheme.purpleL, weight: FontWeight.bold)),
              ),
            ),
            Container(width: 1, height: 18, color: KintanaTheme.purple.withOpacity(0.3), margin: const EdgeInsets.symmetric(horizontal: 6)),
            // Playback controls
            _rbBtn(s.isReplay && s.replayTicks.isNotEmpty ? '⏮' : '⏮', () => s.replaySeek(0)),
            const SizedBox(width: 4),
            _rbBtn(s.replayPlaying ? '⏸' : '▶', () {
              s.toggleReplayPlay();
              HapticFeedback.lightImpact();
            }, active: s.replayPlaying),
            const SizedBox(width: 4),
            _rbBtn('⏭', () => s.replaySeek(1.0)),
            const SizedBox(width: 8),
            // Progress bar
            GestureDetector(
              onTapDown: (d) {
                final box = context.findRenderObject() as RenderBox?;
                // Simple seek on tap
              },
              child: Container(
                width: 100,
                height: 4,
                decoration: BoxDecoration(
                  color: KintanaTheme.purple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: s.replayProgress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [KintanaTheme.purple, KintanaTheme.acc]),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Time info
            Text(
              s.replayCurrentTime != null
                  ? '${s.replayCurrentTime!.hour.toString().padLeft(2, '0')}:${s.replayCurrentTime!.minute.toString().padLeft(2, '0')} — ${s.replayIdx}/${s.replayAll.length}'
                  : '—',
              style: KintanaTheme.mono(size: 8, color: KintanaTheme.purple),
            ),
            const SizedBox(width: 8),
            // Back to live
            if (s.isReplay)
              GestureDetector(
                onTap: () {
                  s.switchToLive();
                  setState(() => _showReplayBar = false);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: KintanaTheme.acc.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: KintanaTheme.acc.withOpacity(0.4)),
                  ),
                  child: Text('⚡ LIVE', style: KintanaTheme.mono(size: 8, color: KintanaTheme.acc, weight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rbBtn(String icon, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active ? KintanaTheme.purple : KintanaTheme.purple.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: KintanaTheme.purple.withOpacity(0.35)),
        ),
        child: Center(
          child: Text(icon, style: TextStyle(
            fontSize: 12,
            color: active ? Colors.white : KintanaTheme.purpleL,
          )),
        ),
      ),
    );
  }

  // ── Main chart widget
  Widget _buildChart(MarketState s, List<Candle> candles) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onScaleStart: (d) {
              if (d.pointerCount == 1) {
                _dragStartX = d.focalPoint.dx;
                _dragStartOffset = s.offset;
              } else {
                _pinchStartDist = null;
                _pinchStartZoom = s.zoom;
              }
            },
            onScaleUpdate: (d) {
              final chartW = context.size?.width ?? 400;

              if (d.pointerCount == 1) {
                // Pan
                final cW = (chartW - CandleChartPainter.padLeft - CandleChartPainter.padRight) / s.zoom;
                if (cW > 0 && _dragStartX != null && _dragStartOffset != null) {
                  final delta = (d.focalPoint.dx - _dragStartX!) / cW;
                  s.offset = (_dragStartOffset! - delta).clamp(0, (candles.length - s.zoom).clamp(0, double.infinity));
                  s.notifyListeners();
                }
              } else {
                // Pinch zoom
                _pinchStartDist ??= d.scale;
                final factor = d.scale / (_pinchStartDist ?? 1);
                final frac = (d.focalPoint.dx - CandleChartPainter.padLeft) /
                    (chartW - CandleChartPainter.padLeft - CandleChartPainter.padRight);
                s.zoomAround(factor, frac.clamp(0.0, 1.0));
                _pinchStartDist = d.scale;
              }
            },
            onScaleEnd: (_) {
              _dragStartX = null;
              _dragStartOffset = null;
              _pinchStartDist = null;
            },
            onTapUp: (d) => _onChartTap(d.localPosition, s, candles),
            child: MouseRegion(
              cursor: SystemMouseCursors.precise,
              onHover: (e) {
                setState(() { _mouseX = e.localPosition.dx; _mouseY = e.localPosition.dy; });
              },
              onExit: (_) => setState(() { _mouseX = null; _mouseY = null; }),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: CandleChartPainter(
                    state: s,
                    candles: candles,
                    zoom: s.zoom,
                    offset: s.offset,
                    yOffset: s.yOffset,
                    mouseX: _mouseX,
                    mouseY: _mouseY,
                    joropredictActive: s.joropredictActive,
                    hitAreas: _hitAreas,
                  ),
                  child: Container(),
                ),
              ),
            ),
          ),
        ),

        // ── OHLC overlay
        Positioned(
          top: 8,
          left: 8,
          child: _buildOHLCOverlay(s, candles),
        ),

        // ── JOROpredict badge
        if (s.joropredictActive)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  decoration: BoxDecoration(
                    color: KintanaTheme.purple.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: KintanaTheme.purple.withOpacity(0.4 + 0.4 * _pulseCtrl.value),
                    ),
                    boxShadow: [BoxShadow(
                      color: KintanaTheme.purple.withOpacity(0.1 + 0.2 * _pulseCtrl.value),
                      blurRadius: 10,
                    )],
                  ),
                  child: Text(
                    '⚡ JOROpredict — ${s.jpSignals.where((sg) => sg.confirmed).length} valid / ${s.jpSignals.length} signals',
                    style: KintanaTheme.mono(size: 9, color: KintanaTheme.purpleL, letterSpacing: 1),
                  ),
                ),
              ),
            ),
          ),

        // ── Zoom buttons
        Positioned(
          top: 8,
          right: CandleChartPainter.padRight + 8,
          child: Column(
            children: [
              _zoomBtn('+', () => s.zoomIn(0.5)),
              const SizedBox(height: 4),
              _zoomBtn('−', () => s.zoomOut(0.5)),
              const SizedBox(height: 4),
              _zoomBtn('⊙', s.zoomReset),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOHLCOverlay(MarketState s, List<Candle> candles) {
    if (candles.isEmpty) return const SizedBox();
    final last = candles.last;
    return Row(
      children: [
        _ohlcItem('O', fp(last.open)),
        const SizedBox(width: 7),
        _ohlcItem('H', fp(last.high), KintanaTheme.green),
        const SizedBox(width: 7),
        _ohlcItem('L', fp(last.low), KintanaTheme.red),
        const SizedBox(width: 7),
        _ohlcItem('C', fp(last.close)),
      ],
    );
  }

  Widget _ohlcItem(String label, String value, [Color col = KintanaTheme.t2]) {
    return Row(
      children: [
        Text('$label:', style: KintanaTheme.mono(size: 9, color: KintanaTheme.t2)),
        const SizedBox(width: 2),
        Text(value, style: KintanaTheme.mono(size: 9, color: col, weight: FontWeight.bold)),
      ],
    );
  }

  Widget _zoomBtn(String icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: () { onTap(); HapticFeedback.selectionClick(); },
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: KintanaTheme.card.withOpacity(0.9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: KintanaTheme.b2),
        ),
        child: Center(
          child: Text(icon, style: const TextStyle(color: KintanaTheme.t2, fontSize: 13)),
        ),
      ),
    );
  }

  void _onChartTap(Offset pos, MarketState s, List<Candle> candles) {
    // Check JOROpredict hit areas
    for (final h in _hitAreas) {
      if ((Offset(h.cx, h.cy) - pos).distance < h.radius) {
        setState(() => _activeJPIdx = _activeJPIdx == h.sigIdx ? null : h.sigIdx);
        HapticFeedback.mediumImpact();
        return;
      }
    }
    setState(() => _activeJPIdx = null);
  }
}
