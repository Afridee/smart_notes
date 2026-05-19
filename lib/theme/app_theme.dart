import 'package:flutter/material.dart';

/// Exact semantic colors from `index.css` (:root and `.dark`).
abstract final class AppThemeColors {
  // Light (:root)
  static const Color lightBackground = Color(0xFFF9F9F9);
  static const Color lightForeground = Color(0xFF202020);
  static const Color lightCard = Color(0xFFFCFCFC);
  static const Color lightCardForeground = Color(0xFF202020);
  static const Color lightPopover = Color(0xFFFCFCFC);
  static const Color lightPopoverForeground = Color(0xFF202020);
  static const Color lightPrimary = Color(0xFF644A40);
  static const Color lightPrimaryForeground = Color(0xFFFFFFFF);
  static const Color lightSecondary = Color(0xFFFFDFB5);
  static const Color lightSecondaryForeground = Color(0xFF582D1D);
  static const Color lightMuted = Color(0xFFEFEFEF);
  static const Color lightMutedForeground = Color(0xFF646464);
  static const Color lightAccent = Color(0xFFE8E8E8);
  static const Color lightAccentForeground = Color(0xFF202020);
  static const Color lightDestructive = Color(0xFFE54D2E);
  static const Color lightDestructiveForeground = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFD8D8D8);
  static const Color lightInput = Color(0xFFD8D8D8);
  static const Color lightRing = Color(0xFF644A40);
  static const Color lightChart1 = Color(0xFF644A40);
  static const Color lightChart2 = Color(0xFFFFDFB5);
  static const Color lightChart3 = Color(0xFFE8E8E8);
  static const Color lightChart4 = Color(0xFFFFE6C4);
  static const Color lightChart5 = Color(0xFF66493E);
  static const Color lightSidebar = Color(0xFFFBFBFB);
  static const Color lightSidebarForeground = Color(0xFF252525);
  static const Color lightSidebarPrimary = Color(0xFF343434);
  static const Color lightSidebarPrimaryForeground = Color(0xFFFBFBFB);
  static const Color lightSidebarAccent = Color(0xFFF7F7F7);
  static const Color lightSidebarAccentForeground = Color(0xFF343434);
  static const Color lightSidebarBorder = Color(0xFFEBEBEB);
  static const Color lightSidebarRing = Color(0xFFB5B5B5);

  // Dark (.dark)
  static const Color darkBackground = Color(0xFF111111);
  static const Color darkForeground = Color(0xFFEEEEEE);
  static const Color darkCard = Color(0xFF191919);
  static const Color darkCardForeground = Color(0xFFEEEEEE);
  static const Color darkPopover = Color(0xFF191919);
  static const Color darkPopoverForeground = Color(0xFFEEEEEE);
  static const Color darkPrimary = Color(0xFFFFE0C2);
  static const Color darkPrimaryForeground = Color(0xFF081A1B);
  static const Color darkSecondary = Color(0xFF393028);
  static const Color darkSecondaryForeground = Color(0xFFFFE0C2);
  static const Color darkMuted = Color(0xFF222222);
  static const Color darkMutedForeground = Color(0xFFB4B4B4);
  static const Color darkAccent = Color(0xFF2A2A2A);
  static const Color darkAccentForeground = Color(0xFFEEEEEE);
  static const Color darkDestructive = Color(0xFFE54D2E);
  static const Color darkDestructiveForeground = Color(0xFFFFFFFF);
  static const Color darkBorder = Color(0xFF201E18);
  static const Color darkInput = Color(0xFF484848);
  static const Color darkRing = Color(0xFFFFE0C2);
  static const Color darkChart1 = Color(0xFFFFE0C2);
  static const Color darkChart2 = Color(0xFF393028);
  static const Color darkChart3 = Color(0xFF2A2A2A);
  static const Color darkChart4 = Color(0xFF42382E);
  static const Color darkChart5 = Color(0xFFFFE0C1);
  static const Color darkSidebar = Color(0xFF18181B);
  static const Color darkSidebarForeground = Color(0xFFF4F4F5);
  static const Color darkSidebarPrimary = Color(0xFF1D4ED8);
  static const Color darkSidebarPrimaryForeground = Color(0xFFFFFFFF);
  static const Color darkSidebarAccent = Color(0xFF27272A);
  static const Color darkSidebarAccentForeground = Color(0xFFF4F4F5);
  static const Color darkSidebarBorder = Color(0xFF27272A);
  static const Color darkSidebarRing = Color(0xFFD4D4D8);
}

