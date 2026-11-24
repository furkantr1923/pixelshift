import 'package:flutter/material.dart';

/// PIXELSHIFT koyu tema paleti (uygulamada yalnızca koyu tema vardır).
class PxColors {
  PxColors._();

  static const background = Color(0xFF0B0E16);
  static const surface = Color(0xFF111522);
  static const surface2 = Color(0xFF171C2C);
  static const surface3 = Color(0xFF1F2538);
  static const border = Color(0xFF272E44);
  static const primary = Color(0xFF7C5CFF);
  static const accent = Color(0xFF22D3EE);
  static const text = Color(0xFFE7E9F1);
  static const muted = Color(0xFF8A91A8);
  static const danger = Color(0xFFFF5C7A);
  static const success = Color(0xFF3DDC97);
  static const warning = Color(0xFFFFB547);
  static const canvas = Color(0xFF07090F);

  static const brandGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildPixelTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: PxColors.primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: PxColors.primary,
    secondary: PxColors.accent,
    surface: PxColors.surface,
    error: PxColors.danger,
    onSurface: PxColors.text,
    outline: PxColors.border,
    surfaceContainerHighest: PxColors.surface3,
    surfaceContainerHigh: PxColors.surface2,
    surfaceContainer: PxColors.surface2,
    surfaceContainerLow: PxColors.surface,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: PxColors.background,
    visualDensity: VisualDensity.standard,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: PxColors.surface,
      foregroundColor: PxColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w600, color: PxColors.text),
    ),
    dividerTheme: const DividerThemeData(color: PxColors.border, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: PxColors.surface2,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: PxColors.border)),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 3,
      activeTrackColor: PxColors.primary,
      inactiveTrackColor: PxColors.border,
      thumbColor: Colors.white,
      overlayColor: PxColors.primary.withOpacity(0.18),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      showValueIndicator: ShowValueIndicator.never,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PxColors.surface3,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: PxColors.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: PxColors.border)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: PxColors.primary)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PxColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PxColors.text,
        side: const BorderSide(color: PxColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: PxColors.surface3, borderRadius: BorderRadius.circular(6), border: Border.all(color: PxColors.border)),
      textStyle: const TextStyle(color: PxColors.text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: PxColors.surface3,
      contentTextStyle: const TextStyle(color: PxColors.text, fontFamily: 'Inter'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: PxColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: PxColors.border)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: PxColors.surface2, showDragHandle: true),
    menuTheme: const MenuThemeData(
      style: MenuStyle(backgroundColor: WidgetStatePropertyAll(PxColors.surface2)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: PxColors.surface3,
      selectedColor: PxColors.primary.withOpacity(0.25),
      side: const BorderSide(color: PxColors.border),
      labelStyle: const TextStyle(fontSize: 12.5, color: PxColors.text),
    ),
    scrollbarTheme: const ScrollbarThemeData(thickness: WidgetStatePropertyAll(6)),
  );
}
