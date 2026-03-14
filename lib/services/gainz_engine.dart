// ═══════════════════════════════════════════════════════════════
// JORO Engine — Supply & Demand (DBR / RBD / DBD / RBR)
// Port exact depuis GainzAlpha v5 HTML
// ═══════════════════════════════════════════════════════════════

import 'dart:math';
import '../models/models.dart';
import '../models/ict_models.dart';

class GainzEngine {
  static int _idCounter = 1;

  // ── ATR(10)
  static double _atr(List<Candle> c, int i) {
    const per = 10;
    final from = max(1, i - per + 1);
    double s = 0; int ct = 0;
    for (int k = from; k <= i; k++) {
      s += max(c[k].high - c[k].low,
           max((c[k].high - c[k-1].close).abs(),
               (c[k].low  - c[k-1].close).abs()));
      ct++;
    }
    if (ct > 0 && s / ct > 0) return s / ct;
    final r = c[i].high - c[i].low;
    return r > 0 ? r : 1.0;
  }

  // ── Force d'un move sur N candles (distance / ATR)
  static double _moveStrength(List<Candle> c, int from, int to) {
    if (to <= from) return 0;
    double h = -double.infinity, l = double.infinity;
    for (int i = from; i <= to; i++) {
      if (c[i].high > h) h = c[i].high;
      if (c[i].low  < l) l = c[i].low;
    }
    final a = _atr(c, to);
    return (h - l) / (a > 0 ? a : 1);
  }

  // ── Trouve une BASE: N candles consécutives range < 1× ATR
  static _Base? _findBase(List<Candle> c, int start, int maxLen) {
    final n = c.length;
    final a = _atr(c, start);
    for (int len = 1; len <= maxLen; len++) {
      if (start + len >= n) break;
      final sl = c.sublist(start, start + len);
      final hi = sl.map((x) => x.high).reduce(max);
      final lo = sl.map((x) => x.low).reduce(min);
      if (hi - lo > a * 1.0) {
        if (len > 1) {
          final sl2 = c.sublist(start, start + len - 1);
          return _Base(
            startIdx: start, endIdx: start + len - 2, len: len - 1,
            high: sl2.map((x) => x.high).reduce(max),
            low:  sl2.map((x) => x.low).reduce(min),
          );
        }
        return null;
      }
    }
    if (start + maxLen <= n) {
      final sl2 = c.sublist(start, start + maxLen);
      return _Base(
        startIdx: start, endIdx: start + maxLen - 1, len: maxLen,
        high: sl2.map((x) => x.high).reduce(max),
        low:  sl2.map((x) => x.low).reduce(min),
      );
    }
    return null;
  }

