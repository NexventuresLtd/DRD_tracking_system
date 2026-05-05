import 'package:flutter/material.dart';

class DRDTheme {
  static const Color primaryColor = Color(0xFF3B82F6);
  static const Color secondaryColor = Color(0xFF0A162E);
  static const Color accentColor = Color(0xFF8B5CF6);
  static const Color successColor = Color(0xFF22C55E);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color dangerColor = Color(0xFFEF4444);
  static const Color infoColor = Color(0xFF06B6D4);
  static const Color backgroundColor = Color(0xFF0A162E);
  static const Color surfaceColor = Color(0xFF1E293B);
  static const Color cardColor = Color(0xFF1E293B);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: accentColor,
        surface: Colors.white,
        error: dangerColor,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      fontFamily: 'Poppins',
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: const Color(0xFF60A5FA),
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF60A5FA),
        secondary: accentColor,
        surface: surfaceColor,
        error: dangerColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: Color(0xFF60A5FA),
        unselectedItemColor: Colors.grey,
      ),
      fontFamily: 'Poppins',
    );
  }

  static const Map<String, Color> teamColors = {
    'Team Alpha': Color(0xFF22C55E),
    'Team Bravo': Color(0xFFF59E0B),
    'Team Charlie': Color(0xFFEF4444),
    'Team Delta': Color(0xFF8B5CF6),
    'Team Echo': Color(0xFF06B6D4),
  };

  static const Map<String, Color> statusColors = {
    'active': Color(0xFF22C55E),
    'stale': Color(0xFFF59E0B),
    'offline': Color(0xFFEF4444),
  };

  static const Map<String, Color> flagColors = {
    'safe': Color(0xFF22C55E),
    'trouble': Color(0xFFF59E0B),
    'help': Color(0xFFEF4444),
  };
}