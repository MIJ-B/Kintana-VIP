import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/market_state.dart';
import '../models/models.dart';
import '../theme/kintana_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _groqCtrl = TextEditingController();
  bool _keyVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = context.read<MarketState>();
      _groqCtrl.text = s.groqKey;
    });
  }

  @override
  void dispose() {
    _groqCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<MarketState>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildProfile(s),
          const SizedBox(height: 16),
          _buildAPISection(s),
          const SizedBox(height: 16),
          _buildJOROpredict(s),
          const SizedBox(height: 16),
          _buildMarketSection(s),
          const SizedBox(height: 16),
          _buildTrailingStop(s),
          const SizedBox(height: 20),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildProfile(MarketState s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [KintanaTheme.card, KintanaTheme.bg2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KintanaTheme.b1),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: KintanaTheme.acc.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: KintanaTheme.acc.withOpacity(0.5)),
              boxShadow: KintanaTheme.glowAcc,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('⭐', style: const TextStyle(fontSize: 18)),
                Text('VIP', style: KintanaTheme.mono(size: 7, color: KintanaTheme.acc, weight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VIP ⭐ KINTANA', style: KintanaTheme.sans(size: 15, weight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(
                  '${s.sym} • ${s.isReplay ? 'REPLAY MODE' : 'Deriv Live'}',
                  style: KintanaTheme.mono(size: 10, color: KintanaTheme.t2),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: KintanaTheme.purple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: KintanaTheme.purple.withOpacity(0.4)),
            ),
            child: Text('v4.0', style: KintanaTheme.mono(size: 11, color: KintanaTheme.purpleL, weight: FontWeight.bold)),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildAPISection(MarketState s) {
    return _section(
      title: 'API KEYS',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KintanaTheme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KintanaTheme.b1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('GROQ API KEY', style: KintanaTheme.mono(size: 9, color: KintanaTheme.t3, letterSpacing: 1)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: KintanaTheme.bg2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: KintanaTheme.b2),
                    ),
                    child: TextField(
                      controller: _groqCtrl,
                      obscureText: !_keyVisible,
                      style: KintanaTheme.mono(size: 11),
                      decoration: InputDecoration(
                        hintText: 'gsk_...',
                        hintStyle: KintanaTheme.mono(size: 11, color: KintanaTheme.t3),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: InputBorder.none,
                        suffixIcon: GestureDetector(
                          onTap: () => setState(() => _keyVisible = !_keyVisible),
                          child: Icon(_keyVisible ? Icons.visibility_off : Icons.visibility,
                              color: KintanaTheme.t3, size: 16),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    s.groqKey = _groqCtrl.text.trim();
                    s.saveSettings();
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ GROQ Key saved!'),
                        backgroundColor: KintanaTheme.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: KintanaTheme.acc.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: KintanaTheme.acc.withOpacity(0.5)),
                    ),
                    child: Text('SAVE', style: KintanaTheme.mono(size: 10, color: KintanaTheme.acc, weight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Get your free key at console.groq.com',
              style: KintanaTheme.mono(size: 9, color: KintanaTheme.t3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJOROpredict(MarketState s) {
    return _section(
      title: '⚡ JOROPREDICT v3',
      child: GlassCard(
        child: Column(
          children: [
            _settingsRow(
              icon: '🎯',
              iconColor: KintanaTheme.purple.withOpacity(0.15),
              title: 'Auto TP/SL',
              subtitle: s.jpAutoTPSL ? 'Active — auto TP/SL via ATR' : 'Inactive — tsy mametraka TP/SL',
              trailing: _toggle(s.jpAutoTPSL, () {
                s.jpAutoTPSL = !s.jpAutoTPSL;
                s.saveSettings();
                setState(() {});
              }),
            ),
            if (s.jpAutoTPSL) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 4, 13, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _numInput('TP (× ATR)', s.jpTPAtr, (v) { s.jpTPAtr = v; s.saveSettings(); })),
                        const SizedBox(width: 8),
                        Expanded(child: _numInput('SL (× ATR)', s.jpSLAtr, (v) { s.jpSLAtr = v; s.saveSettings(); })),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'TP = prix + (ATR × ratio)  •  SL = prix − (ATR × ratio)',
                      style: KintanaTheme.mono(size: 9, color: KintanaTheme.t3),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(color: KintanaTheme.b1, height: 1),
            _settingsRow(
              icon: '🔔',
              iconColor: KintanaTheme.yellow.withOpacity(0.15),
              title: 'Signal Alarm',
              subtitle: s.jpAlarm ? 'Active — notification + vibration' : 'Inactive — mangina',
              trailing: _toggle(s.jpAlarm, () {
                s.jpAlarm = !s.jpAlarm;
                s.saveSettings();
                setState(() {});
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketSection(MarketState s) {
    return _section(
      title: 'MARKET',
      child: GlassCard(
        child: Column(
          children: [
            _settingsRow(
              icon: '📈',
              iconColor: KintanaTheme.acc.withOpacity(0.1),
              title: 'Symbol',
              subtitle: '${s.sym} — ${s.sname}',
              trailing: const Icon(Icons.chevron_right, color: KintanaTheme.t3),
              onTap: () => _showSymbolModal(s),
            ),
            const Divider(color: KintanaTheme.b1, height: 1),
            _settingsRow(
              icon: '🌐',
              iconColor: KintanaTheme.yellow.withOpacity(0.1),
              title: 'Live Streaming',
              subtitle: s.wsOk ? 'Connected ● Live' : 'Reconnecting...',
              trailing: Icon(
                Icons.circle,
                color: s.wsOk ? KintanaTheme.green : KintanaTheme.red,
                size: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailingStop(MarketState s) {
    return _section(
      title: 'RISK MANAGEMENT',
      child: GlassCard(
        child: Column(
          children: [
            _settingsRow(
              icon: '⚡',
              iconColor: KintanaTheme.purple.withOpacity(0.15),
              title: 'Trailing Stop Auto',
              subtitle: s.trailingStop ? 'Active — auto SL adjustment' : 'Inactive — SL fixe',
              trailing: _toggle(s.trailingStop, () {
                s.trailingStop = !s.trailingStop;
                s.saveSettings();
                setState(() {});
              }),
            ),
            if (s.trailingStop)
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 4, 13, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TRAILING DISTANCE (% du prix)', style: KintanaTheme.mono(size: 9, color: KintanaTheme.t3, letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    _numInput('Distance %', s.trailingDist, (v) { s.trailingDist = v; s.saveSettings(); }),
                    const SizedBox(height: 6),
                    Text(
                      'Rehefa miakatra ny prix, ny SL dia manaraka automatiquement.',
                      style: KintanaTheme.mono(size: 9, color: KintanaTheme.t3),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text('VIP ⭐ KINTANA v4.0 • DERIV APP ID: 129691',
            style: KintanaTheme.mono(size: 9, color: KintanaTheme.t3)),
        const SizedBox(height: 4),
        Text('JORO AI + AMD + JOROpredict + Replay Advanced',
            style: KintanaTheme.mono(size: 8, color: KintanaTheme.t3)),
      ],
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(
            title,
            style: KintanaTheme.mono(size: 8, color: KintanaTheme.t3, letterSpacing: 2),
          ),
        ),
        child,
      ],
    );
  }

  Widget _settingsRow({
    required String icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: iconColor, borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text(icon, style: const TextStyle(fontSize: 14))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: KintanaTheme.sans(size: 12, weight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(subtitle, style: KintanaTheme.mono(size: 9, color: KintanaTheme.t3)),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _toggle(bool value, VoidCallback onTap) {
    return GestureDetector(
      onTap: () { onTap(); HapticFeedback.lightImpact(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 38,
        height: 21,
        decoration: BoxDecoration(
          color: value ? KintanaTheme.acc : KintanaTheme.b2,
          borderRadius: BorderRadius.circular(11),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 17,
            height: 17,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }

  Widget _numInput(String label, double value, ValueChanged<double> onChange) {
    final ctrl = TextEditingController(text: value.toString());
    return Container(
      decoration: BoxDecoration(
        color: KintanaTheme.bg2,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: KintanaTheme.b2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: Text(label, style: KintanaTheme.mono(size: 8, color: KintanaTheme.t3)),
          ),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: KintanaTheme.mono(size: 12),
            onSubmitted: (v) => onChange(double.tryParse(v) ?? value),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }

  void _showSymbolModal(MarketState s) {
    final searchCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KintanaTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModalState) {
          final query = searchCtrl.text.toLowerCase();
          final filtered = kMarkets.where((m) =>
              query.isEmpty ||
              m.symbol.toLowerCase().contains(query) ||
              m.name.toLowerCase().contains(query) ||
              m.category.toLowerCase().contains(query)).toList();

          // Group by category
          final categories = <String, List<Market>>{};
          for (final m in filtered) {
            categories.putIfAbsent(m.category, () => []).add(m);
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: KintanaTheme.b2, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                Text('📊 Select Market', style: KintanaTheme.sans(size: 15, weight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: KintanaTheme.bg2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: KintanaTheme.b2),
                  ),
                  child: TextField(
                    controller: searchCtrl,
                    style: KintanaTheme.sans(size: 12),
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search symbol, name...',
                      hintStyle: KintanaTheme.sans(size: 12, color: KintanaTheme.t3),
                      prefixIcon: const Icon(Icons.search, color: KintanaTheme.t3, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: categories.entries.map((entry) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6, top: 4),
                            child: Text(
                              entry.key.toUpperCase(),
                              style: KintanaTheme.mono(size: 8, color: KintanaTheme.t3, letterSpacing: 1.5),
                            ),
                          ),
                          ...entry.value.map((m) {
                            final active = m.symbol == s.sym;
                            return GestureDetector(
                              onTap: () {
                                s.changeSymbol(m);
                                Navigator.pop(ctx);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: active ? KintanaTheme.acc.withOpacity(0.1) : KintanaTheme.bg2,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: active ? KintanaTheme.acc.withOpacity(0.5) : KintanaTheme.b1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(m.flag, style: const TextStyle(fontSize: 16)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(m.symbol, style: KintanaTheme.mono(size: 11, weight: FontWeight.bold,
                                              color: active ? KintanaTheme.acc : KintanaTheme.t1)),
                                          Text(m.name, style: KintanaTheme.sans(size: 10, color: KintanaTheme.t2)),
                                        ],
                                      ),
                                    ),
                                    NeonBadge(label: m.type, color: KintanaTheme.acc.withOpacity(0.7), fontSize: 8),
                                    if (active) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.check_circle, color: KintanaTheme.acc, size: 16),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