abstract final class AppTheme {
  static const double radius = 8; // --radius: 0.5rem

  static ThemeData light() {
    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppThemeColors.lightPrimary,
      onPrimary: AppThemeColors.lightPrimaryForeground,
      primaryContainer: AppThemeColors.lightSecondary,
      onPrimaryContainer: AppThemeColors.lightSecondaryForeground,
      secondary: AppThemeColors.lightSecondary,
      onSecondary: AppThemeColors.lightSecondaryForeground,
      secondaryContainer: AppThemeColors.lightMuted,
      onSecondaryContainer: AppThemeColors.lightMutedForeground,
      tertiary: AppThemeColors.lightAccent,
      onTertiary: AppThemeColors.lightAccentForeground,
      error: AppThemeColors.lightDestructive,
      onError: AppThemeColors.lightDestructiveForeground,
      surface: AppThemeColors.lightBackground,
      onSurface: AppThemeColors.lightForeground,
      onSurfaceVariant: AppThemeColors.lightMutedForeground,
      outline: AppThemeColors.lightBorder,
      outlineVariant: AppThemeColors.lightInput,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppThemeColors.darkBackground,
      onInverseSurface: AppThemeColors.darkForeground,
      inversePrimary: AppThemeColors.darkPrimary,
      surfaceTint: AppThemeColors.lightPrimary,
      surfaceContainerLowest: AppThemeColors.lightBackground,
      surfaceContainerLow: AppThemeColors.lightCard,
      surfaceContainer: AppThemeColors.lightPopover,
      surfaceContainerHigh: AppThemeColors.lightMuted,
      surfaceContainerHighest: AppThemeColors.lightAccent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppThemeColors.lightBackground,
      cardTheme: CardThemeData(
        color: AppThemeColors.lightCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppThemeColors.lightBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppThemeColors.lightPopover,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      dividerTheme: const DividerThemeData(color: AppThemeColors.lightBorder),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppThemeColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppThemeColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppThemeColors.lightRing, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppThemeColors.lightForeground,
        contentTextStyle: const TextStyle(color: AppThemeColors.lightBackground),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppThemeColors.lightPrimary,
        foregroundColor: AppThemeColors.lightPrimaryForeground,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppThemeColors.darkPrimary,
      onPrimary: AppThemeColors.darkPrimaryForeground,
      primaryContainer: AppThemeColors.darkSecondary,
      onPrimaryContainer: AppThemeColors.darkSecondaryForeground,
      secondary: AppThemeColors.darkSecondary,
      onSecondary: AppThemeColors.darkSecondaryForeground,
      secondaryContainer: AppThemeColors.darkMuted,
      onSecondaryContainer: AppThemeColors.darkMutedForeground,
      tertiary: AppThemeColors.darkAccent,
      onTertiary: AppThemeColors.darkAccentForeground,
      error: AppThemeColors.darkDestructive,
      onError: AppThemeColors.darkDestructiveForeground,
      surface: AppThemeColors.darkBackground,
      onSurface: AppThemeColors.darkForeground,
      onSurfaceVariant: AppThemeColors.darkMutedForeground,
      outline: AppThemeColors.darkBorder,
      outlineVariant: AppThemeColors.darkInput,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppThemeColors.lightBackground,
      onInverseSurface: AppThemeColors.lightForeground,
      inversePrimary: AppThemeColors.lightPrimary,
      surfaceTint: AppThemeColors.darkPrimary,
      surfaceContainerLowest: AppThemeColors.darkBackground,
      surfaceContainerLow: AppThemeColors.darkCard,
      surfaceContainer: AppThemeColors.darkPopover,
      surfaceContainerHigh: AppThemeColors.darkMuted,
      surfaceContainerHighest: AppThemeColors.darkAccent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppThemeColors.darkBackground,
      cardTheme: CardThemeData(
        color: AppThemeColors.darkCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppThemeColors.darkBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppThemeColors.darkPopover,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      dividerTheme: const DividerThemeData(color: AppThemeColors.darkBorder),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppThemeColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppThemeColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppThemeColors.darkRing, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppThemeColors.darkForeground,
        contentTextStyle: const TextStyle(color: AppThemeColors.darkBackground),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppThemeColors.darkPrimary,
        foregroundColor: AppThemeColors.darkPrimaryForeground,
      ),
    );
  }
}
