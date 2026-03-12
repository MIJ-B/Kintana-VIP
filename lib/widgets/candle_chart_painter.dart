import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/market_state.dart';
import '../theme/kintana_theme.dart';

// ── Hit area for JOROpredict signals
class JPHitArea {
  final double cx, cy;
  final double radius;
  final int sigIdx;
  const JPHitArea({required this.cx, required this.cy, required this.radius, required this.sigIdx});
}

class CandleChartPainter extends CustomPainter {
  final MarketState state;
  final List<Candle> candles;
  final double zoom;
  final double offset;
  final double yOffset;
  final double? mouseX;
  final double? mouseY;
  final bool joropredictActive;
  final List<JPHitArea> hitAreas;
  final int? activeJPIdx;

  // Layout padding
  static const double padTop = 10;
  static const double padRight = 66;
  static const double padBottom = 30;
  static const double padLeft = 4;

  CandleChartPainter({
    required this.state,
    required this.candles,
    required this.zoom,
    required this.offset,
    required this.yOffset,
    this.mouseX,
    this.mouseY,
    required this.joropredictActive,
    required this.hitAreas,
    this.activeJPIdx,
  });

  // Price formatting
  static String fmt(double? p) => fp(p);

  double p2y(double price, double mn, double mx, double H) {
    final r = mx - mn == 0 ? 1.0 : mx - mn;
    return padTop + (1 - (price - mn) / r) * (H - padTop - padBottom);
  }

  double y2p(double y, double mn, double mx, double H) {
    final r = mx - mn == 0 ? 1.0 : mx - mn;
    return mx - ((y - padTop) / (H - padTop - padBottom)) * r;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;

    // ── Background gradient
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [KintanaTheme.bg, Color(0xFF050812)],
      ).createShader(Rect.fromLTWH(0, 0, W, H));
    canvas.drawRect(Rect.fromLTWH(0, 0, W, H), bgPaint);

    if (candles.isEmpty) {
      _drawEmptyText(canvas, size);
      return;
    }

    // ── Visible range
    final s = offset.round().clamp(0, candles.length - 1);
    final e = min(candles.length - 1, s + zoom.round() - 1);
    final visCandles = candles.sublist(s, e + 1);
    final totalSlots = zoom.round();

    // ── Price range
    double mn = visCandles.map((c) => c.low).reduce(min);
    double mx = visCandles.map((c) => c.high).reduce(max);
    final pad = (mx - mn) * 0.07;
    mn -= pad;
    mx += pad;

    // Apply Y offset (vertical pan)
    if (yOffset != 0) {
      final range = mx - mn;
      mn += range * yOffset;
      mx += range * yOffset;
    }

    final cW = (W - padLeft - padRight) / totalSlots;
    final bW = cW * 0.7;

    // ── Grid lines
    _drawGrid(canvas, W, H, mn, mx);

    // ── Volume bars
    _drawVolume(canvas, W, H, s, visCandles, cW);

    // ── Candles
    _drawCandles(canvas, H, s, e, visCandles, cW, bW, mn, mx);

    // ── Trade lines
    _drawTradeLines(canvas, W, H, mn, mx);

    // ── JOROpredict signals
    if (joropredictActive) {
      _drawJPSignals(canvas, W, H, s, e, cW, mn, mx, totalSlots);
    }

    // ── Live price line
    if (!state.isReplay && state.price != null) {
      _drawLivePriceLine(canvas, W, H, mn, mx, cW, s, visCandles.length);
    }

    // ── Replay cursor
    if (state.isReplay && state.replayTicks.isNotEmpty) {
      _drawReplayCursor(canvas, W, H, s, cW, totalSlots);
    }

    // ── Y-axis labels
    _drawYAxis(canvas, W, H, mn, mx);

    // ── X-axis labels
    _drawXAxis(canvas, W, H, s, e, visCandles, cW);

