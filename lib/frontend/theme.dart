import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static const Color ink = Color(0xFF14213D);
  static const Color inkSoft = Color(0xFF526078);
  static const Color canvas = Color(0xFFFBF7F0);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceTint = Color(0xFFF1F6FC);
  static const Color cobalt = Color(0xFF0969E8);
  static const Color sky = Color(0xFF16A5F8);
  static const Color coral = Color(0xFFF72568);
  static const Color orange = Color(0xFFFF9F1C);
  static const Color teal = Color(0xFF13B8A6);
  static const Color violet = Color(0xFF7B3FE4);

  static const Color success = Color(0xFF159A73);
  static const Color warning = Color(0xFFE98713);
  static const Color error = Color(0xFFD9344A);
  static const Color info = cobalt;
  static const Color border = Color(0xFFE5E8EF);

  // Compatibility aliases used by older screens while the app is migrated.
  static const Color colorStudent = cobalt;
  static const Color colorStudentLight = Color(0xFFB8DCFF);
  static const Color colorAdmin = coral;
  static const Color colorAdminLight = Color(0xFFFFC2D3);
  static const Color colorParent = violet;
  static const Color colorParentLight = Color(0xFFDCCBFF);
  static const Color bgWhite = surface;
  static const Color bgOffWhite = canvas;
  static const Color bgGrayLight = surfaceTint;
  static const Color borderGray = border;
  static const Color borderGrayDark = Color(0xFFCDD3DE);
  static const Color textPrimary = ink;
  static const Color textSecondary = inkSoft;
  static const Color glassBg = Color(0xF2FFFFFF);
  static const Color glassBorder = border;
  static const Color glassBlurTint = Color(0x33FFFFFF);

  static const List<Color> primaryGradient = [cobalt, sky];
  static const List<Color> secondaryGradient = [teal, cobalt];
  static const List<Color> accentGradient = [coral, orange];

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: cobalt,
      brightness: Brightness.light,
      primary: cobalt,
      secondary: coral,
      surface: surface,
      error: error,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvas,
      fontFamily: 'Manrope',
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: ink,
          fontSize: 36,
          height: 1.05,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.4,
        ),
        headlineLarge: TextStyle(
          color: ink,
          fontSize: 30,
          height: 1.1,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
        headlineMedium: TextStyle(
          color: ink,
          fontSize: 24,
          height: 1.15,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        titleLarge: TextStyle(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        titleMedium: TextStyle(
          color: ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: ink, fontSize: 16, height: 1.5),
        bodyMedium: TextStyle(color: inkSoft, fontSize: 14, height: 1.45),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: Color(0xFF8993A6)),
        labelStyle: const TextStyle(color: inkSoft),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: cobalt, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: error),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cobalt,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(64, 54),
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: Color(0xFFDCEBFF),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: cobalt),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static Color categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'sports':
        return orange;
      case 'leadership':
        return violet;
      case 'career':
        return coral;
      case 'volunteer':
        return teal;
      default:
        return cobalt;
    }
  }
}
