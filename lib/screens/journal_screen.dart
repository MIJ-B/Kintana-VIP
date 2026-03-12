import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/market_state.dart';
import '../models/models.dart';
import '../theme/kintana_theme.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  int _tab = 0; // 0=news 1=trades 2=calendar
  List<Map<String, dynamic>> _news = [];
  bool _newsLoading = false;
  bool _newsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNews());
  }

  Future<void> _loadNews() async {
    final s = context.read<MarketState>();
    if (s.groqKey.isEmpty || _newsLoading) return;
    setState(() => _newsLoading = true);
    try {
      final res = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {'Authorization': 'Bearer ${s.groqKey}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'compound-beta',
          'max_tokens': 400,
          'temperature': 0.3,
          'messages': [
            {'role': 'user', 'content': 'Give 4 current forex/financial news headlines in JSON array: [{"title","summary","impact"}] — no markdown. Respond only JSON.'}
          ],
        }),
      );
      final data = jsonDecode(res.body);
      final txt = data['choices']?[0]?['message']?['content'] as String? ?? '[]';
      final clean = txt.replaceAll('```json', '').replaceAll('```', '').trim();
      final parsed = jsonDecode(clean) as List;
      setState(() {
        _news = parsed.cast<Map<String, dynamic>>();
        _newsLoading = false;
        _newsLoaded = true;
      });
    } catch (_) {
      setState(() => _newsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<MarketState>();
    return Column(
      children: [
        _buildTabs(s),
        Expanded(child: _buildContent(s)),
      ],
    );
  }

  Widget _buildTabs(MarketState s) {
    final tabs = ['📰 News', '📒 Journal', '📅 Calendar'];
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      decoration: const BoxDecoration(
        color: KintanaTheme.bg2,
        border: Border(bottom: BorderSide(color: KintanaTheme.b1)),
      ),
      child: Row(
        children: [
          ...List.generate(tabs.length, (i) {
            final active = _tab == i;
            return GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 2),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? KintanaTheme.card : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                  border: active ? Border.all(color: KintanaTheme.b1) : null,
                ),
                child: Text(
                  tabs[i],
                  style: KintanaTheme.mono(
                    size: 10,
                    color: active ? KintanaTheme.acc : KintanaTheme.t3,
                    weight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          if (_tab == 1 && s.trades.isNotEmpty)
            GestureDetector(
              onTap: () => _confirmClearAll(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: KintanaTheme.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: KintanaTheme.red.withOpacity(0.4)),
                ),
                child: Text('🗑 Clear All', style: KintanaTheme.mono(size: 10, color: KintanaTheme.red)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(MarketState s) {
    switch (_tab) {
      case 0: return _buildNews(s);
      case 1: return _buildTrades(s);
      case 2: return _buildCalendar();
      default: return const SizedBox();
    }
  }

  Widget _buildNews(MarketState s) {
    if (s.groqKey.isEmpty) {
      return _emptyState('📰', 'Add GROQ Key in Settings for live news');
    }
    if (_newsLoading) {
      return const Center(child: CircularProgressIndicator(color: KintanaTheme.acc));
    }
    if (!_newsLoaded || _news.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _emptyState('📰', 'No news loaded'),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _loadNews,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: KintanaTheme.acc.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KintanaTheme.acc.withOpacity(0.4)),
              ),
              child: Text('Refresh News', style: KintanaTheme.mono(size: 10, color: KintanaTheme.acc)),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: _news.map((n) {
        final impact = n['impact'] as String? ?? 'Low';
        final impactColor = impact == 'High' ? KintanaTheme.red : impact == 'Medium' ? KintanaTheme.yellow : KintanaTheme.green;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: KintanaTheme.card,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: KintanaTheme.b1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(n['title'] as String? ?? '', style: KintanaTheme.sans(size: 12, weight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(n['summary'] as String? ?? '', style: KintanaTheme.sans(size: 10, color: KintanaTheme.t2)),
              const SizedBox(height: 6),
              NeonBadge(label: impact, color: impactColor, fontSize: 8),
            ],
          ),
        ).animate().fadeIn(duration: 300.ms);
      }).toList(),
    );
  }

  Widget _buildTrades(MarketState s) {
    if (s.trades.isEmpty) {
      return _emptyState('📒', 'No trades yet\nApply a signal from JORO');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: s.trades.length,
      itemBuilder: (ctx, i) {
        final t = s.trades[i];
        final curP = s.isReplay && s.replayAll.isNotEmpty
            ? s.replayAll[s.replayIdx - 1 < 0 ? 0 : s.replayIdx - 1].close
            : s.price;
        final pnl = t.pnl ?? (curP != null && t.status == 'open' ? t.calcFloatPnl(curP) : null);
        final pnlStr = pnl != null ? '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}\$' : '—';
        final pnlColor = pnl != null ? (pnl >= 0 ? KintanaTheme.green : KintanaTheme.red) : KintanaTheme.t2;
        final isBull = t.direction == 'long';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: KintanaTheme.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: KintanaTheme.b1),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  NeonBadge(
                    label: t.direction.toUpperCase(),
                    color: isBull ? KintanaTheme.green : KintanaTheme.red,
                  ),
                  const SizedBox(width: 6),
                  Text(t.symbol, style: KintanaTheme.mono(size: 11, weight: FontWeight.bold)),
                  if (t.status == 'pending')
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: KintanaTheme.yellow.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: KintanaTheme.yellow.withOpacity(0.3)),
                      ),
                      child: Text('⏳ PENDING', style: KintanaTheme.mono(size: 8, color: KintanaTheme.yellow)),
                    ),
                  const Spacer(),
                  Text(
                    '${t.date.day}/${t.date.month}/${t.date.year}',
                    style: KintanaTheme.mono(size: 8, color: KintanaTheme.t3),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _tradeStatBox('ENTRY', fp(t.entry)),
                  _tradeStatBox('STAKE', '\$${t.stake.toInt()}'),
                  _tradeStatBox('P&L', pnlStr, color: pnlColor),
                  if (t.sl != null) _tradeStatBox('SL${t.slTrailed ? '⚡' : ''}', fp(t.sl), color: KintanaTheme.red),
                  if (t.tp1 != null) _tradeStatBox('TP1', fp(t.tp1), color: KintanaTheme.green),
                ],
              ),
              if (t.note != null && t.note!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: KintanaTheme.bg2,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text('📝 ${t.note}', style: KintanaTheme.sans(size: 9, color: KintanaTheme.t2)),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () {
                    s.removeTrade(t.id);
                    HapticFeedback.lightImpact();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: KintanaTheme.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: KintanaTheme.red.withOpacity(0.3)),
                    ),
                    child: Text('🗑 Clear', style: KintanaTheme.mono(size: 9, color: KintanaTheme.red)),
                  ),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 250.ms);
      },
    );
  }

  Widget _tradeStatBox(String label, String? value, {Color? color}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: KintanaTheme.bg2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(label, style: KintanaTheme.mono(size: 7, color: KintanaTheme.t3)),
            const SizedBox(height: 2),
            Text(value ?? '—', style: KintanaTheme.mono(size: 11, color: color ?? KintanaTheme.t1, weight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    const events = [
      {'time': 'MON 08:30', 'event': 'US Non-Farm Payrolls', 'impact': 'High'},
      {'time': 'MON 14:00', 'event': 'Fed Chair Speech', 'impact': 'High'},
      {'time': 'TUE 10:00', 'event': 'EUR CPI Data', 'impact': 'Medium'},
      {'time': 'TUE 15:30', 'event': 'US Retail Sales', 'impact': 'Medium'},
      {'time': 'WED 08:30', 'event': 'UK GDP Monthly', 'impact': 'Medium'},
      {'time': 'WED 14:30', 'event': 'US CPI YoY', 'impact': 'High'},
      {'time': 'THU 12:45', 'event': 'ECB Rate Decision', 'impact': 'High'},
      {'time': 'THU 18:00', 'event': 'US Jobless Claims', 'impact': 'Low'},
      {'time': 'FRI 08:30', 'event': 'Canada Employment', 'impact': 'Medium'},
      {'time': 'FRI 14:00', 'event': 'Michigan Consumer Sentiment', 'impact': 'Low'},
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('📅 ECONOMIC CALENDAR', style: KintanaTheme.mono(size: 9, color: KintanaTheme.t2)),
        const SizedBox(height: 8),
        ...events.map((ev) {
          final impact = ev['impact']!;
          final impactColor = impact == 'High' ? KintanaTheme.red : impact == 'Medium' ? KintanaTheme.yellow : KintanaTheme.green;
          final parts = ev['time']!.split(' ');
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: KintanaTheme.card,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: KintanaTheme.b1),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(parts[0], style: KintanaTheme.mono(size: 8, color: KintanaTheme.t3)),
                    Text(parts[1], style: KintanaTheme.mono(size: 10, color: KintanaTheme.acc, weight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(ev['event']!, style: KintanaTheme.sans(size: 11, weight: FontWeight.w600)),
                ),
                NeonBadge(label: impact, color: impactColor, fontSize: 8),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _emptyState(String icon, String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: KintanaTheme.sans(size: 12, color: KintanaTheme.t3),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(MarketState s) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KintanaTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Clear All Trades?', style: KintanaTheme.sans(size: 14, weight: FontWeight.bold)),
        content: Text('This will delete all ${s.trades.length} trades.', style: KintanaTheme.sans(size: 12, color: KintanaTheme.t2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: KintanaTheme.mono(size: 11, color: KintanaTheme.t2)),
          ),
          TextButton(
            onPressed: () { s.clearAllTrades(); Navigator.pop(context); },
            child: Text('Clear All', style: KintanaTheme.mono(size: 11, color: KintanaTheme.red, weight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
