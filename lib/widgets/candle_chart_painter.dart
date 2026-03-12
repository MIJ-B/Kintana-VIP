import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/market_state.dart';
import '../theme/kintana_theme.dart';

// Hit area pour les signals JP
class JPHitArea {
  final double cx, cy, radius;
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

  static const double padTop    = 10;
  static const double padRight  = 66;
  static const double padBottom = 30;
  static const double padLeft   = 4;

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
  });

  // ── p2y / y2p — exact copy from HTML
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
    canvas.drawRect(
      Rect.fromLTWH(0, 0, W, H),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF03050E), Color(0xFF050812)],
      ).createShader(Rect.fromLTWH(0, 0, W, H)),
    );

    if (candles.isEmpty) { _drawEmptyText(canvas, size); return; }

    // ── Visible range
    final s    = offset.round().clamp(0, candles.length - 1);
    final e    = min(candles.length - 1, s + zoom.round() - 1);
    final vis  = candles.sublist(s, e + 1);
    final totalSlots = zoom.round();

    // ── Price range
    double mn = vis.map((c) => c.low).reduce(min);
    double mx = vis.map((c) => c.high).reduce(max);
    final pad = (mx - mn) * 0.07;
    mn -= pad; mx += pad;
    if (yOffset != 0) {
      final range = mx - mn;
      mn += range * yOffset;
      mx += range * yOffset;
    }

    final cW = (W - padLeft - padRight) / totalSlots;
    final bW = max(1.0, min(cW * 0.7, 32.0));

    _drawGrid(canvas, W, H, mn, mx);
    _drawVolume(canvas, W, H, vis, cW);
    _drawCandles(canvas, H, vis, cW, bW, mn, mx);
    _drawTradeLines(canvas, W, H, mn, mx);

    // ── JOROpredict — exact copy from HTML drawGainzSignals()
    if (joropredictActive) {
      _drawGainzSignals(canvas, W, H, s, e, vis, cW, mn, mx);
    }

    // ── Live price line
    if (!state.isReplay && state.price != null) {
      _drawLivePriceLine(canvas, W, H, mn, mx, cW, s, vis.length);
    }

    // ── Replay cursor
    if (state.isReplay && state.replayTicks.isNotEmpty) {
      _drawReplayCursor(canvas, W, H, s, cW, totalSlots);
    }

    _drawYAxis(canvas, W, H, mn, mx);
    _drawXAxis(canvas, W, H, vis, cW);

    if (mouseX != null && mouseY != null) {
      _drawCrosshair(canvas, W, H, mn, mx);
    }
  }

  // ─────────────────────────────────────────────────────────
  // ── drawGainzSignals — EXACT COPY from HTML drawGainzSignals()
  // ─────────────────────────────────────────────────────────
  void _drawGainzSignals(Canvas canvas, double W, double H, int s, int e,
      List<Candle> vis, double cW, double mn, double mx) {
    hitAreas.clear();

    final cL = padLeft;
    final cR = W - padRight;

    for (final ph in state.jpPhases) {
      final acc      = ph.acc;
      final manipIdx = ph.manipIdx;
      final manipDir = ph.manipDir;
      final distDir  = ph.distDir;
      final isBull   = distDir == 'up'; // vraie direction après manipulation

      // ── Phase 1: ACCUMULATION zone (violet) — exact copy
      final xS  = cL + (acc.startIdx - s + 0.5) * cW;
      final xE  = cL + (acc.endIdx   - s + 0.5) * cW;
      final zy1 = p2y(acc.high, mn, mx, H);
      final zy2 = p2y(acc.low,  mn, mx, H);

      if (xE > cL && xS < cR && zy2 > padTop && zy1 < H - padBottom) {
        final dx2 = max(cL, xS);
        final dw  = min(cR, xE) - dx2;
        if (dw > 0) {
          // Fill
          canvas.drawRect(
            Rect.fromLTWH(dx2, zy1, dw, zy2 - zy1),
            Paint()..color = const Color(0x1A9B72E6),
          );
          // Dashed border
          _dashRect(canvas, Rect.fromLTWH(dx2, zy1, dw, zy2 - zy1),
              const Color(0x739B72E6), 0.7, dash: 3, gap: 3);
        }
        // 'ACC' label
        _drawSmallText(canvas, 'ACC',
            Offset(max(cL + 2, xS + 2), zy1 - 8),
            const Color(0xD99B72E6), bold: true, size: 6.5);
      }

      // ── Phase 2 + Signal: MANIPULATION candle — exact copy
      final mLocal = manipIdx - s;
      if (mLocal >= 0 && mLocal < vis.length) {
        final mc   = vis[mLocal];
        final mx2c = cL + (mLocal + 0.5) * cW;
        final mHy  = p2y(mc.high, mn, mx, H);
        final mLy  = p2y(mc.low,  mn, mx, H);
        final col  = isBull ? KintanaTheme.green : KintanaTheme.red;

        // Highlight du wick de manipulation (ligne épaisse colorée + glow)
        final wickPaint = Paint()
          ..color = col
          ..strokeWidth = 3
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        if (manipDir == 'up') {
          final bodyTop = p2y(max(mc.open, mc.close), mn, mx, H);
          canvas.drawLine(Offset(mx2c, bodyTop), Offset(mx2c, mHy), wickPaint);
        } else {
          final bodyBot = p2y(min(mc.open, mc.close), mn, mx, H);
          canvas.drawLine(Offset(mx2c, bodyBot), Offset(mx2c, mLy), wickPaint);
        }

        // Cercle entry point sur le wick extrême
        final entryY = manipDir == 'up' ? mHy : mLy;
        canvas.drawCircle(
          Offset(mx2c, entryY), 5,
          Paint()..color = col..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        canvas.drawCircle(Offset(mx2c, entryY), 5, Paint()..color = col);

        // Arrow signal — exact copy
        final arrowY = isBull ? mLy + 22 : mHy - 22;
        final arrowPath = Path();
        if (isBull) {
          arrowPath.moveTo(mx2c,      arrowY - 13);
          arrowPath.lineTo(mx2c - 9,  arrowY + 2);
          arrowPath.lineTo(mx2c + 9,  arrowY + 2);
        } else {
          arrowPath.moveTo(mx2c,      arrowY + 13);
          arrowPath.lineTo(mx2c - 9,  arrowY - 2);
          arrowPath.lineTo(mx2c + 9,  arrowY - 2);
        }
        arrowPath.close();
        canvas.drawPath(arrowPath,
            Paint()..color = col.withOpacity(0.5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
        canvas.drawPath(arrowPath, Paint()..color = col);

        // Badge label — exact copy
        final lbl  = isBull ? '▲ BUY' : '▼ SELL';
        final ly   = isBull ? arrowY + 4 : arrowY - 17;
        final tp   = _measureText(lbl, 8, bold: true);
        final tw   = tp + 12;
        // Pill background
        final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(mx2c - tw / 2, ly, tw, 13), const Radius.circular(4));
        canvas.drawRRect(rect, Paint()..color = col.withOpacity(0.2));
        canvas.drawRRect(rect, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 1);
        _drawSmallText(canvas, lbl, Offset(mx2c - tw / 2 + 6, ly + 2), col, bold: true, size: 8, center: true, width: tw);

        // Sub-label 'MAN' — exact copy
        _drawSmallText(canvas, 'MAN',
            Offset(mx2c - 10, isBull ? ly + 15 : ly - 9),
            col.withOpacity(0.7), size: 6);

        // Active signal highlight ring
        final sig = state.jpSignals.where((sg) => sg.idx == manipIdx).firstOrNull;
        if (sig != null) {
          if (state.activeJPSig != null && state.activeJPSig!.idx == sig.idx) {
            canvas.drawCircle(
              Offset(mx2c, arrowY), 18,
              Paint()..color = col.withOpacity(0.4)..style = PaintingStyle.stroke..strokeWidth = 1.5,
            );
          }
          hitAreas.add(JPHitArea(cx: mx2c, cy: arrowY, radius: 24, sigIdx: sig.idx));
        }
      }
    }

    // ── TP/SL lines pour le signal actif — exact copy from HTML
    if (state.jpAutoTPSL && state.activeJPSig != null) {
      final atr   = state.calcATR();
      final sig   = state.activeJPSig!;
      final isBuy = sig.type == 'BUY';
      final entry = sig.price;
      final tp2   = isBuy ? entry + atr * state.jpTPAtr : entry - atr * state.jpTPAtr;
      final sl2   = isBuy ? entry - atr * state.jpSLAtr : entry + atr * state.jpSLAtr;

      final localIdx = sig.idx - s;
      final startX = (localIdx >= 0 && localIdx < vis.length)
          ? cL + (localIdx + 0.5) * cW
          : cL;

      // Entry line
      _dashLine(canvas,
        Paint()..color = Colors.white.withOpacity(0.35)..strokeWidth = 0.8,
        Offset(startX, p2y(entry, mn, mx, H)),
        Offset(cR,     p2y(entry, mn, mx, H)),
        dash: 3, gap: 4,
      );

      // TP line
      final tpY = p2y(tp2, mn, mx, H);
      if (tpY > padTop && tpY < H - padBottom) {
        _dashLine(canvas,
          Paint()..color = KintanaTheme.yellow..strokeWidth = 1.2
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
          Offset(startX, tpY), Offset(cR, tpY), dash: 6, gap: 4,
        );
        canvas.drawRect(Rect.fromLTWH(cR - 42, tpY - 9, 42, 14),
            Paint()..color = const Color(0xF00D1020));
        _drawSmallText(canvas, 'TP ${fp(tp2)}', Offset(cR - 38, tpY - 4),
            KintanaTheme.yellow, bold: true, size: 7);
      }

      // SL line
      final slY = p2y(sl2, mn, mx, H);
      if (slY > padTop && slY < H - padBottom) {
        _dashLine(canvas,
          Paint()..color = KintanaTheme.red..strokeWidth = 1.2
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
          Offset(startX, slY), Offset(cR, slY), dash: 6, gap: 4,
        );
        canvas.drawRect(Rect.fromLTWH(cR - 42, slY - 9, 42, 14),
            Paint()..color = const Color(0xF00D1020));
        _drawSmallText(canvas, 'SL ${fp(sl2)}', Offset(cR - 38, slY - 4),
            KintanaTheme.red, bold: true, size: 7);
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // ── Rest of chart drawing
  // ─────────────────────────────────────────────────────────

  void _drawEmptyText(Canvas canvas, Size size) {
    _drawSmallText(
      canvas,
      state.isReplay ? 'Select a date and tap LOAD' : 'Connecting to market data...',
      Offset(size.width / 2 - 80, size.height / 2),
      const Color(0x803D4A6B), size: 11,
    );
  }

  void _drawGrid(Canvas canvas, double W, double H, double mn, double mx) {
    for (int i = 0; i <= 8; i++) {
      final price = mn + (mx - mn) * (i / 8);
      final y     = p2y(price, mn, mx, H);
      _dashLine(canvas,
        Paint()
          ..color = i % 2 == 0 ? const Color(0xE5161D32) : const Color(0xB2121A2A)
          ..strokeWidth = 0.5,
        Offset(padLeft, y), Offset(W - padRight, y),
        dash: 2, gap: 5,
      );
    }
  }

  void _drawVolume(Canvas canvas, double W, double H, List<Candle> vis, double cW) {
    if (vis.isEmpty) return;
    final maxRange = vis.map((c) => c.range).reduce(max);
    if (maxRange == 0) return;
    final maxVH = H * 0.12;
    for (int i = 0; i < vis.length; i++) {
      final c  = vis[i];
      final vh = (c.range / maxRange) * maxVH;
      final x  = padLeft + (i + 0.5) * cW;
      canvas.drawRect(
        Rect.fromLTWH(x - cW * 0.35, H - padBottom - vh, cW * 0.7, vh),
        Paint()..color = (c.isBull ? KintanaTheme.green : KintanaTheme.red).withOpacity(0.12),
      );
    }
  }

  void _drawCandles(Canvas canvas, double H, List<Candle> vis, double cW, double bW, double mn, double mx) {
    for (int i = 0; i < vis.length; i++) {
      final c      = vis[i];
      final x      = padLeft + (i + 0.5) * cW;
      final openY  = p2y(c.open,  mn, mx, H);
      final closeY = p2y(c.close, mn, mx, H);
      final highY  = p2y(c.high,  mn, mx, H);
      final lowY   = p2y(c.low,   mn, mx, H);
      final bodyTop = min(openY, closeY);
      final bodyH   = max((closeY - openY).abs(), 1.0);
      final isBull  = c.isBull;
      final col     = isBull ? KintanaTheme.green : KintanaTheme.red;

      // Wick
      canvas.drawLine(Offset(x, highY), Offset(x, bodyTop),
          Paint()..color = col.withOpacity(0.7)..strokeWidth = 1.2);
      canvas.drawLine(Offset(x, bodyTop + bodyH), Offset(x, lowY),
          Paint()..color = col.withOpacity(0.7)..strokeWidth = 1.2);

      // Body gradient
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x - bW / 2, bodyTop, bW, bodyH), const Radius.circular(1.5));
      canvas.drawRRect(rect, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: isBull
              ? [KintanaTheme.green, KintanaTheme.green.withOpacity(0.7)]
              : [KintanaTheme.red.withOpacity(0.85), KintanaTheme.red],
        ).createShader(Rect.fromLTWH(x - bW / 2, bodyTop, bW, bodyH)));

      // Doji
      if (bodyH <= 1.5) {
        canvas.drawLine(Offset(x - bW / 2, openY), Offset(x + bW / 2, openY),
            Paint()..color = KintanaTheme.yellow.withOpacity(0.7)..strokeWidth = 1.5);
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
        final paint = Paint()..color = color..strokeWidth = 1.5;
        if (dashed) {
          _dashLine(canvas, paint, Offset(padLeft, y), Offset(W - padRight, y), dash: 6, gap: 3);
        } else {
          canvas.drawLine(Offset(padLeft, y), Offset(W - padRight, y), paint);
        }
        _drawPill(canvas, label, Offset(padLeft + 6, y - 7), color);
      }

      drawLine(t.entry, lc.withOpacity(0.8), t.status == 'pending',
          '${isBull ? '▲' : '▼'} ${t.status == 'pending' ? 'PENDING' : isBull ? 'BUY' : 'SELL'} @ ${fp(t.entry)}');
      if (t.sl  != null) drawLine(t.sl!,  KintanaTheme.red.withOpacity(0.7),   true, '🛑 SL ${fp(t.sl)}');
      if (t.tp1 != null) drawLine(t.tp1!, KintanaTheme.green.withOpacity(0.7), true, '🎯 TP ${fp(t.tp1)}');
    }
  }

  void _drawLivePriceLine(Canvas canvas, double W, double H, double mn, double mx, double cW, int s, int visLen) {
    final price = state.price!;
    final y = p2y(price, mn, mx, H);
    if (y < padTop || y > H - padBottom) return;
    final up  = state.prevPrice == null || price >= state.prevPrice!;
    final col = up ? KintanaTheme.green : KintanaTheme.red;

    // Glow
    canvas.drawLine(Offset(padLeft, y), Offset(W - padRight, y),
        Paint()..color = col.withOpacity(0.4)..strokeWidth = 2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));

    // Dashed line
    _dashLine(canvas, Paint()..color = col.withOpacity(0.7)..strokeWidth = 1.2,
        Offset(padLeft, y), Offset(W - padRight, y), dash: 5, gap: 3);

    // Price badge
    final badgeW = padRight - 2;
    final bx = W - padRight + 1;
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(bx, y - 8, badgeW, 16), const Radius.circular(3));
    canvas.drawRRect(rr, Paint()..color = col);
    _drawSmallText(canvas, fp(price), Offset(bx + 2, y - 5), const Color(0xFF050810), bold: true, size: 8);

    // Pulse dot
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
    canvas.drawLine(Offset(x, padTop), Offset(x, H - padBottom),
        Paint()..color = KintanaTheme.purple.withOpacity(0.6)..strokeWidth = 1);
  }

  void _drawYAxis(Canvas canvas, double W, double H, double mn, double mx) {
    for (int i = 0; i <= 8; i++) {
      final price = mn + (mx - mn) * (i / 8);
      final y     = p2y(price, mn, mx, H);
      if (y < padTop || y > H - padBottom) continue;
      _drawSmallText(canvas, fp(price), Offset(W - padRight + 3, y - 4), KintanaTheme.t3.withOpacity(0.9));
    }
  }

  void _drawXAxis(Canvas canvas, double W, double H, List<Candle> vis, double cW) {
    if (vis.isEmpty) return;
    final step = max(1, (vis.length / 6).ceil());
    for (int i = 0; i < vis.length; i += step) {
      final c  = vis[i];
      final x  = padLeft + (i + 0.5) * cW;
      final dt = DateTime.fromMillisecondsSinceEpoch(c.time * 1000);
      final lbl = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      _drawSmallText(canvas, lbl, Offset(x - 12, H - padBottom + 4), KintanaTheme.t3);
    }
  }

  void _drawCrosshair(Canvas canvas, double W, double H, double mn, double mx) {
    final x = mouseX!; final y = mouseY!;
    final paint = Paint()..color = KintanaTheme.t2.withOpacity(0.25)..strokeWidth = 0.5;
    _dashLine(canvas, paint, Offset(x, padTop), Offset(x, H - padBottom), dash: 3, gap: 4);
    _dashLine(canvas, paint, Offset(padLeft, y), Offset(W - padRight, y), dash: 3, gap: 4);
    final hp = y2p(y, mn, mx, H);
    canvas.drawRect(Rect.fromLTWH(W - padRight, y - 7.5, padRight - 1, 15), Paint()..color = const Color(0xF0101424));
    canvas.drawRect(Rect.fromLTWH(W - padRight, y - 7.5, padRight - 1, 15),
        Paint()..color = KintanaTheme.b2.withOpacity(0.9)..style = PaintingStyle.stroke..strokeWidth = 0.8);
    _drawSmallText(canvas, fp(hp), Offset(W - padRight + 3, y - 4.5), KintanaTheme.t1.withOpacity(0.8));
  }

  // ─────────────────────────────────────────────────────────
  // ── Drawing helpers
  // ─────────────────────────────────────────────────────────

  void _dashLine(Canvas canvas, Paint paint, Offset a, Offset b,
      {double dash = 2, double gap = 5}) {
    final dir = b - a;
    final len = dir.distance;
    if (len == 0) return;
    final unit = dir / len;
    double d = 0;
    while (d < len) {
      canvas.drawLine(a + unit * d, a + unit * min(d + dash, len), paint);
      d += dash + gap;
    }
  }

  void _dashRect(Canvas canvas, Rect rect, Color color, double strokeWidth,
      {double dash = 3, double gap = 3}) {
    final p = Paint()..color = color..strokeWidth = strokeWidth;
    final corners = [
      [rect.topLeft, rect.topRight],
      [rect.topRight, rect.bottomRight],
      [rect.bottomRight, rect.bottomLeft],
      [rect.bottomLeft, rect.topLeft],
    ];
    for (final seg in corners) _dashLine(canvas, p, seg[0], seg[1], dash: dash, gap: gap);
  }

  void _drawPill(Canvas canvas, String text, Offset pos, Color color) {
    final tp = _buildTP(text, 7.5, color, bold: true);
    const pad = 5.0;
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(pos.dx - pad, pos.dy - 1, tp.width + pad * 2, tp.height + 2), const Radius.circular(3));
    canvas.drawRRect(rect, Paint()..color = color.withOpacity(0.18));
    canvas.drawRRect(rect, Paint()..color = color.withOpacity(0.55)..style = PaintingStyle.stroke..strokeWidth = 0.8);
    tp.paint(canvas, pos);
  }

  TextPainter _buildTP(String text, double size, Color color, {bool bold = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        fontFamily: 'SpaceMono', fontSize: size, color: color,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      )),
      textDirection: TextDirection.ltr,
      textAlign: center ? TextAlign.center : TextAlign.left,
    )..layout();
    return tp;
  }

  double _measureText(String text, double size, {bool bold = false}) {
    return _buildTP(text, size, Colors.white, bold: bold).width;
  }

  void _drawSmallText(Canvas canvas, String text, Offset pos, Color color,
      {double size = 7.5, bool bold = false, bool center = false, double? width}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        fontFamily: 'SpaceMono', fontSize: size, color: color,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      )),
      textDirection: TextDirection.ltr,
      textAlign: center ? TextAlign.center : TextAlign.left,
    );
    if (width != null) tp.layout(minWidth: width, maxWidth: width);
    else tp.layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(CandleChartPainter old) => true;
}
