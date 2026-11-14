import 'package:material_ui/material_ui.dart';

/// سمة ألوان كاملة. المستخدم بيختار واحدة من صفحة "حسابي".
class AppPalette {
  final String id;
  final String name;

  /// اللون الأساسي (الهيدر، الأزرار، العناصر المحدّدة).
  final Color primary;
  final Color primaryDark;
  final Color primaryLight;

  /// لون مكمّل (نجوم، شارات، تمييز).
  final Color accent;
  final Color accentDeep;

  final Color bg;
  final Color ink;
  final Color muted;
  final Color line;

  /// خلفية فاتحة بلون السمة (شارات، أيقونات).
  final Color soft;

  const AppPalette({
    required this.id,
    required this.name,
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.accent,
    required this.accentDeep,
    required this.bg,
    required this.ink,
    required this.muted,
    required this.line,
    required this.soft,
  });

  static const orange = AppPalette(
    id: 'orange',
    name: 'برتقالي',
    primary: Color(0xFFFF7A1A),
    primaryDark: Color(0xFFE5620A),
    primaryLight: Color(0xFFFF9A4D),
    accent: Color(0xFFFFB627),
    accentDeep: Color(0xFFD98600),
    bg: Color(0xFFFFFFFF),
    ink: Color(0xFF1B1D22),
    muted: Color(0xFF7B8089),
    line: Color(0xFFE9EBEF),
    soft: Color(0xFFFFEDDD),
  );

  static const green = AppPalette(
    id: 'green',
    name: 'أخضر',
    primary: Color(0xFF0B7A55),
    primaryDark: Color(0xFF064E3B),
    primaryLight: Color(0xFF14A36E),
    accent: Color(0xFFD4A537),
    accentDeep: Color(0xFFB8861B),
    bg: Color(0xFFFFFFFF),
    ink: Color(0xFF0B1F17),
    muted: Color(0xFF74857D),
    line: Color(0xFFE3ECE7),
    soft: Color(0xFFE3F3EB),
  );

  static const blue = AppPalette(
    id: 'blue',
    name: 'أزرق',
    primary: Color(0xFF2563EB),
    primaryDark: Color(0xFF1E40AF),
    primaryLight: Color(0xFF4F8BFF),
    accent: Color(0xFFF5A524),
    accentDeep: Color(0xFFD98A0B),
    bg: Color(0xFFFFFFFF),
    ink: Color(0xFF0F172A),
    muted: Color(0xFF6B7A90),
    line: Color(0xFFE2E8F2),
    soft: Color(0xFFE4ECFF),
  );

  static const purple = AppPalette(
    id: 'purple',
    name: 'بنفسجي',
    primary: Color(0xFF7C3AED),
    primaryDark: Color(0xFF5B21B6),
    primaryLight: Color(0xFF9F67FF),
    accent: Color(0xFFFFB020),
    accentDeep: Color(0xFFD98A0B),
    bg: Color(0xFFFFFFFF),
    ink: Color(0xFF1E1B2E),
    muted: Color(0xFF7A7690),
    line: Color(0xFFE9E5F4),
    soft: Color(0xFFEFE7FF),
  );

  static const rose = AppPalette(
    id: 'rose',
    name: 'وردي',
    primary: Color(0xFFE11D48),
    primaryDark: Color(0xFF9F1239),
    primaryLight: Color(0xFFFB4B6E),
    accent: Color(0xFFF5A524),
    accentDeep: Color(0xFFD98A0B),
    bg: Color(0xFFFFFFFF),
    ink: Color(0xFF2A1218),
    muted: Color(0xFF8A7479),
    line: Color(0xFFF1E4E7),
    soft: Color(0xFFFFE4EA),
  );

  static const all = <AppPalette>[orange, green, blue, purple, rose];

  static AppPalette byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return orange;
  }
}

/// ألوان البرنامج. القيم دلوقتي بتتبع السمة المختارة (AppPalette).
/// الأسماء القديمة اتساب زي ما هي: green = اللون الأساسي للسمة، gold = اللون المكمّل.
class Brand {
  Brand._();

  static AppPalette palette = AppPalette.orange;

  static Color get green => palette.primary;
  static Color get greenDark => palette.primaryDark;
  static Color get greenLight => palette.primaryLight;
  static Color get gold => palette.accent;
  static Color get goldDeep => palette.accentDeep;
  static Color get bg => palette.bg;
  static Color get ink => palette.ink;

  static LinearGradient get headerGradient => LinearGradient(
    colors: [
      palette.primary,
      Color.lerp(palette.primary, palette.primaryDark, 0.6)!,
    ],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static LinearGradient get softGradient => LinearGradient(
    colors: [palette.primary, palette.primaryLight],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );
}

/// لون خلفية المربعات (البيج الهادي) زي تطبيقات التوصيل الكبيرة.
const Color kTileBeige = Color(0xFFF4EEE6);
