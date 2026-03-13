import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/market_state.dart';
import '../theme/kintana_theme.dart';

class CandleChartPainter extends CustomPainter {
  final MarketState state;
  final List<Candle> candles;
  final double zoom;
  final double offset;
  final double yOffset;
  final double? mouseX;
  final double? mouseY;

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
  });

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

    canvas.drawRect(
      Rect.fromLTWH(0, 0, W, H),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF03050E), Color(0xFF050812)],
      ).createShader(Rect.fromLTWH(0, 0, W, H)),
    );

    if (candles.isEmpty) { _drawEmptyText(canvas, size); return; }

    final s         = offset.round().clamp(0, candles.length - 1);
    final e         = min(candles.length - 1, s + zoom.round() - 1);
    final vis       = candles.sublist(s, e + 1);
    final totalSlots = zoom.round();

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
    _drawSDZones(canvas, W, H, s, cW, mn, mx);

    if (!state.isReplay && state.price != null) {
      _drawLivePriceLine(canvas, W, H, mn, mx, cW, s, vis.length);
    }
    if (state.isReplay && state.replayTicks.isNotEmpty) {
      _drawReplayCursor(canvas, W, H, s, cW, totalSlots);
    }

    _drawYAxis(canvas, W, H, mn, mx);
    _drawXAxis(canvas, W, H, vis, cW);

    if (mouseX != null && mouseY != null) {
      _drawCrosshair(canvas, W, H, mn, mx);
    }
  }

  // ============================================================
  // -- Supply & Demand Zones Drawing
  // ============================================================
  void _drawSDZones(Canvas canvas, double W, double H,
      int s, double cW, double mn, double mx) {
    if (!state.sdActive) return;
    final cL = padLeft;
    final cR = W - padRight;

    for (final zone in state.sdZones) {
      if (zone.status == SDZoneStatus.expired) continue;

      final zy1 = p2y(zone.zoneHigh, mn, mx, H);
      final zy2 = p2y(zone.zoneLow,  mn, mx, H);
      if (zy2 < padTop || zy1 > H - padBottom) continue;

      final isBuy = zone.isBuy;

      // -- Waiting / Entered: yellow rectangle
      if (zone.status == SDZoneStatus.waiting ||
          zone.status == SDZoneStatus.entered) {
        final entered   = zone.status == SDZoneStatus.entered;
        final fillCol   = entered
            ? const Color(0x33FFD740)
            : const Color(0x1AFFD740);
        final strokeCol = entered
            ? const Color(0xCCFFD740)
            : const Color(0x80FFD740);

        canvas.drawRect(
          Rect.fromLTWH(cL, zy1, cR - cL, zy2 - zy1),
          Paint()..color = fillCol,
        );
        _dashRect(canvas,
          Rect.fromLTWH(cL, zy1, cR - cL, zy2 - zy1),
          strokeCol, 1.0, dash: 5, gap: 3);

        _drawSmallText(canvas,
            isBuy ? 'DEMAND ZONE (BUY)' : 'SUPPLY ZONE (SELL)',
            Offset(cL + 6, zy1 + 4),
            const Color(0xE5FFD740), bold: true, size: 7);

        if (entered && !zone.ltfConfirmed) {
          _drawSmallText(canvas, 'Price in zone - awaiting LTF confirmation...',
              Offset(cL + 6, zy2 - 12),
              const Color(0xCCFFD740), size: 6);
        }
      }

      // -- Confirmed: SL (red) + TP (green) rectangles
      if (zone.status == SDZoneStatus.confirmed &&
          zone.entry != null && zone.sl != null && zone.tp != null) {
        final entryY = p2y(zone.entry!, mn, mx, H);
        final slY    = p2y(zone.sl!,    mn, mx, H);
        final tpY    = p2y(zone.tp!,    mn, mx, H);

        // SL rect (red)
        final slTop = min(entryY, slY);
        final slHt  = (entryY - slY).abs();
        canvas.drawRect(
          Rect.fromLTWH(cL, slTop, cR - cL, slHt),
          Paint()..color = const Color(0x22FF3D57),
        );
        _dashRect(canvas,
          Rect.fromLTWH(cL, slTop, cR - cL, slHt),
          const Color(0x99FF3D57), 1.0);
        _drawSmallText(canvas, 'SL ${fp(zone.sl)}',
            Offset(cL + 6, slTop + 4),
            const Color(0xE5FF3D57), bold: true, size: 7);

        // TP rect (green)
        final tpTop = min(entryY, tpY);
        final tpHt  = (entryY - tpY).abs();
        canvas.drawRect(
          Rect.fromLTWH(cL, tpTop, cR - cL, tpHt),
          Paint()..color = const Color(0x2200E676),
        );
        _dashRect(canvas,
          Rect.fromLTWH(cL, tpTop, cR - cL, tpHt),
          const Color(0x9900E676), 1.0);
        _drawSmallText(canvas, 'TP ${fp(zone.tp)}',
            Offset(cL + 6, tpTop + 4),
            const Color(0xE500E676), bold: true, size: 7);

        // Entry line
        _dashLine(canvas,
          Paint()..color = const Color(0xCCFFD740)..strokeWidth = 1.5,
          Offset(cL, entryY), Offset(cR, entryY), dash: 6, gap: 3);
        _drawSmallText(canvas, 'ENTRY ${fp(zone.entry)}',
            Offset(cL + 6, entryY - 10),
            const Color(0xE5FFD740), bold: true, size: 7);

        // Yellow zone outline (faint)
        _dashRect(canvas,
          Rect.fromLTWH(cL, zy1, cR - cL, zy2 - zy1),
          const Color(0x40FFD740), 0.7, dash: 3, gap: 4);

        // LTF confirmation label
        _drawSmallText(canvas,
            'LTF confirmed - ${isBuy ? "BUY" : "SELL"}',
            Offset(cL + 6, zy1 + 4),
            const Color(0xCCFFD740), bold: true, size: 6.5);
      }

      // -- Hit TP / SL: fade result
      if (zone.status == SDZoneStatus.hitTP ||
          zone.status == SDZoneStatus.hitSL) {
        final hit   = zone.status == SDZoneStatus.hitTP;
        final fCol  = hit ? const Color(0x2200E676) : const Color(0x22FF3D57);
        final sCol  = hit ? const Color(0x6600E676) : const Color(0x66FF3D57);
        final tCol  = hit ? const Color(0xE500E676) : const Color(0xE5FF3D57);
        canvas.drawRect(
          Rect.fromLTWH(cL, zy1, cR - cL, zy2 - zy1),
          Paint()..color = fCol,
        );
        _dashRect(canvas,
          Rect.fromLTWH(cL, zy1, cR - cL, zy2 - zy1),
          sCol, 0.8);
        _drawSmallText(canvas,
            hit ? 'TP HIT' : 'SL HIT',
            Offset(cL + 6, zy1 + 4),
            tCol, bold: true, size: 8);
      }
    }
  }

  // ============================================================
  // -- Standard chart drawing
  // ============================================================
  void _drawEmptyText(Canvas canvas, Size size) {
    _drawSmallText(
      canvas,
      state.isReplay
          ? 'Select a date and tap LOAD'
          : 'Connecting to market data...',
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
          ..color = i % 2 == 0
              ? const Color(0xE5161D32)
              : const Color(0xB2121A2A)
          ..strokeWidth = 0.5,
        Offset(padLeft, y), Offset(W - padRight, y),
        dash: 2, gap: 5,
      );
    }
  }

  void _drawVolume(Canvas canvas, double W, double H,
      List<Candle> vis, double cW) {
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
        Paint()..color =
            (c.isBull ? KintanaTheme.green : KintanaTheme.red).withOpacity(0.12),
      );
    }
  }

  void _drawCandles(Canvas canvas, double H, List<Candle> vis,
      double cW, double bW, double mn, double mx) {
    for (int i = 0; i < vis.length; i++) {
      final c      = vis[i];
      final x      = padLeft + (i + 0.5) * cW;
      final openY  = p2y(c.open,  mn, mx, H);
      final closeY = p2y(c.close, mn, mx, H);
      final highY  = p2y(c.high,  mn, mx, H);
      final lowY   = p2y(c.low,   mn, mx, H);
      final bodyTop = min(openY, closeY);
      final bodyH   = max((closeY - openY).abs(), 1.0);
      final col     = c.isBull ? KintanaTheme.green : KintanaTheme.red;

      canvas.drawLine(Offset(x, highY), Offset(x, bodyTop),
          Paint()..color = col.withOpacity(0.7)..strokeWidth = 1.2);
      canvas.drawLine(Offset(x, bodyTop + bodyH), Offset(x, lowY),
          Paint()..color = col.withOpacity(0.7)..strokeWidth = 1.2);

      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x - bW / 2, bodyTop, bW, bodyH),
          const Radius.circular(1.5));
      canvas.drawRRect(rect, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: c.isBull
              ? [KintanaTheme.green, KintanaTheme.green.withOpacity(0.7)]
              : [KintanaTheme.red.withOpacity(0.85), KintanaTheme.red],
        ).createShader(Rect.fromLTWH(x - bW / 2, bodyTop, bW, bodyH)));

      if (bodyH <= 1.5) {
        canvas.drawLine(Offset(x - bW / 2, openY), Offset(x + bW / 2, openY),
            Paint()..color = KintanaTheme.yellow.withOpacity(0.7)..strokeWidth = 1.5);
      }
    }
  }

  void _drawTradeLines(Canvas canvas, double W, double H,
      double mn, double mx) {
    for (final t in state.trades) {
      if (t.status != 'open' && t.status != 'pending') continue;
      final isBull = t.direction == 'long';
      final lc = isBull ? KintanaTheme.green : KintanaTheme.red;

      void drawLine(double price, Color color, bool dashed, String label) {
        final y = p2y(price, mn, mx, H);
        if (y < padTop || y > H - padBottom) return;
        final paint = Paint()..color = color..strokeWidth = 1.5;
        if (dashed) {
          _dashLine(canvas, paint, Offset(padLeft, y),
              Offset(W - padRight, y), dash: 6, gap: 3);
        } else {
          canvas.drawLine(Offset(padLeft, y), Offset(W - padRight, y), paint);
        }
        _drawPill(canvas, label, Offset(padLeft + 6, y - 7), color);
      }

      drawLine(t.entry, lc.withOpacity(0.8), t.status == 'pending',
          '${isBull ? "^" : "v"} ${t.status == "pending" ? "PENDING" : isBull ? "BUY" : "SELL"} @ ${fp(t.entry)}');
      if (t.sl  != null) drawLine(t.sl!,  KintanaTheme.red.withOpacity(0.7),   true, 'SL ${fp(t.sl)}');
      if (t.tp1 != null) drawLine(t.tp1!, KintanaTheme.green.withOpacity(0.7), true, 'TP ${fp(t.tp1)}');
    }
  }

  void _drawLivePriceLine(Canvas canvas, double W, double H,
      double mn, double mx, double cW, int s, int visLen) {
    final price = state.price!;
    final y = p2y(price, mn, mx, H);
    if (y < padTop || y > H - padBottom) return;
    final up  = state.prevPrice == null || price >= state.prevPrice!;
    final col = up ? KintanaTheme.green : KintanaTheme.red;

    canvas.drawLine(Offset(padLeft, y), Offset(W - padRight, y),
        Paint()..color = col.withOpacity(0.4)..strokeWidth = 2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    _dashLine(canvas,
        Paint()..color = col.withOpacity(0.7)..strokeWidth = 1.2,
        Offset(padLeft, y), Offset(W - padRight, y), dash: 5, gap: 3);

    final badgeW = padRight - 2;
    final bx = W - padRight + 1;
    final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, y - 8, badgeW, 16), const Radius.circular(3));
    canvas.drawRRect(rr, Paint()..color = col);
    _drawSmallText(canvas, fp(price), Offset(bx + 2, y - 5),
        const Color(0xFF050810), bold: true, size: 8);

    final lastLocal = state.candles.length - 1 - s;
    if (lastLocal >= 0 && lastLocal < visLen) {
      final lx = padLeft + (lastLocal + 0.5) * cW;
      canvas.drawCircle(Offset(lx, y), 6,
          Paint()..color = col.withOpacity(0.22));
      canvas.drawCircle(Offset(lx, y), 2.5, Paint()..color = col);
    }
  }

  void _drawReplayCursor(Canvas canvas, double W, double H,
      int s, double cW, int totalSlots) {
    final rIdx  = state.replayIdx - 1;
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
      _drawSmallText(canvas, fp(price),
          Offset(W - padRight + 3, y - 4),
          KintanaTheme.t3.withOpacity(0.9));
    }
  }

  void _drawXAxis(Canvas canvas, double W, double H,
      List<Candle> vis, double cW) {
    if (vis.isEmpty) return;
    final step = max(1, (vis.length / 6).ceil());
    for (int i = 0; i < vis.length; i += step) {
      final c  = vis[i];
      final x  = padLeft + (i + 0.5) * cW;
      final dt = DateTime.fromMillisecondsSinceEpoch(c.time * 1000);
      final lbl =
          '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';
      _drawSmallText(canvas, lbl, Offset(x - 12, H - padBottom + 4),
          KintanaTheme.t3);
    }
  }

  void _drawCrosshair(Canvas canvas, double W, double H,
      double mn, double mx) {
    final x = mouseX!; final y = mouseY!;
    final paint =
        Paint()..color = KintanaTheme.t2.withOpacity(0.25)..strokeWidth = 0.5;
    _dashLine(canvas, paint, Offset(x, padTop), Offset(x, H - padBottom),
        dash: 3, gap: 4);
    _dashLine(canvas, paint, Offset(padLeft, y), Offset(W - padRight, y),
        dash: 3, gap: 4);
    final hp = y2p(y, mn, mx, H);
    canvas.drawRect(
        Rect.fromLTWH(W - padRight, y - 7.5, padRight - 1, 15),
        Paint()..color = const Color(0xF0101424));
    canvas.drawRect(
        Rect.fromLTWH(W - padRight, y - 7.5, padRight - 1, 15),
        Paint()
          ..color = KintanaTheme.b2.withOpacity(0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
    _drawSmallText(canvas, fp(hp), Offset(W - padRight + 3, y - 4.5),
        KintanaTheme.t1.withOpacity(0.8));
  }

  // ============================================================
  // -- Helpers
  // ============================================================
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
      [rect.topLeft,    rect.topRight],
      [rect.topRight,   rect.bottomRight],
      [rect.bottomRight, rect.bottomLeft],
      [rect.bottomLeft, rect.topLeft],
    ];
    for (final seg in corners) {
      _dashLine(canvas, p, seg[0], seg[1], dash: dash, gap: gap);
    }
  }

  void _drawPill(Canvas canvas, String text, Offset pos, Color color) {
    final tp  = _buildTP(text, 7.5, color, bold: true);
    const pad = 5.0;
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
            pos.dx - pad, pos.dy - 1, tp.width + pad * 2, tp.height + 2),
        const Radius.circular(3));
    canvas.drawRRect(rect, Paint()..color = color.withOpacity(0.18));
    canvas.drawRRect(rect,
        Paint()
          ..color = color.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
    tp.paint(canvas, pos);
  }

  TextPainter _buildTP(String text, double size, Color color,
      {bool bold = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'SpaceMono',
            fontSize: size,
            color: color,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          )),
      textDirection: TextDirection.ltr,
      textAlign: center ? TextAlign.center : TextAlign.left,
    )..layout();
    return tp;
  }

  void _drawSmallText(Canvas canvas, String text, Offset pos, Color color,
      {double size = 7.5,
      bool bold = false,
      bool center = false,
      double? width}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'SpaceMono',
            fontSize: size,
            color: color,
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
