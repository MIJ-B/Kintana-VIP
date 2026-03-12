import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'services/market_state.dart';
import 'screens/chart_screen.dart';
import 'screens/joro_screen.dart';
import 'screens/journal_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/kintana_theme.dart';
import 'models/models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: KintanaTheme.bg2,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(
    ChangeNotifierProvider(
      create: (_) => MarketState(),
      child: const KintanaApp(),
    ),
  );
}

class KintanaApp extends StatelessWidget {
  const KintanaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KINTANA',
      debugShowCheckedModeBanner: false,
      theme: KintanaTheme.theme,
      home: const KintanaHome(),
    );
  }
}

class KintanaHome extends StatefulWidget {
  const KintanaHome({super.key});
  @override
  State<KintanaHome> createState() => _KintanaHomeState();
}

class _KintanaHomeState extends State<KintanaHome> with TickerProviderStateMixin {
  int _tab = 0;
  late AnimationController _liveDotCtrl;
  int _joroNotifCount = 0;
  final _pageCtrl = PageController();

  @override
  void initState() {
    super.initState();
    _liveDotCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _liveDotCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goTab(int i) {
    setState(() {
      _tab = i;
      if (i == 1) _joroNotifCount = 0;
    });
    _pageCtrl.jumpToPage(i);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<MarketState>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: KintanaTheme.bg,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(s),
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  children: const [
                    ChartScreen(),
                    JoroScreen(),
                    JournalScreen(),
                    SettingsScreen(),
                  ],
                ),
              ),
              _buildBottomNav(s),
            ],
          ),
        ),
      ),
    );
  }

  // ── Topbar
  Widget _buildTopBar(MarketState s) {
    final up = s.prevPrice == null || (s.price ?? 0) >= (s.prevPrice ?? 0);
    final priceColor = up ? KintanaTheme.green : KintanaTheme.red;
    final changeStr = s.open0 != null && s.price != null
        ? '${((s.price! - s.open0!) / s.open0! * 100) >= 0 ? '+' : ''}${((s.price! - s.open0!) / s.open0! * 100).toStringAsFixed(2)}%'
        : '+0.00%';
    final changeNeg = s.open0 != null && s.price != null && s.price! < s.open0!;

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xF7070A18),
        border: Border(bottom: BorderSide(color: KintanaTheme.b1)),
      ),
      child: Row(
        children: [
          // Brand
          Row(
            children: [
              Text('⭐', style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 5),
              Text(
                'KINTANA',
                style: KintanaTheme.mono(
                  size: 13,
                  color: KintanaTheme.acc,
                  weight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ).animate().fadeIn(duration: 600.ms),

          const SizedBox(width: 10),

          // Symbol badge
          GestureDetector(
            onTap: () => _goTab(3),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: KintanaTheme.card2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KintanaTheme.b2),
              ),
              child: Row(
                children: [
                  // Live dot
                  AnimatedBuilder(
                    animation: _liveDotCtrl,
                    builder: (_, __) => Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: s.isReplay ? KintanaTheme.purple : KintanaTheme.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (s.isReplay ? KintanaTheme.purple : KintanaTheme.green)
                                .withOpacity(0.3 + 0.3 * _liveDotCtrl.value),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(s.sym, style: KintanaTheme.mono(size: 11, weight: FontWeight.bold)),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Price
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: KintanaTheme.mono(size: 15, color: priceColor, weight: FontWeight.bold),
                child: Text(fp(s.price)),
              ),
              Text(
                changeStr,
                style: KintanaTheme.mono(
                  size: 10,
                  color: changeNeg ? KintanaTheme.red : KintanaTheme.green,
                ),
              ),
            ],
          ),

          const SizedBox(width: 8),

          // WS status
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: KintanaTheme.card2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: KintanaTheme.b2),
            ),
            child: Center(
              child: Icon(
                s.wsOk ? Icons.wifi : Icons.wifi_off,
                color: s.wsOk ? KintanaTheme.green : KintanaTheme.red,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom nav
  Widget _buildBottomNav(MarketState s) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: KintanaTheme.bg2,
        border: const Border(top: BorderSide(color: KintanaTheme.b1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: Stack(
        children: [
          // Active indicator
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            left: _tab * (MediaQuery.of(context).size.width / 4),
            top: 0,
            child: Container(
              width: MediaQuery.of(context).size.width / 4,
              height: 2,
              decoration: BoxDecoration(
                gradient: KintanaTheme.accGrad,
                boxShadow: KintanaTheme.glowAcc,
              ),
            ),
          ),
          Row(
            children: [
              _navItem(0, _chartIcon, 'Chart'),
              _navItemJoro(1),
              _navItem(2, Icons.book_outlined, 'Journal'),
              _navItem(3, Icons.settings_outlined, 'Settings'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navItem(int idx, IconData icon, String label) {
    final active = _tab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () { _goTab(idx); HapticFeedback.selectionClick(); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: active ? KintanaTheme.acc : KintanaTheme.t3,
                size: active ? 22 : 20,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: KintanaTheme.mono(
                  size: 9,
                  color: active ? KintanaTheme.acc : KintanaTheme.t3,
                  weight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItemJoro(int idx) {
    final active = _tab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () { _goTab(idx); HapticFeedback.selectionClick(); },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: active ? KintanaTheme.acc : KintanaTheme.b2,
                      width: active ? 1.5 : 1,
                    ),
                    boxShadow: active ? KintanaTheme.glowAcc : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.network(
                      'https://i.ibb.co/jvXcY5xS/Chat-GPT-Image-Mar-8-2026-10-07-09-AM.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text('🤖', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                ),
                if (_joroNotifCount > 0)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: KintanaTheme.red,
                        shape: BoxShape.circle,
                        boxShadow: KintanaTheme.glowRed,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              'JORO',
              style: KintanaTheme.mono(
                size: 9,
                color: active ? KintanaTheme.acc : KintanaTheme.t3,
                weight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData get _chartIcon => Icons.candlestick_chart_outlined;
}
