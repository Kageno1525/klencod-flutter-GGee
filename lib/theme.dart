import 'package:flutter/material.dart';

class AppTheme {
  // ═══════════════ Core Colors ═══════════════
  static const purple = Color(0xFF6C5CE7);
  static const blue = Color(0xFF00D2FF);
  static const teal = Color(0xFF00D68F);
  static const orange = Color(0xFFFFB84D);
  static const red = Color(0xFFFF6B6B);
  static const green = Color(0xFF00D68F);
  static const pink = Color(0xFFEC4899);

  // Dark backgrounds
  static const darkBg1 = Color(0xFF0B0B14);
  static const darkBg2 = Color(0xFF131324);
  static const darkBg3 = Color(0xFF1E1E33);
  static const darkSurface = Color(0xFF1C1C2E);

  // Light backgrounds
  static const lightBg1 = Color(0xFFF5F6FB);
  static const lightBg2 = Color(0xFFEEF0F8);
  static const lightSurface = Colors.white;

  // ═══════════════ Gradients ═══════════════
  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF6C5CE7), Color(0xFF00D2FF)],
  );
  static const secondaryGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFEC4899), Color(0xFFFF8E53)],
  );
  static const orangeGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFFFB84D), Color(0xFFFF8E53)],
  );
  static const cosmosGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF3F51B5), Color(0xFF6C5CE7)],
  );
  static const successGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF00B894), Color(0xFF00D68F)],
  );
  static const dangerGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
  );
  static const infoGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)],
  );

  // ═══════════════ Theme Data ═══════════════
  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        primary: purple,
        secondary: blue,
        tertiary: teal,
        surface: darkSurface,
        error: red,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: purple, width: 1.5),
        ),
        labelStyle: TextStyle(
          color: Colors.white.withOpacity(0.6),
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.35),
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2C2C3E),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(
            decoration: TextDecoration.none,
            decorationColor: Colors.transparent),
        bodyMedium: TextStyle(
            decoration: TextDecoration.none,
            decorationColor: Colors.transparent),
        bodySmall: TextStyle(
            decoration: TextDecoration.none,
            decorationColor: Colors.transparent),
      ),
    );
  }

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: const ColorScheme.light(
        primary: purple,
        secondary: blue,
        tertiary: teal,
        surface: lightSurface,
        error: red,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: Color(0xFF1A1A2E),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.9),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.black.withOpacity(0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: purple, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  // ═══════════════ Helpers ═══════════════
  static Color textColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white
          : const Color(0xFF1A1A2E);

  static Color subTextColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.55)
          : Colors.black.withOpacity(0.5);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Animated background with soft blobs + subtle gradient.
  static Widget background(BuildContext context) {
    final dark = isDark(context);
    return Container(
      constraints: const BoxConstraints.expand(),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [darkBg1, darkBg2, darkBg1]
              : [lightBg1, lightBg2, lightBg1],
        ),
      ),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BlobsPainter(
            c1: purple.withOpacity(dark ? 0.32 : 0.16),
            c2: blue.withOpacity(dark ? 0.24 : 0.12),
            c3: teal.withOpacity(dark ? 0.20 : 0.10),
          ),
        ),
      ),
    );
  }

  static Widget glassCard({
    required BuildContext context,
    required Widget child,
    EdgeInsets? padding,
    VoidCallback? onTap,
    Color? color,
    BorderRadius? borderRadius,
  }) {
    final dark = isDark(context);
    final radius = borderRadius ?? BorderRadius.circular(20);

    final inner = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ??
            (dark
                ? darkSurface.withOpacity(0.65)
                : Colors.white.withOpacity(0.9)),
        borderRadius: radius,
        border: Border.all(
          color: dark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.04),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.25 : 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return inner;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: inner,
      ),
    );
  }
}

class _BlobsPainter extends CustomPainter {
  final Color c1, c2, c3;
  _BlobsPainter({required this.c1, required this.c2, required this.c3});

  @override
  void paint(Canvas canvas, Size size) {
    _blob(canvas, Offset(size.width * 0.10, size.height * 0.15), 340, c1);
    _blob(canvas, Offset(size.width * 0.95, size.height * 0.35), 380, c2);
    _blob(canvas, Offset(size.width * 0.40, size.height * 0.95), 280, c3);
  }

  void _blob(Canvas canvas, Offset center, double radius, Color color) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withOpacity(0)],
        stops: const [0.0, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_BlobsPainter old) =>
      old.c1 != c1 || old.c2 != c2 || old.c3 != c3;
}