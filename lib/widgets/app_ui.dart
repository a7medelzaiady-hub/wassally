import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// مكونات واجهة مشتركة مبنية على نظام التصميم (AppCards / AppHeaders /
/// رسائل الحالة). استخدمها بدل كروت وألوان مكتوبة يدويًا في كل صفحة.

/// كارت أبيض بحواف وحدود وظل موحدين.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.only(bottom: AppSpacing.sm),
    this.onTap,
    this.elevated = false,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final bool elevated;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.xl);
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: elevated ? AppShadows.card : null,
        ),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: borderColor ?? AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// عنوان قسم داخل كارت: أيقونة أو رقم خطوة في مربع بنفسجي فاتح + العنوان.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.step,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final int? step;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.purpleSoft,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: step != null
              ? Text(
                  '$step',
                  style: const TextStyle(
                    color: AppColors.purple,
                    fontWeight: FontWeight.w900,
                    fontSize: AppTypography.titleSmall,
                  ),
                )
              : Icon(icon ?? Icons.circle_outlined, color: AppColors.purple, size: 21),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(title, style: AppTypography.sectionTitle)),
        ?trailing,
      ],
    );
  }
}

enum AppNoticeType { info, action, success, error }

/// رسالة حالة موحدة (نجاح / خطأ / مطلوب منك / معلومة).
class AppNotice extends StatelessWidget {
  const AppNotice(this.text, {super.key, this.type = AppNoticeType.info});

  final String text;
  final AppNoticeType type;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (type) {
      AppNoticeType.info => (AppColors.purpleSoft, AppColors.purple, Icons.info_outline_rounded),
      AppNoticeType.action => (AppColors.orangeSoft, AppColors.orangeDeep, Icons.touch_app_outlined),
      AppNoticeType.success => (AppColors.successSoft, AppColors.success, Icons.check_circle_outline_rounded),
      AppNoticeType.error => (AppColors.dangerSoft, AppColors.danger, Icons.error_outline_rounded),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: type == AppNoticeType.error ? fg : AppColors.inkSoft,
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
