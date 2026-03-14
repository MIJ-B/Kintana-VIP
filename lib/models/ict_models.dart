// ═══════════════════════════════════════════════════════════════
// JORO Strategy — Models
// Supply & Demand Zones only: DBR / RBD / DBD / RBR
// ═══════════════════════════════════════════════════════════════

enum SDPattern { dbr, rbd, dbd, rbr }
enum SDZoneTypeV2 { demand, supply }

class SDZoneV2 {
  final int        id;
  final SDZoneTypeV2 type;
  final SDPattern  pattern;
  final double     top;
  final double     bottom;
  final int        baseStart;
  final int        baseEnd;
  final int        exitIdx;
  final double     strength;
  final double     atr;
  bool             tested;
  bool             invalidated;
  int?             retestIdx;

  SDZoneV2({
    required this.id,
    required this.type,
    required this.pattern,
    required this.top,
    required this.bottom,
    required this.baseStart,
    required this.baseEnd,
    required this.exitIdx,
    required this.strength,
    required this.atr,
    this.tested      = false,
    this.invalidated = false,
    this.retestIdx,
  });

  double get mid    => (top + bottom) / 2;
  bool   get isFresh => !tested;
  bool   get isBuy  => type == SDZoneTypeV2.demand;
}

// ── Signal: prix revient dans zone + rejection candle
enum JOROSignalDir { buy, sell }
enum JOROHitState  { none, tp, sl }

class JOROSDSignal {
  final int           id;
  final int           idx;
  final JOROSignalDir dir;
  final double        price;
  final double        sl;
  final double        tp;
  final SDPattern     pattern;
  final int           confidence;
  final bool          isFresh;
  JOROHitState        hitState;

  JOROSDSignal({
    required this.id,
    required this.idx,
    required this.dir,
    required this.price,
    required this.sl,
    required this.tp,
    required this.pattern,
    required this.confidence,
    required this.isFresh,
    this.hitState = JOROHitState.none,
  });

  bool   get isBuy => dir == JOROSignalDir.buy;
  String get rrStr {
    final risk   = (price - sl).abs();
    final reward = (tp - price).abs();
    if (risk == 0) return '—';
    return '1:${(reward / risk).toStringAsFixed(1)}';
  }
}

// ── Entry zone stage display (25/50/75/100%)
class JOROEntryZone {
  final double top;
  final double bottom;
  final bool   isBull;
  int          stage;

  JOROEntryZone({
    required this.top,
    required this.bottom,
    required this.isBull,
    this.stage = 25,
  });
}

// ── Full analysis result
class JOROAnalysis {
  final List<SDZoneV2>     zones;
  final List<JOROSDSignal> signals;
  JOROSDSignal?            activeSignal;
  JOROEntryZone?           entryZone;

  JOROAnalysis({
    required this.zones,
    required this.signals,
    this.activeSignal,
    this.entryZone,
  });

  factory JOROAnalysis.empty() => JOROAnalysis(zones: [], signals: []);
}
