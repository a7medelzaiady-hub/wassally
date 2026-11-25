import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// نوع الرسالة: بيحدد الأيقونة ولون الشريط الجانبي.
enum AppSnackKind { success, error, info }

/// بيخمّن نوع الرسالة من كلامها لو ما اتحددش.
AppSnackKind guessSnackKind(String message) {
  final m = message.trim();
  if (RegExp(r'تعذر|فشل|خطأ|غلط|مرفوض|غير صالح|مش متاح|ممنوع|لا يمكن|مغلق|انتهت|الحد الأقصى|محتاج|لازم|اكتب|اختار|اسمح|فعّل|استنى|راجع|سجل دخولك').hasMatch(m)) {
    return m.startsWith('تم') ? AppSnackKind.success : AppSnackKind.error;
  }
  if (RegExp(r'^(تم|اتـ?حفظ|اتبعت|اتضاف|اتمسح|اتلغى|اتحدث)|بنجاح|✓').hasMatch(m)) {
    return AppSnackKind.success;
  }
  return AppSnackKind.info;
}

/// رسالة بإطار موحّد واحترافي: كارت بنفسجي غامق، أيقونة في دايرة،
/// عنوان اختياري، وزر قفل. نفس الشكل في التطبيق كله.
SnackBar appSnack(
  String message, {
  String? title,
  AppSnackKind? kind,
  Duration duration = const Duration(seconds: 4),
  SnackBarAction? action,
  bool showClose = false,
}) {
  final k = kind ?? guessSnackKind(title ?? message);
  final (icon, accent) = switch (k) {
    AppSnackKind.success => (Icons.check_rounded, const Color(0xFF34D399)),
    AppSnackKind.error => (Icons.priority_high_rounded, const Color(0xFFFF8A65)),
    AppSnackKind.info => (Icons.info_outline_rounded, AppColors.orangeLight),
  };
  return SnackBar(
    duration: duration,
    action: action,
    showCloseIcon: showClose,
    content: Row(
      crossAxisAlignment: title == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 1.6),
          ),
          child: Icon(icon, color: accent, size: 18),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTypography.body,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
              ],
              Text(
                message,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: title == null ? 1 : 0.86),
                  fontSize: title == null ? AppTypography.bodySmall : AppTypography.label,
                  fontWeight: title == null ? FontWeight.w700 : FontWeight.w500,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
