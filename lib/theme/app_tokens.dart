import 'package:flutter/material.dart';

/// نظام تصميم وصّلي الموحد: البنفسجي الملكي للهوية، البرتقالي للإجراءات
/// والأسعار والعروض، والأبيض للخلفيات والكروت.
///
/// أي صفحة جديدة أو معدلة تاخد ألوانها ومقاساتها من هنا بدل قيم عشوائية.
class AppColors {
  AppColors._();

  // ── البنفسجي الملكي: الهيدر، التنقل النشط، العناوين البارزة.
  // نفس درجة البنفسجي المعتمدة من مرجع «طلبات» (#8318D8).
  static const purple = Color(0xFF7A14CC);
  static const purpleDeep = Color(0xFF8318D8);
  static const purpleDarker = Color(0xFF4A0C80);
  static const purpleSoft = Color(0xFFEFEAFD);

  // ── البرتقالي: أزرار الإجراءات، الأسعار، العروض، التمييز.
  static const orange = Color(0xFFF26B00);
  static const orangeLight = Color(0xFFFF9133);

  /// للنصوص البرتقالية (الأسعار) على الأبيض: تباين مريح للقراءة.
  static const orangeDeep = Color(0xFFC24A00);
  static const orangeSoft = Color(0xFFFFEEDF);

  // ── الأبيض والمحايد.
  static const white = Colors.white;
  static const bg = Color(0xFFF6F5FA);
  static const surfaceAlt = Color(0xFFF1EFF7);
  static const ink = Color(0xFF1E1638);
  static const inkSoft = Color(0xFF3D3556);
  static const muted = Color(0xFF6B6480);
  static const line = Color(0xFFE5E1EF);

  // ── الحالات.
  static const success = Color(0xFF1F9D63);
  static const successSoft = Color(0xFFE5F6EE);
  static const warning = Color(0xFFB7791F);
  static const warningSoft = Color(0xFFFFF4DB);
  static const danger = Color(0xFFD92D20);
  static const dangerSoft = Color(0xFFFDECEA);

  static const headerGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFF8C22E0), Color(0xFF6E10BE)],
  );

  static const actionGradient = LinearGradient(
    colors: [orangeLight, orange],
  );
}

/// المسافات: مضاعفات 4 فقط.
class AppSpacing {
  AppSpacing._();
  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// الهامش الجانبي القياسي لكل الصفحات.
  static const double page = 16;
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(page, md, page, xxl);
}

class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;

  static final card = BorderRadius.circular(lg);
  static final input = BorderRadius.circular(md);
  static final button = BorderRadius.circular(md);
}

/// تدرج الخطوط. أصغر حجم مسموح 12 حتى تفضل النصوص مقروءة.
class AppTypography {
  AppTypography._();
  static const double display = 26;
  static const double headline = 22;
  static const double title = 19;
  static const double titleSmall = 17;
  static const double body = 15;
  static const double bodySmall = 14;
  static const double label = 13;
  static const double caption = 12;
  static const double price = 17;

  /// الحد الأدنى لأي نص في الواجهة.
  static const double minimum = caption;

  static const pageTitle = TextStyle(
    fontSize: title,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    height: 1.25,
  );
  static const sectionTitle = TextStyle(
    fontSize: titleSmall,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    height: 1.3,
  );
  static const bodyText = TextStyle(
    fontSize: body,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
    height: 1.45,
  );
  static const secondary = TextStyle(
    fontSize: bodySmall,
    fontWeight: FontWeight.w500,
    color: AppColors.muted,
    height: 1.4,
  );
  static const priceText = TextStyle(
    fontSize: price,
    fontWeight: FontWeight.w900,
    color: AppColors.orangeDeep,
    height: 1.2,
  );

  /// حجم الخط ثابت ومتناسق زي التطبيقات المشهورة: بيصغر شوية مع إعداد
  /// خط صغير في الهاتف، ومش بيكبر عن المقاسات المعتمدة فوق (التكبير
  /// الكبير كان بيضخم الكروت والنصوص).
  static const double minTextScale = 0.9;
  static const double maxTextScale = 1.0;
}

class AppShadows {
  AppShadows._();
  static const card = [
    BoxShadow(color: Color(0x141E1638), blurRadius: 14, offset: Offset(0, 5)),
  ];
  static const floating = [
    BoxShadow(color: Color(0x241E1638), blurRadius: 18, offset: Offset(0, 6)),
  ];
}

/// أقل مساحة ضغط مريحة لأي زر أو أيقونة.
const double kMinTapTarget = 48;