    // ── Crosshair
    if (mouseX != null && mouseY != null) {
      _drawCrosshair(canvas, W, H, mn, mx);
    }
  }

  void _drawEmptyText(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: state.isReplay ? 'Select a date and tap LOAD' : 'Connecting to market data...',
        style: const TextStyle(
          fontFamily: 'SpaceMono',
          fontSize: 11,
          color: Color(0x803D4A6B),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height / 2 - tp.height / 2));
  }

  void _drawGrid(Canvas canvas, double W, double H, double mn, double mx) {
    final paint = Paint()..style = PaintingStyle.stroke;
    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i <= 8; i++) {
      final price = mn + (mx - mn) * (i / 8);
      final y = p2y(price, mn, mx, H);
      paint.color = i % 2 == 0
          ? const Color(0xE5161D32)
          : const Color(0xB2121A2A);
      paint.strokeWidth = 0.5;
      // Dashed
      _dashLine(canvas, paint, Offset(padLeft, y), Offset(W - padRight, y));
    }
  }

  void _dashLine(Canvas canvas, Paint paint, Offset a, Offset b,
      {double dashLen = 2, double gapLen = 5}) {
    final dir = (b - a);
    final len = dir.distance;
    final unit = dir / len;
    double d = 0;
    while (d < len) {
      final start = a + unit * d;
      final end = a + unit * min(d + dashLen, len);
      canvas.drawLine(start, end, paint);
      d += dashLen + gapLen;
    }
  }

  void _drawVolume(Canvas canvas, double W, double H, int s,
      List<Candle> vis, double cW) {
    if (vis.isEmpty) return;
    // Pseudo-volume (range as proxy)
    final maxRange = vis.map((c) => c.range).reduce(max);
    if (maxRange == 0) return;
    final maxVH = H * 0.12;
    final paint = Paint();

    for (int i = 0; i < vis.length; i++) {
      final c = vis[i];
      final vh = (c.range / maxRange) * maxVH;
      final x = padLeft + (i + 0.5) * cW;
      paint.color = (c.isBull ? KintanaTheme.green : KintanaTheme.red)
          .withOpacity(0.12);
      canvas.drawRect(
        Rect.fromLTWH(x - cW * 0.35, H - padBottom - vh, cW * 0.7, vh),
        paint,
      );
    }
  }

  void _drawCandles(Canvas canvas, double H, int s, int e, List<Candle> vis,
      double cW, double bW, double mn, double mx) {
    final bullBody = Paint()..color = KintanaTheme.green;
    final bearBody = Paint()..color = KintanaTheme.red;
    final bullWick = Paint()
      ..color = KintanaTheme.green.withOpacity(0.7)
      ..strokeWidth = 1.2;
    final bearWick = Paint()
      ..color = KintanaTheme.red.withOpacity(0.7)
      ..strokeWidth = 1.2;

    for (int i = 0; i < vis.length; i++) {
      final c = vis[i];
      final x = padLeft + (i + 0.5) * cW;
      final openY = p2y(c.open, mn, mx, H);
      final closeY = p2y(c.close, mn, mx, H);
      final highY = p2y(c.high, mn, mx, H);
      final lowY = p2y(c.low, mn, mx, H);
      final bodyTop = min(openY, closeY);
      final bodyH = max((closeY - openY).abs(), 1.0);
      final isBull = c.isBull;

      // Wick
      canvas.drawLine(Offset(x, highY), Offset(x, bodyTop),
          isBull ? bullWick : bearWick);
      canvas.drawLine(Offset(x, bodyTop + bodyH), Offset(x, lowY),
          isBull ? bullWick : bearWick);

      // Body
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - bW / 2, bodyTop, bW, bodyH),
        const Radius.circular(1.5),
      );

      if (isBull) {
        // Gradient fill
        final grad = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              KintanaTheme.green,
              KintanaTheme.green.withOpacity(0.7),
            ],
          ).createShader(Rect.fromLTWH(x - bW / 2, bodyTop, bW, bodyH));
        canvas.drawRRect(rect, grad);
      } else {
        final grad = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              KintanaTheme.red.withOpacity(0.85),
              KintanaTheme.red,
            ],
          ).createShader(Rect.fromLTWH(x - bW / 2, bodyTop, bW, bodyH));
        canvas.drawRRect(rect, grad);
      }

      // Doji highlight
      if (bodyH <= 1.5) {
        canvas.drawLine(
          Offset(x - bW / 2, openY),
          Offset(x + bW / 2, openY),
          Paint()
            ..color = KintanaTheme.yellow.withOpacity(0.7)
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  void _drawTradeLines(Canvas canvas, double W, double H, double mn, double mx) {
    for (final t in state.trades) {
      if (t.status != 'open' && t.status != 'pending') continue;
      final isBull = t.direction == 'long';
      final lc = isBull ? KintanaTheme.green : KintanaTheme.red;

      void drawLine(double price, Color color, bool dashed, String label) {
        final y = p2y(price, mn, mx, H);
        if (y < padTop || y > H - padBottom) return;
        final paint = Paint()
          ..color = color
          ..strokeWidth = 1.5;
        if (dashed) {
          _dashLine(canvas, paint, Offset(padLeft, y), Offset(W - padRight, y),
              dashLen: 6, gapLen: 3);
        } else {
          canvas.drawLine(Offset(padLeft, y), Offset(W - padRight, y), paint);
        }
        // Label
        _drawPill(canvas, label, Offset(padLeft + 6, y - 7), color);
      }

      drawLine(t.entry, lc.withOpacity(0.8), t.status == 'pending',
          '${isBull ? '▲' : '▼'} ${t.status == 'pending' ? 'PENDING' : isBull ? 'BUY' : 'SELL'} @ ${fmt(t.entry)}');
      if (t.sl != null) drawLine(t.sl!, KintanaTheme.red.withOpacity(0.7), true, '🛑 SL ${fmt(t.sl)}');
      if (t.tp1 != null) drawLine(t.tp1!, KintanaTheme.green.withOpacity(0.7), true, '🎯 TP ${fmt(t.tp1)}');
    }
  }

  void _drawPill(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'SpaceMono',
          fontSize: 7.5,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = 5.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pos.dx - pad, pos.dy - 1, tp.width + pad * 2, tp.height + 2),
      const Radius.circular(3),
    );
    canvas.drawRRect(rect, Paint()..color = color.withOpacity(0.18));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = color.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    tp.paint(canvas, pos);
  }

  void _drawJPSignals(Canvas canvas, double W, double H, int s, int e, double cW,
      double mn, double mx, int totalSlots) {
    hitAreas.clear();
    for (final sig in state.jpSignals) {
      if (sig.idx < s || sig.idx > e) continue;
      final localIdx = sig.idx - s;
      final x = padLeft + (localIdx + 0.5) * cW;
      final isBuy = sig.type == 'BUY';
      final col = isBuy ? KintanaTheme.green : KintanaTheme.red;
      final sigY = isBuy
          ? p2y(sig.price, mn, mx, H) + 22
          : p2y(sig.price, mn, mx, H) - 22;

      // Glow circle
      canvas.drawCircle(
        Offset(x, p2y(sig.price, mn, mx, H)),
        7,
        Paint()
          ..color = col.withOpacity(0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(
        Offset(x, p2y(sig.price, mn, mx, H)),
        4,
        Paint()..color = col,
      );

      // Arrow
      final arrowPath = Path();
      if (isBuy) {
        arrowPath.moveTo(x, sigY - 13);
        arrowPath.lineTo(x - 9, sigY + 2);
        arrowPath.lineTo(x + 9, sigY + 2);
      } else {
        arrowPath.moveTo(x, sigY + 13);
        arrowPath.lineTo(x - 9, sigY - 2);
        arrowPath.lineTo(x + 9, sigY - 2);
      }
      arrowPath.close();
      canvas.drawPath(
        arrowPath,
        Paint()
          ..color = col
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawPath(arrowPath, Paint()..color = col);

      // Badge label
      final lbl = isBuy ? '▲ BUY' : '▼ SELL';
      final badgeY = isBuy ? sigY + 4 : sigY - 17;
      _drawPill(canvas, '$lbl  JP', Offset(x - 22, badgeY), col);

      // Sub-label
      _drawSmallText(canvas, 'JP', Offset(x - 6, isBuy ? badgeY + 14 : badgeY - 5),
          col.withOpacity(0.7));

      // Register hit area
      hitAreas.add(JPHitArea(cx: x, cy: sigY, radius: 24, sigIdx: sig.idx));

      // Active signal highlight ring
      if (activeJPIdx != null && activeJPIdx == sig.idx) {
        canvas.drawCircle(
          Offset(x, sigY),
          18,
          Paint()
            ..color = col.withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // ── Draw TP/SL for active signal
    if (state.activeJPSig != null) {
      _drawActiveSignalLines(canvas, W, H, s, cW, mn, mx);
    }
  }

  void _drawActiveSignalLines(Canvas canvas, double W, double H, int s,
      double cW, double mn, double mx) {
    final sig = state.activeJPSig!;
    final isBuy = sig.isBuy;
    final atr = state.calcATR();
    final entry = sig.entry;
    final tp = isBuy ? entry + atr * state.jpTPAtr : entry - atr * state.jpTPAtr;
    final sl = isBuy ? entry - atr * state.jpSLAtr : entry + atr * state.jpSLAtr;

    final entY = p2y(entry, mn, mx, H);
    final tpY = p2y(tp, mn, mx, H);
    final slY = p2y(sl, mn, mx, H);

    void drawDash(double y, Color col, String label) {
      if (y < padTop || y > H - padBottom) return;
      final p = Paint()
        ..color = col
        ..strokeWidth = 1.2;
      _dashLine(canvas, p, Offset(padLeft, y), Offset(W - padRight, y), dashLen: 6, gapLen: 4);
      // Label on right axis
      final tp2 = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: 'SpaceMono',
            fontSize: 7,
            fontWeight: FontWeight.bold,
            color: col,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.drawRect(
        Rect.fromLTWH(W - padRight + 1, y - 7, padRight - 2, 14),
        Paint()..color = const Color(0xF00D1020),
      );
      tp2.paint(canvas, Offset(W - padRight + 4, y - 5));
    }

    drawDash(entY, Colors.white.withOpacity(0.35), 'ENTRY');
    drawDash(tpY, KintanaTheme.yellow, 'TP ${fmt(tp)}');
    drawDash(slY, KintanaTheme.red, 'SL ${fmt(sl)}');
  }

  void _drawLivePriceLine(Canvas canvas, double W, double H, double mn, double mx,
      double cW, int s, int visLen) {
    final price = state.price!;
    final y = p2y(price, mn, mx, H);
    if (y < padTop || y > H - padBottom) return;

    final up = state.prevPrice == null || price >= state.prevPrice!;
    final col = up ? KintanaTheme.green : KintanaTheme.red;

    // Glow
    final glowPaint = Paint()
      ..color = col.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawLine(
      Offset(padLeft, y),
      Offset(W - padRight, y),
      glowPaint..strokeWidth = 2,
    );

    // Main dashed line
    _dashLine(
      canvas,
      Paint()
        ..color = col.withOpacity(0.7)
        ..strokeWidth = 1.2,
      Offset(padLeft, y),
      Offset(W - padRight, y),
      dashLen: 5,
      gapLen: 3,
    );

    // Price badge
    final badgeW = padRight - 2;
    final bx = W - padRight + 1;
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(bx, y - 8, badgeW, 16),
      const Radius.circular(3),
    );
    canvas.drawRRect(rr, Paint()..color = col);
    final tp = TextPainter(
      text: TextSpan(
        text: fmt(price),
        style: const TextStyle(
          fontFamily: 'SpaceMono',
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: Color(0xFF050810),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(bx + (badgeW - tp.width) / 2, y - 5.5));

    // Pulse dot on last candle
    final lastLocal = state.candles.length - 1 - s;
    if (lastLocal >= 0 && lastLocal < visLen) {
      final lx = padLeft + (lastLocal + 0.5) * cW;
      canvas.drawCircle(Offset(lx, y), 6, Paint()..color = col.withOpacity(0.22));
      canvas.drawCircle(Offset(lx, y), 2.5, Paint()..color = col);
    }
  }

  void _drawReplayCursor(Canvas canvas, double W, double H, int s, double cW, int totalSlots) {
    final rIdx = state.replayIdx - 1;
    if (rIdx < s) return;
    final local = rIdx - s;
    if (local >= totalSlots) return;
    final x = padLeft + (local + 0.5) * cW;
    canvas.drawLine(
      Offset(x, padTop),
      Offset(x, H - padBottom),
      Paint()
        ..color = KintanaTheme.purple.withOpacity(0.6)
        ..strokeWidth = 1,
    );
  }

  void _drawYAxis(Canvas canvas, double W, double H, double mn, double mx) {
    for (int i = 0; i <= 8; i++) {
      final price = mn + (mx - mn) * (i / 8);
      final y = p2y(price, mn, mx, H);
      if (y < padTop || y > H - padBottom) continue;
      _drawSmallText(
        canvas,
        fmt(price),
        Offset(W - padRight + 3, y - 4),
        KintanaTheme.t3.withOpacity(0.9),
      );
    }
  }

  void _drawXAxis(Canvas canvas, double W, double H, int s, int e,
      List<Candle> vis, double cW) {
    if (vis.isEmpty) return;
    final step = max(1, (vis.length / 6).ceil());
    for (int i = 0; i < vis.length; i += step) {
      final c = vis[i];
      final x = padLeft + (i + 0.5) * cW;
      final dt = DateTime.fromMillisecondsSinceEpoch(c.time * 1000);
      final label = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      _drawSmallText(canvas, label, Offset(x - 12, H - padBottom + 4), KintanaTheme.t3);
    }
  }

  void _drawCrosshair(Canvas canvas, double W, double H, double mn, double mx) {
    final x = mouseX!;
    final y = mouseY!;
    final paint = Paint()
      ..color = KintanaTheme.t2.withOpacity(0.25)
      ..strokeWidth = 0.5;
    _dashLine(canvas, paint, Offset(x, padTop), Offset(x, H - padBottom), dashLen: 3, gapLen: 4);
    _dashLine(canvas, paint, Offset(padLeft, y), Offset(W - padRight, y), dashLen: 3, gapLen: 4);

    // Price label on Y axis
    final hp = y2p(y, mn, mx, H);
    final bxR = W - padRight;
    canvas.drawRect(
      Rect.fromLTWH(bxR, y - 7.5, padRight - 1, 15),
      Paint()..color = const Color(0xF0101424),
    );
    canvas.drawRect(
      Rect.fromLTWH(bxR, y - 7.5, padRight - 1, 15),
      Paint()
        ..color = KintanaTheme.b2.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    _drawSmallText(canvas, fmt(hp), Offset(bxR + 3, y - 4.5), KintanaTheme.t1.withOpacity(0.8));
  }

  void _drawSmallText(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'SpaceMono',
          fontSize: 7.5,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(CandleChartPainter old) => true;
}
