import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/market_state.dart';
import '../models/models.dart';
import '../theme/kintana_theme.dart';

enum _Role { user, ai }

class _ChatMsg {
  final _Role role;
  final String text;
  final JOROSignal? signal;
  final bool isTyping;
  final DateTime time;

  _ChatMsg({
    required this.role,
    required this.text,
    this.signal,
    this.isTyping = false,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}

class JoroScreen extends StatefulWidget {
  const JoroScreen({super.key});
  @override
  State<JoroScreen> createState() => _JoroScreenState();
}

class _JoroScreenState extends State<JoroScreen> {
  final _msgs = <_ChatMsg>[];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
  String _selectedModel = 'llama-3.3-70b-versatile';

  final _models = [
    {'id': 'compound-beta', 'label': 'Compound'},
    {'id': 'compound-beta-mini', 'label': 'Mini'},
    {'id': 'llama-3.3-70b-versatile', 'label': 'Llama 3.3'},
    {'id': 'meta-llama/llama-4-scout-17b-16e-instruct', 'label': 'Llama 4'},
    {'id': 'moonshotai/kimi-k2-instruct', 'label': 'Kimi-K2'},
    {'id': 'llama-3.1-8b-instant', 'label': 'Fast'},
  ];

  @override
  void initState() {
    super.initState();
    _msgs.add(_ChatMsg(
      role: _Role.ai,
      text: 'WELCOME',
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = context.read<MarketState>();
      _selectedModel = s.groqModel;
      // Listen for S&D win/loss results
      s.addListener(_onMarketStateChange);
    });
  }

  void _onMarketStateChange() {
    final s = context.read<MarketState>();
    if (s.sdLastResultMsg != null) {
      final msg = s.sdLastResultMsg!;
      s.sdLastResultMsg = null;
      setState(() {
        _msgs.add(_ChatMsg(role: _Role.ai, text: msg));
      });
      _scrollDown();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try { context.read<MarketState>().removeListener(_onMarketStateChange); } catch (_) {}
      }
    });
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ?? Market context string
  String _buildContext(MarketState s) {
    final candles = s.getCandles();
    final last15 = candles.takeLast(15).map((c) =>
        'O:${fp(c.open)} H:${fp(c.high)} L:${fp(c.low)} C:${fp(c.close)}').join('|');
    final closes = candles.takeLast(20).map((c) => c.close).toList();
    final ema8 = closes.length >= 8 ? closes.sublist(closes.length - 8).reduce((a, b) => a + b) / 8 : null;
    final ema20 = closes.length >= 20 ? closes.reduce((a, b) => a + b) / 20 : null;
    final allH = candles.isEmpty ? 0.0 : candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final allL = candles.isEmpty ? 0.0 : candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final last10 = candles.takeLast(10);
    final bullCount = last10.where((c) => c.close >= c.open).length;
    final bearCount = 10 - bullCount;
    final momentum = bearCount > bullCount
        ? 'BEARISH ($bearCount/10 bear candles)'
        : 'BULLISH ($bullCount/10 bull candles)';
    final trend = ema8 != null && ema20 != null
        ? (ema8 > ema20 ? 'BULLISH (EMA8 above EMA20)' : 'BEARISH (EMA8 below EMA20)')
        : 'N/A';
    final curPrice = s.isReplay && candles.isNotEmpty ? candles.last.close : s.price;
    final jpInfo = s.joropredictActive && s.jpSignals.isNotEmpty
        ? '\nJOROpredict signals (last 3): ${s.jpSignals.takeLast(3).map((sg) => '${sg.type}@${fp(sg.price)}').join(', ')}'
        : '';

    return '''=== MARKET DATA (${s.isReplay ? 'Replay' : 'Real-time Deriv'}) ===
Symbol: ${s.sym} (${s.sname}) | Timeframe: ${s.tf}s
Current Price: ${fp(curPrice)}
Session High: ${fp(allH)} | Session Low: ${fp(allL)}
EMA8: ${fp(ema8)} | EMA20: ${fp(ema20)}
Trend: $trend
Momentum (last 10 bars): $momentum
Bars loaded: ${candles.length}$jpInfo
Last 15 OHLC candles (oldest→newest): $last15
=== IMPORTANT: Analyze direction from data. BEARISH → SELL. BULLISH → BUY. ===''';
  }

  // ?? AMD system prompt
  static const _amdSystem = '''You are JORO, elite AMD (Accumulation/Manipulation/Distribution) trading AI for Deriv, forex, crypto.

AMD Strategy:
- ACCUMULATION: Price consolidates in tight range — institutions accumulating
- MANIPULATION: Fakeout/stop hunt breaks the range then returns inside — retail traders trapped
- DISTRIBUTION: Real breakout in true direction after manipulation

CRITICAL: Respond ONLY with this exact JSON (no markdown, no extra text):
{"direction":"BUY","symbol":"R_100","timeframe":"M15","strategy":"AMD","acc_zone_low":1200.00,"acc_zone_high":1220.00,"manipulation_level":1195.00,"manipulation_dir":"down","entry_exact":1210.00,"sl":1190.00,"tp1":1250.00,"tp2":1280.00,"tp3":1320.00,"confidence":82,"reason":"2 sentence AMD analysis","rr_ratio":"1:3.5"}

Rules:
- direction = true direction AFTER manipulation (opposite of fakeout)
- entry_exact = entry right at manipulation candle close or retest
- sl = beyond manipulation wick extreme
- tps at logical distribution targets''';

  Future<void> _send([String? type]) async {
    final s = context.read<MarketState>();
    if (s.groqKey.isEmpty) {
      setState(() {
        _msgs.add(_ChatMsg(role: _Role.ai, text: '⚠️ Mila GROQ API Key — aleha amin\'ny Settings ary save ny key!'));
      });
      _scrollDown();
      return;
    }

    final userText = type == 'amd'
        ? 'Analyse AMD signal — ${s.sym} ${s.tf}s'
        : type == 'trend'
        ? 'Is the trend bullish or bearish? Explain price action.'
        : type == 'sr'
        ? 'What are key support and resistance levels right now?'
        : type == 'status'
        ? 'AMD Status — phases actuelles?'
        : _inputCtrl.text.trim();

    if (userText.isEmpty) return;

    setState(() {
      _msgs.add(_ChatMsg(role: _Role.user, text: userText));
      _msgs.add(_ChatMsg(role: _Role.ai, text: '', isTyping: true));
      _sending = true;
      _inputCtrl.clear();
    });
    _scrollDown();

    final context2 = _buildContext(s);
    final isAMD = type == 'amd';
    final systemPrompt = isAMD ? _amdSystem : '''You are JORO, expert trading analyst for Deriv/forex markets. Be concise, insightful, action-oriented. Use emojis sparingly. Format key data clearly.''';

    try {
      final res = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer ${s.groqKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _selectedModel,
          'max_tokens': isAMD ? 600 : 800,
          'temperature': isAMD ? 0.2 : 0.7,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': '$context2\n\nUser: $userText'},
          ],
        }),
      );

      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final rawText = data['choices']?[0]?['message']?['content'] as String? ?? 'Error';

