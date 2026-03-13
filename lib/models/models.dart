// ?? Candle model
class Candle {
  final int time;
  final double open;
  double high;
  double low;
  double close;

  Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  factory Candle.fromMap(Map<String, dynamic> m) => Candle(
    time:  (m['epoch'] ?? m['time']) is int
        ? (m['epoch'] ?? m['time']) as int
        : int.parse((m['epoch'] ?? m['time']).toString()),
    open:  double.parse(m['open'].toString()),
    high:  double.parse(m['high'].toString()),
    low:   double.parse(m['low'].toString()),
    close: double.parse(m['close'].toString()),
  );

  bool get isBull => close >= open;
  double get body => (close - open).abs();
  double get range => high - low;
}

// ?? Market symbol
class Market {
  final String category;
  final String symbol;
  final String name;
  final String flag;
  final String type; // SYN, FX, CMD, etc.

  const Market({
    required this.category,
    required this.symbol,
    required this.name,
    required this.flag,
    required this.type,
  });
}

// ?? Trade / Signal
class Trade {
  final int id;
  final String symbol;
  final String direction; // long / short
  double entry;
  double? sl;
  double? tp1;
  double? tp2;
  double? tp3;
  double? entryZoneLow;
  double? entryZoneHigh;
  String status; // open, pending, closed_sl, closed_tp
  double? pnl;
  bool slTrailed;
  String? note;
  final double stake;
  final double leverage;
  final double lotSize;
  final DateTime date;
  bool hitChecked;

  Trade({
    required this.id,
    required this.symbol,
    required this.direction,
    required this.entry,
    this.sl,
    this.tp1,
    this.tp2,
    this.tp3,
    this.entryZoneLow,
    this.entryZoneHigh,
    this.status = 'open',
    this.pnl,
    this.slTrailed = false,
    this.note,
    this.stake = 10,
    this.leverage = 100000,
    this.lotSize = 0.01,
    DateTime? date,
    this.hitChecked = false,
  }) : date = date ?? DateTime.now();

  double? calcFloatPnl(double price) {
    final mult = lotSize * leverage;
    final diff = direction == 'long' ? price - entry : entry - price;
    return diff * mult / entry;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'symbol': symbol,
    'direction': direction,
    'entry': entry,
    'sl': sl,
    'tp1': tp1,
    'tp2': tp2,
    'tp3': tp3,
    'entryZoneLow': entryZoneLow,
    'entryZoneHigh': entryZoneHigh,
    'status': status,
    'pnl': pnl,
    'slTrailed': slTrailed,
    'note': note,
    'stake': stake,
    'leverage': leverage,
    'lotSize': lotSize,
    'date': date.toIso8601String(),
  };

  factory Trade.fromJson(Map<String, dynamic> j) => Trade(
    id: j['id'] as int,
    symbol: j['symbol'] as String,
    direction: j['direction'] as String,
    entry: (j['entry'] as num).toDouble(),
    sl: j['sl'] != null ? (j['sl'] as num).toDouble() : null,
    tp1: j['tp1'] != null ? (j['tp1'] as num).toDouble() : null,
    tp2: j['tp2'] != null ? (j['tp2'] as num).toDouble() : null,
    tp3: j['tp3'] != null ? (j['tp3'] as num).toDouble() : null,
    entryZoneLow: j['entryZoneLow'] != null ? (j['entryZoneLow'] as num).toDouble() : null,
    entryZoneHigh: j['entryZoneHigh'] != null ? (j['entryZoneHigh'] as num).toDouble() : null,
    status: j['status'] as String? ?? 'open',
    pnl: j['pnl'] != null ? (j['pnl'] as num).toDouble() : null,
    slTrailed: j['slTrailed'] as bool? ?? false,
    note: j['note'] as String?,
    stake: (j['stake'] as num?)?.toDouble() ?? 10,
    leverage: (j['leverage'] as num?)?.toDouble() ?? 100000,
    lotSize: (j['lotSize'] as num?)?.toDouble() ?? 0.01,
    date: j['date'] != null ? DateTime.parse(j['date']) : DateTime.now(),
  );
}

// ?? JOROpredict signal
class JOROSignal {
  final String direction; // BUY / SELL
  final String symbol;
  final String timeframe;
  final String strategy; // AMD, Swing
  final double entry;
  final double? sl;
  final double? tp1;
  final double? tp2;
  final double? tp3;
  final double? accZoneLow;
  final double? accZoneHigh;
  final double? manipLevel;
  final String? manipDir;
  final int confidence;
  final String reason;
  final String? rrRatio;

  const JOROSignal({
    required this.direction,
    required this.symbol,
    required this.timeframe,
    required this.strategy,
    required this.entry,
    this.sl,
    this.tp1,
    this.tp2,
    this.tp3,
    this.accZoneLow,
    this.accZoneHigh,
    this.manipLevel,
    this.manipDir,
    required this.confidence,
    required this.reason,
    this.rrRatio,
  });

