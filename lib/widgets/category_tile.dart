import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

class CategoryInfo {
  /// لازم تطابق قيمة category في مستند المحل.
  final String category;
  final String title;
  final String description;
  final IconData icon;
  final Color tint;
  final Color accent;

  const CategoryInfo({
    required this.category,
    required this.title,
    required this.description,
    required this.icon,
    required this.tint,
    required this.accent,
  });
}

const List<CategoryInfo> kCategories = [
  CategoryInfo(
    category: 'مطاعم',
    title: 'اطلب الطعام',
    description: 'توصيل سريع وعروض حصرية من مطاعمنا.',
    icon: Icons.lunch_dining,
    tint: Color(0xFFFFD9C2),
    accent: Color(0xFFC2410C),
  ),
  CategoryInfo(
    category: 'سوبرماركت',
    title: 'اطلب البقالة',
    description: 'كل اللي محتاجه من أفضل متاجر البقالة لحد باب بيتك.',
    icon: Icons.shopping_basket,
    tint: Color(0xFFDCEBC9),
    accent: Color(0xFF3F7D20),
  ),
  CategoryInfo(
    category: 'ورد',
    title: 'اطلب الورد',
    description: 'ورد طازج لأحبابك لحد باب بيتهم.',
    icon: Icons.local_florist,
    tint: Color(0xFFFBD3DD),
    accent: Color(0xFFB4234F),
  ),
];

/// زر "الكل" (بيشيل الفلتر).
CategoryInfo get kAllCategory => CategoryInfo(
  category: 'الكل',
  title: 'كل المحلات',
  description: '',
  icon: Icons.apps_rounded,
  tint: kPrimarySoft,
  accent: kPrimary,
);

/// قسم صغير: دايرة أيقونة ملوّنة واسم تحتها.
class CategoryTile extends StatelessWidget {
  final CategoryInfo info;
  final bool selected;
  final VoidCallback onTap;

  const CategoryTile({
    super.key,
    required this.info,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: info.title,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: info.tint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? info.accent : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: Icon(info.icon, color: info.accent, size: 28),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  info.category,
                  style: text.labelLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: selected ? kInk : kMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