      JOROSignal? sig;
      String displayText = rawText;

      if (isAMD) {
        try {
          final clean = rawText.replaceAll('```json', '').replaceAll('```', '').trim();
          final j = jsonDecode(clean) as Map<String, dynamic>;
          sig = JOROSignal.fromJson(j);
          displayText = '';
        } catch (_) {
          displayText = rawText;
        }
      }

      setState(() {
        _msgs.removeLast(); // remove typing
        _msgs.add(_ChatMsg(role: _Role.ai, text: displayText, signal: sig));
        _sending = false;
      });
      _scrollDown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.removeLast();
        _msgs.add(_ChatMsg(role: _Role.ai, text: '❌ Error: $e'));
        _sending = false;
      });
      _scrollDown();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildMessages()),
        _buildQuickActions(),
        _buildInput(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(
        color: KintanaTheme.bg2,
        border: Border(bottom: BorderSide(color: KintanaTheme.b1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: KintanaTheme.acc, width: 2),
                  boxShadow: KintanaTheme.glowAcc,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    'https://i.ibb.co/jvXcY5xS/Chat-GPT-Image-Mar-8-2026-10-07-09-AM.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text('🤖', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('JORO', style: KintanaTheme.sans(size: 15, weight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(
                            gradient: KintanaTheme.accGrad,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('AI ANALYST', style: KintanaTheme.mono(size: 8, color: Colors.white, letterSpacing: 1)),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          width: 5, height: 5,
                          decoration: const BoxDecoration(color: KintanaTheme.acc, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 4),
                        Text('Ready to analyze', style: KintanaTheme.mono(size: 10, color: KintanaTheme.acc)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Model selector
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text('MODEL:', style: KintanaTheme.mono(size: 8, color: KintanaTheme.t3)),
                const SizedBox(width: 6),
                ..._models.map((m) {
                  final active = _selectedModel == m['id'];
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedModel = m['id']!);
                      context.read<MarketState>()
                        ..groqModel = m['id']!
                        ..saveSettings();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: active ? KintanaTheme.acc.withOpacity(0.08) : KintanaTheme.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: active ? KintanaTheme.acc : KintanaTheme.b2,
                        ),
                      ),
                      child: Text(
                        m['label']!,
                        style: KintanaTheme.mono(
                          size: 8,
                          color: active ? KintanaTheme.acc : KintanaTheme.t2,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: _msgs.length,
      itemBuilder: (ctx, i) {
        final msg = _msgs[i];
        return _buildMsg(msg).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1);
      },
    );
  }

  Widget _buildMsg(_ChatMsg msg) {
    if (msg.text == 'WELCOME') return _buildWelcomeMsg();
    if (msg.isTyping) return _buildTyping();
    if (msg.signal != null) return _buildSignalCard(msg.signal!);

    final isUser = msg.role == _Role.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KintanaTheme.b2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.network(
                  'https://i.ibb.co/jvXcY5xS/Chat-GPT-Image-Mar-8-2026-10-07-09-AM.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(child: Text('🤖', style: TextStyle(fontSize: 14))),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isUser ? KintanaTheme.acc.withOpacity(0.1) : KintanaTheme.card,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isUser ? 12 : 4),
                  topRight: Radius.circular(isUser ? 4 : 12),
                  bottomLeft: const Radius.circular(12),
                  bottomRight: const Radius.circular(12),
                ),
                border: Border.all(
                  color: isUser ? KintanaTheme.acc.withOpacity(0.25) : KintanaTheme.b1,
                ),
              ),
              child: Text(
                msg.text,
                style: KintanaTheme.sans(size: 12, color: KintanaTheme.t1),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: KintanaTheme.card2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KintanaTheme.b2),
              ),
              child: const Center(child: Text('👤', style: TextStyle(fontSize: 14))),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWelcomeMsg() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: KintanaTheme.b2)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.network(
                'https://i.ibb.co/jvXcY5xS/Chat-GPT-Image-Mar-8-2026-10-07-09-AM.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(child: Text('🤖')),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KintanaTheme.card,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4), topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12),
                ),
                border: Border.all(color: KintanaTheme.b1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(text: TextSpan(
                    style: KintanaTheme.sans(size: 12),
                    children: [
                      const TextSpan(text: 'Salama! '),
                      TextSpan(text: 'JORO', style: KintanaTheme.sans(size: 12, color: KintanaTheme.acc, weight: FontWeight.bold)),
                      const TextSpan(text: ' eto 📊\n\n'),
                      TextSpan(text: '⭐ VIP KINTANA', style: KintanaTheme.sans(size: 12, color: KintanaTheme.yellow, weight: FontWeight.bold)),
                      const TextSpan(text: ' — Chart HD, Replay Advanced, ary JORO AI!\n\nStratégie:\n'),
                      TextSpan(text: '🎯 Swing', style: KintanaTheme.sans(size: 12, color: KintanaTheme.acc, weight: FontWeight.bold)),
                      const TextSpan(text: ' — Trend, entry/TP/SL\n'),
                      TextSpan(text: '⚡ JOROpredict AMD', style: KintanaTheme.sans(size: 12, color: KintanaTheme.purpleL, weight: FontWeight.bold)),
                      const TextSpan(text: ' — Liquidity trap detection'),
                    ],
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTyping() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: KintanaTheme.b2)),
            child: const Center(child: Text('🤖', style: TextStyle(fontSize: 14))),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: KintanaTheme.card,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4), topRight: Radius.circular(12),
                bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12),
              ),
              border: Border.all(color: KintanaTheme.b1),
            ),
            child: Row(
              children: List.generate(3, (i) {
                return Container(
                  margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                  child: _TypingDot(delay: i * 150),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalCard(JOROSignal sig) {
    final isBuy = sig.isBuy;
    final col = isBuy ? KintanaTheme.green : KintanaTheme.red;
    final s = context.read<MarketState>();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: KintanaTheme.b2)),
            child: const Center(child: Text('🤖', style: TextStyle(fontSize: 14))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0D1020), Color(0xFF090C18)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: KintanaTheme.b2),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: KintanaTheme.b1)),
                    ),
                    child: Row(
                      children: [
                        NeonBadge(
                          label: '${isBuy ? '▲' : '▼'} ${sig.direction}',
                          color: col,
                        ),
                        const SizedBox(width: 7),
                        Text(sig.symbol, style: KintanaTheme.mono(size: 11, weight: FontWeight.bold)),
                        const SizedBox(width: 7),
                        NeonBadge(label: '⚡ AMD', color: KintanaTheme.acc),
                        const Spacer(),
                        Text(sig.timeframe, style: KintanaTheme.mono(size: 8, color: KintanaTheme.t3)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(13),
                    child: Column(
                      children: [
                        // Entry / SL
                        Row(
                          children: [
                            Expanded(child: _sigItem('⚡ ENTRY', fp(sig.entry), KintanaTheme.acc, isEntry: true)),
                            const SizedBox(width: 6),
                            Expanded(child: _sigItem('🛑 SL', fp(sig.sl), KintanaTheme.red, isSL: true)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // TPs
                        if (sig.tp1 != null) _tpRow('TP1', sig.tp1!, sig.rrRatio),
                        if (sig.tp2 != null) _tpRow('TP2', sig.tp2!,
                            sig.rrRatio != null ? '1:${(double.tryParse(sig.rrRatio!.split(':').last) ?? 1) * 2}' : null),
                        const SizedBox(height: 8),
                        // Confidence bar
                        Row(
                          children: [
                            Text('CONFIDENCE', style: KintanaTheme.mono(size: 8, color: KintanaTheme.t3)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: KintanaTheme.b1,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: sig.confidence / 100,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: KintanaTheme.accGrad,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${sig.confidence}%', style: KintanaTheme.mono(size: 10, color: KintanaTheme.acc, weight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Reason
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: KintanaTheme.card,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: KintanaTheme.b1),
                          ),
                          child: Text(sig.reason, style: KintanaTheme.sans(size: 10, color: KintanaTheme.t2)),
                        ),
                        const SizedBox(height: 10),
                        // Apply button
                        SizedBox(
                          width: double.infinity,
                          child: GestureDetector(
                            onTap: () => _applySignal(sig),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                gradient: isBuy ? KintanaTheme.buyGrad : KintanaTheme.sellGrad,
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: isBuy ? KintanaTheme.glowGreen : KintanaTheme.glowRed,
                              ),
                              child: Center(
                                child: Text(
                                  '${isBuy ? '📈' : '📉'} APPLY SIGNAL',
                                  style: KintanaTheme.mono(
                                    size: 10,
                                    color: isBuy ? KintanaTheme.bg : Colors.white,
                                    weight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95), duration: 400.ms, curve: Curves.elasticOut),
          ),
        ],
      ),
    );
  }

  Widget _sigItem(String label, String value, Color col, {bool isEntry = false, bool isSL = false}) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: col.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: col.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: KintanaTheme.mono(size: 7, color: KintanaTheme.t3)),
          const SizedBox(height: 3),
          Text(value, style: KintanaTheme.mono(size: 13, color: col, weight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _tpRow(String label, double price, String? rr) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: KintanaTheme.green.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: KintanaTheme.green.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Text(label, style: KintanaTheme.mono(size: 9, color: KintanaTheme.green, weight: FontWeight.bold)),
          const SizedBox(width: 6),
          if (rr != null)
            Text('R:R $rr', style: KintanaTheme.mono(size: 8, color: KintanaTheme.t3)),
          const Spacer(),
          Text(fp(price), style: KintanaTheme.mono(size: 11, color: KintanaTheme.green, weight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _applySignal(JOROSignal sig) {
    final s = context.read<MarketState>();
    final trade = Trade(
      id: DateTime.now().millisecondsSinceEpoch,
      symbol: sig.symbol.isNotEmpty ? sig.symbol : s.sym,
      direction: sig.isBuy ? 'long' : 'short',
      entry: sig.entry,
      sl: sig.sl,
      tp1: sig.tp1,
      tp2: sig.tp2,
      tp3: sig.tp3,
      status: 'open',
      note: 'JORO AMD Signal — ${sig.reason}',
    );
    s.addTrade(trade);
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Signal applied: ${sig.direction} @ ${fp(sig.entry)}'),
        backgroundColor: sig.isBuy ? KintanaTheme.green : KintanaTheme.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: KintanaTheme.b1)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _qBtn('⚡ AMD Signal', () => _send('amd'), highlight: true),
          const SizedBox(width: 5),
          _qBtn('🔍 AMD Status', () => _send('status')),
          const SizedBox(width: 5),
          _qBtn('📐 S/R Levels', () => _send('sr')),
          const SizedBox(width: 5),
          _qBtn('📈 Trend', () => _send('trend')),
        ],
      ),
    );
  }

  Widget _qBtn(String label, VoidCallback onTap, {bool highlight = false}) {
    return GestureDetector(
      onTap: () { onTap(); HapticFeedback.lightImpact(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        decoration: BoxDecoration(
          color: highlight ? KintanaTheme.purple.withOpacity(0.15) : KintanaTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: highlight ? KintanaTheme.purple.withOpacity(0.5) : KintanaTheme.b2,
          ),
        ),
        child: Center(
          child: Text(label, style: KintanaTheme.mono(
            size: 10,
            color: highlight ? KintanaTheme.purpleL : KintanaTheme.t2,
            weight: FontWeight.bold,
          )),
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: const BoxDecoration(
        color: KintanaTheme.bg2,
        border: Border(top: BorderSide(color: KintanaTheme.b1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: KintanaTheme.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KintanaTheme.b2),
              ),
              child: TextField(
                controller: _inputCtrl,
                style: KintanaTheme.sans(size: 12),
                maxLines: 3,
                minLines: 1,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Ask JORO anything about the market...',
                  hintStyle: KintanaTheme.sans(size: 12, color: KintanaTheme.t3),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : () => _send(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _sending ? KintanaTheme.acc.withOpacity(0.5) : KintanaTheme.acc,
                borderRadius: BorderRadius.circular(10),
                boxShadow: KintanaTheme.glowAcc,
              ),
              child: _sending
                  ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)))
                  : const Icon(Icons.send_rounded, color: Color(0xFF050810), size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDot extends StatefulWidget {
  final int delay;
  const _TypingDot({required this.delay});
  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _anim = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.5, curve: Curves.easeInOut)),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Opacity(
      opacity: _anim.value,
      child: Container(
        width: 6, height: 6,
        decoration: const BoxDecoration(color: KintanaTheme.acc, shape: BoxShape.circle),
      ),
    ),
  );
}

extension<T> on Iterable<T> {
  List<T> takeLast(int n) {
    final list = toList();
    return list.length <= n ? list : list.sublist(list.length - n);
  }
}
