import 'package:flutter/material.dart';

import 'brand.dart';

/// ألوان وصلي بتتبع السمة المختارة (brand.dart). غيّر القيم من هناك.
Color get kPrimary => Brand.green;
Color get kPrimaryDark => Brand.greenDark;
Color get kPrimarySoft => Brand.palette.soft;
Color get kAccent => Brand.gold;
Color get kBg => Brand.bg;
Color get kInk => Brand.ink;
Color get kMuted => Brand.palette.muted;
Color get kLine => Brand.palette.line;
const Color kSuccess = Color(0xFF1F9D63);
const Color kDanger = Color(0xFFD92D20);

ThemeData buildAppTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: kPrimary,
        brightness: Brightness.light,
      ).copyWith(
        primary: kPrimary,
        onPrimary: Colors.white,
        secondary: kAccent,
        onSecondary: kAccent.computeLuminance() > 0.179 ? Colors.black : Colors.white,
        surface: Colors.white,
        onSurface: kInk,
        onSurfaceVariant: kMuted,
        surfaceContainerLow: Colors.white,
        surfaceContainer: kBg,
        surfaceContainerHigh: kPrimarySoft,
        outlineVariant: kLine,
        error: kDanger,
      );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Tajawal',
  );
  final text = base.textTheme.apply(
    fontFamily: 'Tajawal',
    bodyColor: kInk,
    displayColor: kInk,
  );

  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );

  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    textTheme: text,
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shadowColor: kInk.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kLine),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      contentTextStyle: text.bodyMedium,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: kPrimary),
    appBarTheme: AppBarTheme(
      backgroundColor: kInk,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        minimumSize: const Size(64, 52),
        side: BorderSide(color: kLine, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kPrimary,
        textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: border(kLine),
      enabledBorder: border(kLine),
      focusedBorder: border(kPrimary, 1.5),
      errorBorder: border(kDanger),
      focusedErrorBorder: border(kDanger, 1.5),
      hintStyle: text.bodyMedium?.copyWith(color: kMuted),
      labelStyle: text.bodyMedium?.copyWith(color: kMuted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: kPrimarySoft,
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return text.labelMedium!.copyWith(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? kPrimary : kMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? kPrimary : kMuted);
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kInk,
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerColor: kLine,
  );
}
