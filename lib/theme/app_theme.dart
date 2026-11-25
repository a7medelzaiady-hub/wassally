import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'brand.dart';

export 'app_tokens.dart';

/// ألوان وصلي بتتبع السمة المختارة (brand.dart). غيّر القيم من هناك.
Color get kPrimary => Brand.green;
Color get kPrimaryDark => Brand.greenDark;
Color get kPrimarySoft => Brand.palette.soft;
Color get kAccent => Brand.gold;
Color get kBg => Brand.bg;
Color get kInk => Brand.ink;
Color get kMuted => Brand.palette.muted;
Color get kLine => Brand.palette.line;
const Color kSuccess = AppColors.success;
const Color kDanger = AppColors.danger;

TextTheme _textTheme(TextTheme base) {
  TextStyle? s(TextStyle? style, double size, FontWeight weight,
          [double height = 1.35]) =>
      style?.copyWith(fontSize: size, fontWeight: weight, height: height);
  return base.copyWith(
    displaySmall: s(base.displaySmall, AppTypography.display, FontWeight.w900, 1.2),
    headlineMedium: s(base.headlineMedium, AppTypography.headline, FontWeight.w900, 1.25),
    headlineSmall: s(base.headlineSmall, 20, FontWeight.w800, 1.25),
    titleLarge: s(base.titleLarge, AppTypography.title, FontWeight.w800, 1.3),
    titleMedium: s(base.titleMedium, AppTypography.titleSmall - 1, FontWeight.w700, 1.3),
    titleSmall: s(base.titleSmall, AppTypography.body, FontWeight.w700, 1.3),
    bodyLarge: s(base.bodyLarge, 16, FontWeight.w500, 1.45),
    bodyMedium: s(base.bodyMedium, AppTypography.body, FontWeight.w500, 1.45),
    bodySmall: s(base.bodySmall, AppTypography.label, FontWeight.w500, 1.4),
    labelLarge: s(base.labelLarge, AppTypography.body, FontWeight.w800, 1.2),
    labelMedium: s(base.labelMedium, AppTypography.label, FontWeight.w700, 1.2),
    labelSmall: s(base.labelSmall, AppTypography.caption, FontWeight.w700, 1.2),
  );
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.purple,
    brightness: Brightness.light,
  ).copyWith(
    primary: kPrimary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.orangeSoft,
    onPrimaryContainer: AppColors.orangeDeep,
    secondary: AppColors.purple,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.purpleSoft,
    onSecondaryContainer: AppColors.purple,
    tertiary: AppColors.purpleDeep,
    surface: Colors.white,
    onSurface: kInk,
    onSurfaceVariant: kMuted,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: kBg,
    surfaceContainerHigh: AppColors.surfaceAlt,
    surfaceContainerHighest: AppColors.surfaceAlt,
    outline: AppColors.muted,
    outlineVariant: kLine,
    error: kDanger,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Tajawal',
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
  final text = _textTheme(base.textTheme).apply(
    fontFamily: 'Tajawal',
    bodyColor: kInk,
    displayColor: kInk,
  );

  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: AppRadius.input,
        borderSide: BorderSide(color: color, width: width),
      );

  final buttonShape =
      RoundedRectangleBorder(borderRadius: AppRadius.button);

  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    textTheme: text,
    iconTheme: const IconThemeData(color: AppColors.inkSoft, size: 24),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: kInk.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: kLine),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      contentTextStyle: text.bodyMedium,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: kPrimary),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.purpleDeep,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white, size: 24),
      actionsIconTheme: const IconThemeData(color: Colors.white, size: 24),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      toolbarHeight: 60,
      titleTextStyle: text.titleLarge?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w800,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.line,
        disabledForegroundColor: AppColors.muted,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        shape: buttonShape,
        textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.purple,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        elevation: 0,
        shape: buttonShape,
        textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.purple,
        minimumSize: const Size(64, 52),
        side: const BorderSide(color: AppColors.line, width: 1.5),
        shape: buttonShape,
        textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.purple,
        minimumSize: const Size(48, 44),
        textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: AppColors.purpleSoft,
      checkmarkColor: AppColors.purple,
      side: const BorderSide(color: AppColors.line),
      shape: const StadiumBorder(),
      labelStyle: text.labelLarge?.copyWith(
        fontSize: AppTypography.bodySmall,
        fontWeight: FontWeight.w700,
        color: AppColors.inkSoft,
      ),
      secondaryLabelStyle: text.labelLarge?.copyWith(
        fontSize: AppTypography.bodySmall,
        fontWeight: FontWeight.w800,
        color: AppColors.purple,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      // Labels float above the border instead of colliding with it.
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      alignLabelWithHint: true,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
      border: border(kLine),
      enabledBorder: border(kLine),
      focusedBorder: border(AppColors.purple, 1.6),
      errorBorder: border(kDanger),
      focusedErrorBorder: border(kDanger, 1.6),
      disabledBorder: border(kLine),
      prefixIconColor: AppColors.muted,
      suffixIconColor: AppColors.muted,
      hintStyle: text.bodyMedium?.copyWith(color: kMuted),
      labelStyle: text.bodyMedium?.copyWith(color: kMuted),
      floatingLabelStyle: text.bodyMedium?.copyWith(
        color: AppColors.purple,
        fontWeight: FontWeight.w700,
      ),
      helperStyle: text.bodySmall?.copyWith(color: kMuted),
      errorStyle: text.bodySmall?.copyWith(color: kDanger),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.purple : null,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.purple,
      titleTextStyle: text.titleSmall?.copyWith(color: kInk),
      subtitleTextStyle: text.bodySmall?.copyWith(color: kMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      minVerticalPadding: AppSpacing.sm,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.purple,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.orange,
      labelStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      unselectedLabelStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.purpleSoft,
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return text.labelMedium!.copyWith(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? AppColors.purple : kMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? AppColors.purple : kMuted);
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.purpleDarker,
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      actionTextColor: AppColors.orangeLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.orange,
      foregroundColor: Colors.white,
    ),
    dividerTheme: DividerThemeData(color: kLine, space: 1, thickness: 1),
    dividerColor: kLine,
  );
}