  bool get isBuy => direction == 'BUY';

  factory JOROSignal.fromJson(Map<String, dynamic> j) => JOROSignal(
    direction: j['direction'] as String,
    symbol: j['symbol'] as String? ?? '',
    timeframe: j['timeframe'] as String? ?? '',
    strategy: j['strategy'] as String? ?? 'AMD',
    entry: (j['entry_exact'] as num?)?.toDouble() ?? 0,
    sl: j['sl'] != null ? (j['sl'] as num).toDouble() : null,
    tp1: j['tp1'] != null ? (j['tp1'] as num).toDouble() : null,
    tp2: j['tp2'] != null ? (j['tp2'] as num).toDouble() : null,
    tp3: j['tp3'] != null ? (j['tp3'] as num).toDouble() : null,
    accZoneLow: j['acc_zone_low'] != null ? (j['acc_zone_low'] as num).toDouble() : null,
    accZoneHigh: j['acc_zone_high'] != null ? (j['acc_zone_high'] as num).toDouble() : null,
    manipLevel: j['manipulation_level'] != null ? (j['manipulation_level'] as num).toDouble() : null,
    manipDir: j['manipulation_dir'] as String?,
    confidence: (j['confidence'] as num?)?.toInt() ?? 75,
    reason: j['reason'] as String? ?? '',
    rrRatio: j['rr_ratio'] as String?,
  );
}

// ?? Price formatted
String fp(double? p) {
  if (p == null || p.isNaN) return '—';
  if (p > 10000) return p.toStringAsFixed(2);
  if (p > 1000)  return p.toStringAsFixed(2);
  if (p > 10)    return p.toStringAsFixed(3);
  if (p > 0.1)   return p.toStringAsFixed(4);
  return p.toStringAsFixed(5);
}

// ?? All markets
const List<Market> kMarkets = [
  Market(category: 'Volatility Indices', symbol: 'R_10',    name: 'Volatility 10',       flag: '🔵', type: 'SYN'),
  Market(category: 'Volatility Indices', symbol: 'R_25',    name: 'Volatility 25',       flag: '🟢', type: 'SYN'),
  Market(category: 'Volatility Indices', symbol: 'R_50',    name: 'Volatility 50',       flag: '🟡', type: 'SYN'),
  Market(category: 'Volatility Indices', symbol: 'R_75',    name: 'Volatility 75',       flag: '🟠', type: 'SYN'),
  Market(category: 'Volatility Indices', symbol: 'R_100',   name: 'Volatility 100',      flag: '🔴', type: 'SYN'),
  Market(category: 'Volatility (1s)',    symbol: '1HZ10V',  name: 'Volatility 10 (1s)',  flag: '🔵', type: 'SYN'),
  Market(category: 'Volatility (1s)',    symbol: '1HZ25V',  name: 'Volatility 25 (1s)',  flag: '🟢', type: 'SYN'),
  Market(category: 'Volatility (1s)',    symbol: '1HZ50V',  name: 'Volatility 50 (1s)',  flag: '🟡', type: 'SYN'),
  Market(category: 'Volatility (1s)',    symbol: '1HZ75V',  name: 'Volatility 75 (1s)',  flag: '🟠', type: 'SYN'),
  Market(category: 'Volatility (1s)',    symbol: '1HZ100V', name: 'Volatility 100 (1s)', flag: '🔴', type: 'SYN'),
  Market(category: 'Boom & Crash',       symbol: 'BOOM300N',  name: 'Boom 300',          flag: '📈', type: 'SYN'),
  Market(category: 'Boom & Crash',       symbol: 'BOOM500',   name: 'Boom 500',          flag: '📈', type: 'SYN'),
  Market(category: 'Boom & Crash',       symbol: 'BOOM1000',  name: 'Boom 1000',         flag: '📈', type: 'SYN'),
  Market(category: 'Boom & Crash',       symbol: 'CRASH300N', name: 'Crash 300',         flag: '📉', type: 'SYN'),
  Market(category: 'Boom & Crash',       symbol: 'CRASH500',  name: 'Crash 500',         flag: '📉', type: 'SYN'),
  Market(category: 'Boom & Crash',       symbol: 'CRASH1000', name: 'Crash 1000',        flag: '📉', type: 'SYN'),
  Market(category: 'Step & Range',       symbol: 'stpRNG',    name: 'Step Index',        flag: '⚡', type: 'SYN'),
  Market(category: 'Step & Range',       symbol: 'RNGBULL100',name: 'Range Break 100',   flag: '📊', type: 'SYN'),
  Market(category: 'Forex Majors',  symbol: 'frxEURUSD', name: 'Euro / US Dollar',          flag: '🇪🇺', type: 'FX'),
  Market(category: 'Forex Majors',  symbol: 'frxGBPUSD', name: 'British Pound / USD',       flag: '🇬🇧', type: 'FX'),
  Market(category: 'Forex Majors',  symbol: 'frxUSDJPY', name: 'USD / Japanese Yen',        flag: '🇯🇵', type: 'FX'),
  Market(category: 'Forex Majors',  symbol: 'frxUSDCHF', name: 'USD / Swiss Franc',         flag: '🇨🇭', type: 'FX'),
  Market(category: 'Forex Majors',  symbol: 'frxAUDUSD', name: 'Australian Dollar / USD',   flag: '🇦🇺', type: 'FX'),
  Market(category: 'Forex Majors',  symbol: 'frxUSDCAD', name: 'USD / Canadian Dollar',     flag: '🇨🇦', type: 'FX'),
  Market(category: 'Forex Majors',  symbol: 'frxNZDUSD', name: 'New Zealand Dollar / USD',  flag: '🇳🇿', type: 'FX'),
  Market(category: 'Forex Cross',   symbol: 'frxEURGBP', name: 'Euro / British Pound',      flag: '🇪🇺', type: 'FX'),
  Market(category: 'Forex Cross',   symbol: 'frxEURJPY', name: 'Euro / Japanese Yen',       flag: '🇯🇵', type: 'FX'),
  Market(category: 'Forex Cross',   symbol: 'frxGBPJPY', name: 'GBP / Japanese Yen',        flag: '🇬🇧', type: 'FX'),
  Market(category: 'Commodities',   symbol: 'frxXAUUSD', name: 'Gold / US Dollar',          flag: '🥇', type: 'CMD'),
  Market(category: 'Commodities',   symbol: 'frxXAGUSD', name: 'Silver / US Dollar',        flag: '🥈', type: 'CMD'),
];

