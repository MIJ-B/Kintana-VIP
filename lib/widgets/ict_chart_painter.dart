// ═══════════════════════════════════════════════════════════════
// JORO Chart Painter — Supply & Demand (DBR/RBD/DBD/RBR)
// Zones, Signals (arrow + TP/SL), Entry Zone (stage 25→100%)
// ═══════════════════════════════════════════════════════════════

import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/ict_models.dart';
import '../services/market_state.dart';
import '../theme/kintana_theme.dart';
import 'candle_chart_painter.dart';


class ICTChartPainter extends CustomPainter {
  final MarketState state;
  final List<Candle> candles;
  final double zoom;
  final double offset;
  final double yOffset;
  final double? mouseX;
  final double? mouseY;

  static const double padTop    = CandleChartPainter.padTop;
  static const double padRight  = CandleChartPainter.padRight;
  static const double padBottom = CandleChartPainter.padBottom;
  static const double padLeft   = CandleChartPainter.padLeft;

  const ICTChartPainter({
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

  @override
  void paint(Canvas canvas, Size size) {
    if (!state.joroActive) return;
    final W = size.width;
    final H = size.height;
    if (candles.isEmpty) return;

    final s   = offset.round().clamp(0, candles.length - 1);
    final e   = min(candles.length - 1, s + zoom.round() - 1);
    final vis = candles.sublist(s, e + 1);

    double mn = vis.map((c) => c.low).reduce(min);
    double mx = vis.map((c) => c.high).reduce(max);
    final pad = (mx - mn) * 0.07;
    mn -= pad; mx += pad;
    if (yOffset != 0) {
      final range = mx - mn;
      mn += range * yOffset;
      mx += range * yOffset;
    }

    final cW = (W - padLeft - padRight) / zoom.round();
    final j  = state.joro;

    _drawZones(canvas, W, H, s, cW, mn, mx, j);
    _drawEntryZone(canvas, W, H, s, cW, mn, mx, j);
    _drawSignal(canvas, W, H, s, cW, mn, mx, j);
  }

  // ── 1. Supply & Demand Zones
  void _drawZones(Canvas canvas, double W, double H, int s, double cW,
      double mn, double mx, JOROAnalysis j) {
    final cL = padLeft;
    final cR = W - padRight;

    for (final zone in j.zones) {
      if (zone.invalidated) continue;

      final zy1 = p2y(zone.top,    mn, mx, H);
      final zy2 = p2y(zone.bottom, mn, mx, H);
      if (zy2 < padTop || zy1 > H - padBottom) continue;

      final col         = zone.isBuy ? KintanaTheme.green : KintanaTheme.red;
      final fillOpacity = zone.isFresh ? 0.10 : 0.05;

      // X de départ = base candle
      final baseLocal = zone.baseStart - s;
      final startX = (baseLocal >= 0 && baseLocal < zoom.round())
          ? padLeft + (baseLocal + 0.5) * cW
          : cL;

      // Fill
      canvas.drawRect(
        Rect.fromLTWH(startX, zy1, cR - startX, zy2 - zy1),
        Paint()..color = col.withOpacity(fillOpacity),
      );

      // Border (pointillée si tested, solide si fresh)
      if (zone.isFresh) {
        canvas.drawRect(
          Rect.fromLTWH(startX, zy1, cR - startX, zy2 - zy1),
          Paint()
            ..color = col.withOpacity(0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        // Glow subtil
        canvas.drawRect(
          Rect.fromLTWH(startX, zy1, cR - startX, zy2 - zy1),
          Paint()
            ..color = col.withOpacity(0.12)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      } else {
        _dashRect(canvas,
          Rect.fromLTWH(startX, zy1, cR - startX, zy2 - zy1),
          col.withOpacity(0.40), 0.8,
        );
      }

      // Label
      final patStr   = zone.pattern.name.toUpperCase();
      final typeStr  = zone.isBuy ? 'DEMAND' : 'SUPPLY';
      final freshStr = zone.isFresh ? ' · FRESH ✦' : '';
      final strengthStr = '${zone.strength.toStringAsFixed(1)}×';
      _drawSmallText(canvas,
        '${zone.isBuy ? '▲' : '▼'} $typeStr · $patStr$freshStr',
        Offset(startX + 5, zy1 + 4),
        col.withOpacity(0.9), bold: zone.isFresh, size: 7);

      // Strength badge (coin droit)
      _drawSmallText(canvas, strengthStr,
        Offset(cR - 28, zy1 + 4),
        col.withOpacity(0.6), size: 6.5);

      // Mid line
      final mid = (zy1 + zy2) / 2;
      _dashLine(canvas,
        Paint()..color = col.withOpacity(0.22)..strokeWidth = 0.5,
        Offset(startX, mid), Offset(cR, mid),
      );
    }
  }

  // ── 2. Entry Zone (stage 25/50/75/100%)
  void _drawEntryZone(Canvas canvas, double W, double H, int s, double cW,
      double mn, double mx, JOROAnalysis j) {
    final zone = j.entryZone;
    if (zone == null) return;

    final cL  = padLeft;
    final cR  = W - padRight;
    final zy1 = p2y(zone.top,    mn, mx, H);
    final zy2 = p2y(zone.bottom, mn, mx, H);
    if (zy2 < padTop || zy1 > H - padBottom) return;

    final baseCol = zone.isBull ? KintanaTheme.green : KintanaTheme.red;
    final pendCol = const Color(0xFF8B4A2E); // marron si pas encore 100%
    final col     = zone.stage == 100 ? baseCol : pendCol;
    final zH      = zy2 - zy1;

    final fillAlpha = zone.stage == 25 ? 0.07
        : zone.stage == 50 ? 0.11
        : zone.stage == 75 ? 0.16 : 0.22;

    // Fill
    canvas.drawRect(Rect.fromLTWH(cL, zy1, cR - cL, zH),
      Paint()..color = (zone.stage == 100 ? baseCol : pendCol).withOpacity(fillAlpha));

    // Glow pour 75+
    if (zone.stage >= 75) {
      canvas.drawRect(Rect.fromLTWH(cL, zy1, cR - cL, zH),
        Paint()
          ..color = col.withOpacity(0.12)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, zone.stage == 100 ? 12 : 6));
    }

    // Border
    if (zone.stage < 50) {
      _dashRect(canvas, Rect.fromLTWH(cL, zy1, cR - cL, zH),
          col.withOpacity(0.40), 0.9);
    } else if (zone.stage < 100) {
      _dashRect(canvas, Rect.fromLTWH(cL, zy1, cR - cL, zH),
          col.withOpacity(0.60), 1.0, dash: 3, gap: 3);
    } else {
      canvas.drawRect(Rect.fromLTWH(cL, zy1, cR - cL, zH),
        Paint()
          ..color = col.withOpacity(0.90)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    }

    // Badge principal
    final stageText = zone.stage == 100
        ? '${zone.isBull ? '▲' : '▼'} CONFIRMED ✓'
        : '${zone.isBull ? '▲' : '▼'} ENTRY ZONE ⏳';
    _drawPill(canvas, stageText, Offset(cL + 8, zy1 + zH / 2 - 7), col);

    // Badge %
    _drawPill(canvas, '${zone.stage}%', Offset(cR - 34, zy1 + 4), col);

    // Prix
    _drawSmallText(canvas, fp(zone.top),    Offset(cR - 58, zy1 - 9),  col.withOpacity(0.7), size: 6);
    _drawSmallText(canvas, fp(zone.bottom), Offset(cR - 58, zy2 + 3),  col.withOpacity(0.7), size: 6);

    // Barre de progression
    const barH = 3.0;
    final barY = zy2 - barH - 1;
    final barW = cR - cL;
    canvas.drawRect(Rect.fromLTWH(cL, barY, barW, barH),
        Paint()..color = Colors.white.withOpacity(0.08));
    canvas.drawRect(Rect.fromLTWH(cL, barY, barW * (zone.stage / 100), barH),
        Paint()..color = col.withOpacity(0.85));

    // Mid line
    final mid = (zy1 + zy2) / 2;
    _dashLine(canvas,
      Paint()..color = col.withOpacity(0.30)..strokeWidth = 0.5,
      Offset(cL, mid), Offset(cR, mid),
    );
  }

  // ── 3. Signal actif (arrow BUY/SELL + TP/SL rects + ✓/✗)
  void _drawSignal(Canvas canvas, double W, double H, int s, double cW,
      double mn, double mx, JOROAnalysis j) {
    final sig = j.activeSignal;
    if (sig == null) return;

    final cL    = padLeft;
    final cR    = W - padRight;
    final col   = sig.isBuy ? KintanaTheme.green : KintanaTheme.red;
    final lIdx  = sig.idx - s;
    final hasVis = lIdx >= 0 && lIdx < zoom.round();
    final arrowX = hasVis ? padLeft + (lIdx + 0.5) * cW : cL + 20;

    final entY = p2y(sig.price, mn, mx, H);
    final tpY  = p2y(sig.tp,   mn, mx, H);
    final slY  = p2y(sig.sl,   mn, mx, H);

    // ── Arrow + dot (si pas encore touché)
    if (hasVis && sig.hitState == JOROHitState.none) {
      final candleIdx = sig.idx.clamp(0, candles.length - 1);
      final dotY   = sig.isBuy
          ? p2y(candles[candleIdx].low,  mn, mx, H)
          : p2y(candles[candleIdx].high, mn, mx, H);
      final arrowY = sig.isBuy ? dotY + 22 : dotY - 22;

      // Dot avec glow
      canvas.drawCircle(Offset(arrowX, dotY), 6,
          Paint()..color = col.withOpacity(0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(Offset(arrowX, dotY), 3, Paint()..color = col);

      // Triangle
      final path = Path();
      if (sig.isBuy) {
        path.moveTo(arrowX, arrowY - 13);
        path.lineTo(arrowX - 9, arrowY + 2);
        path.lineTo(arrowX + 9, arrowY + 2);
      } else {
        path.moveTo(arrowX, arrowY + 13);
        path.lineTo(arrowX - 9, arrowY - 2);
        path.lineTo(arrowX + 9, arrowY - 2);
      }
      path.close();
      canvas.drawPath(path,
          Paint()..color = col
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawPath(path, Paint()..color = col);

      // Badge BUY/SELL + pattern + confidence
      final lbl = '${sig.isBuy ? "▲ BUY" : "▼ SELL"} · ${sig.pattern.name.toUpperCase()} ${sig.confidence}%${sig.isFresh ? " ✦" : ""}';
      _drawPill(canvas, lbl,
        Offset(arrowX - lbl.length * 3.2, sig.isBuy ? arrowY + 4 : arrowY - 18),
        col);
    }

    // ── TP / SL rectangles
    if (sig.hitState == JOROHitState.none) {
      // TP
      final tpTop = min(entY, tpY);
      final tpHt  = (tpY - entY).abs();
      if (tpHt > 2) {
        canvas.drawRect(Rect.fromLTWH(arrowX, tpTop, cR - arrowX, tpHt),
          Paint()..color = KintanaTheme.green.withOpacity(0.09));
        canvas.drawRect(Rect.fromLTWH(arrowX, tpTop, cR - arrowX, tpHt),
          Paint()..color = KintanaTheme.green.withOpacity(0.70)
            ..style = PaintingStyle.stroke..strokeWidth = 1.0);
        _drawSmallText(canvas, 'TP  ${fp(sig.tp)}  (${sig.rrStr})',
          Offset(cR - 95, sig.isBuy ? tpTop + 10 : tpTop + tpHt - 12),
          KintanaTheme.green.withOpacity(0.95), bold: true, size: 7);
      }

      // SL
      final slTop = min(entY, slY);
      final slHt  = (slY - entY).abs();
      if (slHt > 2) {
        canvas.drawRect(Rect.fromLTWH(arrowX, slTop, cR - arrowX, slHt),
          Paint()..color = KintanaTheme.red.withOpacity(0.09));
        canvas.drawRect(Rect.fromLTWH(arrowX, slTop, cR - arrowX, slHt),
          Paint()..color = KintanaTheme.red.withOpacity(0.70)
            ..style = PaintingStyle.stroke..strokeWidth = 1.0);
        _drawSmallText(canvas, 'SL  ${fp(sig.sl)}',
          Offset(cR - 68, sig.isBuy ? slTop + slHt - 12 : slTop + 10),
          KintanaTheme.red.withOpacity(0.95), bold: true, size: 7);
      }

      // Ligne entry pointillée
      _dashLine(canvas,
        Paint()..color = Colors.white.withOpacity(0.38)..strokeWidth = 0.8,
        Offset(arrowX, entY), Offset(cR, entY),
      );
      _drawSmallText(canvas, 'ENTRY  ${fp(sig.price)}',
        Offset(cR - 90, entY - 9),
        Colors.white.withOpacity(0.58), bold: true, size: 6.5);
    }

    // ── TP Hit ✓
    if (sig.hitState == JOROHitState.tp) {
      final tpTop = min(entY, tpY);
      final tpHt  = (tpY - entY).abs();
      canvas.drawRect(Rect.fromLTWH(arrowX, tpTop, cR - arrowX, tpHt),
        Paint()..color = KintanaTheme.green.withOpacity(0.18));
      canvas.drawRect(Rect.fromLTWH(arrowX, tpTop, cR - arrowX, tpHt),
        Paint()..color = KintanaTheme.green.withOpacity(0.9)
          ..style = PaintingStyle.stroke..strokeWidth = 1.5);
      _drawBigCheck(canvas, '✓',
        Offset((arrowX + cR) / 2, tpTop + tpHt / 2 + 12), KintanaTheme.green);
    }

    // ── SL Hit ✗
    if (sig.hitState == JOROHitState.sl) {
      final slTop = min(entY, slY);
      final slHt  = (slY - entY).abs();
      canvas.drawRect(Rect.fromLTWH(arrowX, slTop, cR - arrowX, slHt),
        Paint()..color = KintanaTheme.red.withOpacity(0.18));
      canvas.drawRect(Rect.fromLTWH(arrowX, slTop, cR - arrowX, slHt),
        Paint()..color = KintanaTheme.red.withOpacity(0.9)
          ..style = PaintingStyle.stroke..strokeWidth = 1.5);
      _drawBigCheck(canvas, '✗',
        Offset((arrowX + cR) / 2, slTop + slHt / 2 + 12), KintanaTheme.red);
    }
  }

  // ══ Helpers ═══════════════════════════════════════════════

  void _dashLine(Canvas canvas, Paint paint, Offset a, Offset b,
      {double dash = 4, double gap = 4}) {
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

  void _dashRect(Canvas canvas, Rect rect, Color color, double sw,
      {double dash = 4, double gap = 4}) {
    final p = Paint()..color = color..strokeWidth = sw;
    for (final seg in [
      [rect.topLeft, rect.topRight],
      [rect.topRight, rect.bottomRight],
      [rect.bottomRight, rect.bottomLeft],
      [rect.bottomLeft, rect.topLeft],
    ]) { _dashLine(canvas, p, seg[0], seg[1], dash: dash, gap: gap); }
  }

  void _drawSmallText(Canvas canvas, String text, Offset pos, Color color,
      {double size = 7.5, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        fontFamily: 'SpaceMono', fontSize: size, color: color,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  void _drawPill(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        fontFamily: 'SpaceMono', fontSize: 7.5, color: color,
        fontWeight: FontWeight.bold,
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    const pad = 5.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pos.dx - pad, pos.dy - 1, tp.width + pad * 2, tp.height + 2),
      const Radius.circular(3),
    );
    canvas.drawRRect(rect, Paint()..color = color.withOpacity(0.18));
    canvas.drawRRect(rect, Paint()
      ..color = color.withOpacity(0.55)
      ..style = PaintingStyle.stroke..strokeWidth = 0.8);
    tp.paint(canvas, pos);
  }

  void _drawBigCheck(Canvas canvas, String text, Offset center, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        fontFamily: 'SpaceMono', fontSize: 34, color: color,
        fontWeight: FontWeight.bold,
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.drawCircle(center, 22, Paint()
      ..color = color.withOpacity(0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(ICTChartPainter old) => true;
}