  // ════════════════════════════════════════════════════════════
  // MAIN — calcule les zones S&D + signaux
  // ════════════════════════════════════════════════════════════
  static JOROAnalysis compute(List<Candle> candles) {
    if (candles.length < 20) return JOROAnalysis.empty();
    final n      = candles.length;
    final zones  = <SDZoneV2>[];
    final signals = <JOROSDSignal>[];

    // ══ ÉTAPE 1: Détecter les zones Supply & Demand ══
    for (int i = 3; i < n - 4; i++) {
      final a          = _atr(candles, i);
      final lookback   = min(5, i);
      final moveBefore = _moveStrength(candles, i - lookback, i);
      final base       = _findBase(candles, i, 6);
      if (base == null || base.len < 1) continue;

      final afterIdx = base.endIdx + 1;
      if (afterIdx >= n - 1) continue;

      final lookfwd   = min(5, n - afterIdx - 1);
      final moveAfter = _moveStrength(candles, afterIdx, afterIdx + lookfwd);
      if (moveAfter < 1.8) continue; // impulsion sortante insuffisante

      final exit       = candles[afterIdx];
      final bullExit   = exit.close > exit.open && exit.close > base.high;
      final bearExit   = exit.close < exit.open && exit.close < base.low;
      if (!bullExit && !bearExit) continue;

      // Classer le pattern
      SDZoneType  zType;
      SDPattern   pattern;
      if (bullExit) {
        zType   = SDZoneType.demand;
        pattern = moveBefore >= 1.5 ? SDPattern.dbr : SDPattern.rbr;
      } else {
        zType   = SDZoneType.supply;
        pattern = moveBefore >= 1.5 ? SDPattern.rbd : SDPattern.dbd;
      }

      // Éviter doublons
      if (zones.any((z) =>
          z.type == zType && z.top >= base.low && z.bottom <= base.high)) {
        continue;
      }

      // Vérifier retest / invalidation
      bool tested = false, invalidated = false;
      int? retestIdx;
      for (int j = afterIdx + 1; j < n; j++) {
        final c = candles[j];
        if (zType == SDZoneType.demand) {
          if (c.low <= base.high && c.close >= base.low) {
            tested = true; retestIdx ??= j;
          }
          if (c.close < base.low) { invalidated = true; break; }
        } else {
          if (c.high >= base.low && c.close <= base.high) {
            tested = true; retestIdx ??= j;
          }
          if (c.close > base.high) { invalidated = true; break; }
        }
      }

      zones.add(SDZoneV2(
        id:          _idCounter++,
        type:        zType,
        pattern:     pattern,
        top:         base.high,
        bottom:      base.low,
        baseStart:   base.startIdx,
        baseEnd:     base.endIdx,
        exitIdx:     afterIdx,
        strength:    moveAfter,
        atr:         a,
        tested:      tested,
        invalidated: invalidated,
        retestIdx:   retestIdx,
      ));
    }

    // ══ ÉTAPE 2: Générer les signaux (prix revient + rejection) ══
    for (final zone in zones) {
      if (zone.invalidated) continue;
      final searchFrom = zone.exitIdx + 1;

      for (int i = searchFrom; i < n; i++) {
        final c = candles[i];
        final a = _atr(candles, i);

        if (zone.isBuy) {
          // DEMAND: prix touche la zone par le bas
          final inZone    = c.low <= zone.top && c.low >= zone.bottom - a * 0.3;
          final rejection = c.close > zone.mid && c.close > c.open;
          if (c.close < zone.bottom - a * 0.1) { zone.invalidated = true; break; }

          if (inZone && rejection) {
            if (!signals.any((sg) => (sg.idx - i).abs() <= 3)) {
              final sl = zone.bottom - a * 0.3;
              // TP = prochaine zone Supply au-dessus
              final nextSupply = zones
                  .where((z) => !z.isBuy && !z.invalidated && z.bottom > zone.top)
                  .toList()
                ..sort((a2, b2) => a2.bottom.compareTo(b2.bottom));
              final tp = nextSupply.isNotEmpty
                  ? nextSupply.first.bottom
                  : c.close + a * 2;
              final conf = zone.isFresh
                  ? (zone.strength > 3 ? 90 : 82)
                  : (zone.strength > 3 ? 75 : 65);
              signals.add(JOROSDSignal(
                id: _idCounter++, idx: i,
                dir: JOROSignalDir.buy, price: c.close,
                sl: sl, tp: tp,
                pattern: zone.pattern,
                confidence: conf,
                isFresh: zone.isFresh,
              ));
            }
            break; // 1 signal par zone
          }
        } else {
          // SUPPLY: prix touche la zone par le haut
          final inZone    = c.high >= zone.bottom && c.high <= zone.top + a * 0.3;
          final rejection = c.close < zone.mid && c.close < c.open;
          if (c.close > zone.top + a * 0.1) { zone.invalidated = true; break; }

          if (inZone && rejection) {
            if (!signals.any((sg) => (sg.idx - i).abs() <= 3)) {
              final sl = zone.top + a * 0.3;
              final nextDemand = zones
                  .where((z) => z.isBuy && !z.invalidated && z.top < zone.bottom)
                  .toList()
                ..sort((a2, b2) => b2.top.compareTo(a2.top));
              final tp = nextDemand.isNotEmpty
                  ? nextDemand.first.top
                  : c.close - a * 2;
              final conf = zone.isFresh
                  ? (zone.strength > 3 ? 90 : 82)
                  : (zone.strength > 3 ? 75 : 65);
              signals.add(JOROSDSignal(
                id: _idCounter++, idx: i,
                dir: JOROSignalDir.sell, price: c.close,
                sl: sl, tp: tp,
                pattern: zone.pattern,
                confidence: conf,
                isFresh: zone.isFresh,
              ));
            }
            break;
          }
        }
      }
    }

    // ── Signal actif = dernier signal non-invalidé
    JOROSDSignal? active;
    if (signals.isNotEmpty) {
      active = signals.last;
      // Vérifier TP/SL déjà touché
      for (int i = active.idx + 1; i < n; i++) {
        final c = candles[i];
        if (active.isBuy) {
          if (c.high >= active.tp) { active.hitState = JOROHitState.tp; break; }
          if (c.low  <= active.sl) { active.hitState = JOROHitState.sl; break; }
        } else {
          if (c.low  <= active.tp) { active.hitState = JOROHitState.tp; break; }
          if (c.high >= active.sl) { active.hitState = JOROHitState.sl; break; }
        }
      }
    }

    // ── Entry Zone (stage basé sur la force de la zone)
    JOROEntryZone? entryZone;
    if (active != null && active.hitState == JOROHitState.none) {
      // Trouver la zone source du signal
      final srcZone = zones.where((z) =>
        z.isBuy == active!.isBuy &&
        !z.invalidated &&
        z.exitIdx < active.idx,
      ).toList();

      final zoneRef = srcZone.isNotEmpty ? srcZone.last : null;
      final zTop    = zoneRef?.top    ?? active.price + _atr(candles, active.idx) * 0.2;
      final zBottom = zoneRef?.bottom ?? active.price - _atr(candles, active.idx) * 0.3;

      // Stage selon la force et fraîcheur de la zone
      int stage;
      final str = zoneRef?.strength ?? 2.0;
      final fresh = zoneRef?.isFresh ?? false;
      if (str >= 3.5 && fresh) stage = 100;
      else if (str >= 2.5)     stage = 75;
      else if (str >= 2.0)     stage = 50;
      else                     stage = 25;

      entryZone = JOROEntryZone(
        top:    zTop,
        bottom: zBottom,
        isBull: active.isBuy,
        stage:  stage,
      );
    }

    return JOROAnalysis(
      zones:        zones,
      signals:      signals,
      activeSignal: active,
      entryZone:    entryZone,
    );
  }

  static double calcATRnow(List<Candle> candles) {
    if (candles.length < 2) return 1.0;
    return _atr(candles, candles.length - 1);
  }
}

class _Base {
  final int startIdx, endIdx, len;
  final double high, low;
  const _Base({
    required this.startIdx, required this.endIdx, required this.len,
    required this.high, required this.low,
  });
}
