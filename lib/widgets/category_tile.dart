import 'package:flutter/material.dart';

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
  CategoryInfo(category: 'مطاعم', title: 'مطاعم', description: 'مطاعم ووجبات جاهزة.', icon: Icons.lunch_dining, tint: Color(0xFFFFD9C2), accent: Color(0xFFC2410C)),
  CategoryInfo(category: 'سوبرماركت', title: 'سوبر ماركت', description: 'احتياجات البيت اليومية.', icon: Icons.shopping_basket, tint: Color(0xFFDCEBC9), accent: Color(0xFF3F7D20)),
  CategoryInfo(category: 'بقالة', title: 'بقالة', description: 'منتجات البقالة والاحتياجات السريعة.', icon: Icons.storefront, tint: Color(0xFFE4E9FF), accent: Color(0xFF4056A1)),
  CategoryInfo(category: 'خضار وفاكهة', title: 'خضار وفاكهة', description: 'خضار وفاكهة طازجة.', icon: Icons.eco, tint: Color(0xFFDDF3D9), accent: Color(0xFF287A38)),
  CategoryInfo(category: 'لحوم ودواجن', title: 'لحوم ودواجن', description: 'لحوم ودواجن طازجة.', icon: Icons.set_meal, tint: Color(0xFFFFE1D8), accent: Color(0xFFB64D32)),
  CategoryInfo(category: 'مخبوزات وحلويات', title: 'مخبوزات وحلويات', description: 'مخبوزات وحلويات متنوعة.', icon: Icons.bakery_dining, tint: Color(0xFFFFEBCB), accent: Color(0xFF9A5A16)),
  CategoryInfo(category: 'محمصات وعطارة', title: 'محمصات وعطارة', description: 'مكسرات وتوابل وأعشاب.', icon: Icons.grain, tint: Color(0xFFEFE2D2), accent: Color(0xFF80552E)),
  CategoryInfo(category: 'كافيه ومشروبات', title: 'كافيه ومشروبات', description: 'مشروبات ساخنة وباردة.', icon: Icons.local_cafe, tint: Color(0xFFEADCF5), accent: Color(0xFF74459B)),
  CategoryInfo(category: 'ورد وهدايا', title: 'ورد وهدايا', description: 'ورد وهدايا للمناسبات.', icon: Icons.local_florist, tint: Color(0xFFFBD3DD), accent: Color(0xFFB4234F)),
  CategoryInfo(category: 'أخرى', title: 'متاجر متنوعة', description: 'أنشطة ومحلات متنوعة.', icon: Icons.store, tint: Color(0xFFE5E7EB), accent: Color(0xFF4B5563)),
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