// ??????????????????????????????????????????????
// ?? Supply & Demand Zone (Loi d'offre et demande)
// ??????????????????????????????????????????????

enum SDZoneType { supply, demand }
enum SDZoneStatus { waiting, entered, confirmed, hitTP, hitSL, expired }

class SDZone {
  final int     id;
  final SDZoneType type;       // supply (SELL) or demand (BUY)
  final double  zoneHigh;      // top of yellow entry rectangle
  final double  zoneLow;       // bottom of yellow entry rectangle
  final int     originIdx;     // candle index where zone was detected
  final double  originClose;   // close of origin candle
  SDZoneStatus  status;

  // Step 3 ? confirmed signal levels
  double? entry;
  double? sl;
  double? tp;

  // LTF confirmation
  bool    ltfConfirmed;
  int?    ltfConfirmIdx;       // candle idx where LTF confirmed

  // Result tracking
  bool?   won;                 // true = hit TP, false = hit SL
  DateTime createdAt;

  SDZone({
    required this.id,
    required this.type,
    required this.zoneHigh,
    required this.zoneLow,
    required this.originIdx,
    required this.originClose,
    this.status = SDZoneStatus.waiting,
    this.entry,
    this.sl,
    this.tp,
    this.ltfConfirmed = false,
    this.ltfConfirmIdx,
    this.won,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isBuy  => type == SDZoneType.demand;
  bool get isSell => type == SDZoneType.supply;
  double get zoneMid => (zoneHigh + zoneLow) / 2;
  double get zoneSize => zoneHigh - zoneLow;

  bool priceInZone(double price) => price >= zoneLow && price <= zoneHigh;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'zoneHigh': zoneHigh,
    'zoneLow': zoneLow,
    'originIdx': originIdx,
    'originClose': originClose,
    'status': status.name,
    'entry': entry,
    'sl': sl,
    'tp': tp,
    'ltfConfirmed': ltfConfirmed,
    'ltfConfirmIdx': ltfConfirmIdx,
    'won': won,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SDZone.fromJson(Map<String, dynamic> j) => SDZone(
    id:           j['id'] as int,
    type:         SDZoneType.values.byName(j['type'] as String),
    zoneHigh:     (j['zoneHigh'] as num).toDouble(),
    zoneLow:      (j['zoneLow'] as num).toDouble(),
    originIdx:    j['originIdx'] as int,
    originClose:  (j['originClose'] as num).toDouble(),
    status:       SDZoneStatus.values.byName(j['status'] as String? ?? 'waiting'),
    entry:        j['entry'] != null ? (j['entry'] as num).toDouble() : null,
    sl:           j['sl']    != null ? (j['sl']    as num).toDouble() : null,
    tp:           j['tp']    != null ? (j['tp']    as num).toDouble() : null,
    ltfConfirmed: j['ltfConfirmed'] as bool? ?? false,
    ltfConfirmIdx:j['ltfConfirmIdx'] as int?,
    won:          j['won'] as bool?,
    createdAt:    j['createdAt'] != null ? DateTime.parse(j['createdAt']) : DateTime.now(),
  );
}
