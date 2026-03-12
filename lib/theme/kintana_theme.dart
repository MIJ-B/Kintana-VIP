import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class KintanaTheme {
  // ── Colors
  static const bg      = Color(0xFF03050E);
  static const bg2     = Color(0xFF070A18);
  static const card    = Color(0xFF0D1020);
  static const card2   = Color(0xFF111525);
  static const b1      = Color(0xFF161D32);
  static const b2      = Color(0xFF1C2540);

  static const acc     = Color(0xFF00D4FF);
  static const green   = Color(0xFF00E676);
  static const red     = Color(0xFFFF3D57);
  static const yellow  = Color(0xFFFFD740);
  static const purple  = Color(0xFF9B72E6);
  static const purpleL = Color(0xFFC4AAFF);

  static const t1      = Color(0xFFE8EDF8);
  static const t2      = Color(0xFF7A87A8);
  static const t3      = Color(0xFF3D4A6B);

  // ── Gradients
  static const LinearGradient bgGrad = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bg, Color(0xFF050812)],
  );

  static const LinearGradient accGrad = LinearGradient(
    colors: [acc, purple],
  );

  static const LinearGradient buyGrad = LinearGradient(
    colors: [Color(0xE600E676), Color(0xE600C864)],
  );

  static const LinearGradient sellGrad = LinearGradient(
    colors: [Color(0xE6FF3D57), Color(0xE6DC1E3C)],
  );

  // ── Shadows / Glows
  static List<BoxShadow> glowAcc = [
    BoxShadow(color: acc.withOpacity(0.4), blurRadius: 16, spreadRadius: 0),
  ];
  static List<BoxShadow> glowGreen = [
    BoxShadow(color: green.withOpacity(0.4), blurRadius: 16, spreadRadius: 0),
  ];
  static List<BoxShadow> glowRed = [
    BoxShadow(color: red.withOpacity(0.4), blurRadius: 16, spreadRadius: 0),
  ];

  // ── Text Styles
  static TextStyle mono({
    double size = 12,
    Color color = t1,
    FontWeight weight = FontWeight.normal,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'SpaceMono',
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle sans({
    double size = 14,
    Color color = t1,
    FontWeight weight = FontWeight.normal,
    double? letterSpacing,
  }) {
    return GoogleFonts.syne(
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing,
    );
  }

  // ── MaterialTheme
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: acc,
      secondary: purple,
      surface: card,
      error: red,
    ),
    textTheme: GoogleFonts.syneTextTheme(
      ThemeData.dark().textTheme,
    ).apply(bodyColor: t1, displayColor: t1),
    appBarTheme: const AppBarTheme(
      backgroundColor: bg2,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: bg2,
      selectedItemColor: acc,
      unselectedItemColor: t3,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    dividerColor: b1,
    cardColor: card,
  );
}

// ── Reusable styled containers
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color borderColor;
  final double radius;
  final List<BoxShadow>? shadow;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor = KintanaTheme.b1,
    this.radius = 12,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KintanaTheme.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: shadow,
      ),
      padding: padding,
      child: child,
    );
  }
}

class NeonBadge extends StatelessWidget {
  final String label;
  final Color color;
  final double fontSize;

  const NeonBadge({
    super.key,
    required this.label,
    required this.color,
    this.fontSize = 9,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        label,
        style: KintanaTheme.mono(
          size: fontSize,
          color: color,
          weight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
