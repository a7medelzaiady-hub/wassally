import 'package:flutter/material.dart';

import '../models/home_category.dart';
import '../theme/app_tokens.dart';
import '../theme/brand.dart';
import 'cached_net_image.dart';

/// معرّف كارت «الكل»: يفتح كل المحلات بدون تصفية (القيمة null للفلتر).
const String kAllCategoriesId = 'all';

/// Four realistic-photo category cards per row, independent of Firestore.
/// All cards work with the existing store directory filters. The first card,
/// «الكل», opens every store without a filter (onSelected(null)).
class HomeCategoryGrid extends StatelessWidget {
  const HomeCategoryGrid({
    super.key,
    required this.onSelected,
    this.loadPhotos = true,
    this.selectedId,
    this.highlightSelection = false,
  });

  /// null = «الكل» (بدون تصفية)، غير كده معرّف القسم.
  final ValueChanged<String?> onSelected;

  /// القسم النشط لما الشبكة تُستخدم كفلتر. null = «الكل».
  final String? selectedId;

  /// يظهر تمييز القسم النشط (الرئيسية بتفتح صفحة المحلات فمش محتاجاه).
  final bool highlightSelection;

  /// Can be disabled for deterministic widget layout tests (no network).
  final bool loadPhotos;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 11),
            child: Text(
              'أقسامنا المختلفة',
              style: TextStyle(
                color: Brand.ink,
                fontSize: AppTypography.title,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          LayoutBuilder(builder: (context, constraints) {
            // Height follows the real photo width and the phone's font size
            // so two-line names never overflow, even with large text.
            const columns = 4;
            const spacing = 8.0;
            final tileWidth =
                (constraints.maxWidth - 24 - spacing * (columns - 1)) / columns;
            final labelHeight = MediaQuery.textScalerOf(context)
                    .scale(AppTypography.caption) *
                1.15 *
                2;
            return GridView.builder(
            key: const Key('home-category-grid'),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: homeCategories.length + 1,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: 12,
              mainAxisExtent: tileWidth + 5 + labelHeight + 4,
            ),
            itemBuilder: (context, index) {
              if (index == 0) return _allCard();
              final category = homeCategories[index - 1];
              final selected =
                  highlightSelection && selectedId == category.id;
              final fallback = ColoredBox(
                color: Brand.palette.primary.withValues(alpha: 0.08),
                child: Center(
                  child: Icon(
                    category.icon,
                    color: Brand.palette.primary,
                    size: 29,
                  ),
                ),
              );
              return Semantics(
                label: 'قسم ${category.title}',
                button: true,
                child: InkWell(
                  key: Key('home-category-${category.id}'),
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => onSelected(category.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: _frame(
                          selected: selected,
                          child: loadPhotos
                              ? CachedNetImage(
                                  url: category.photoUrl,
                                  memCacheWidth: 240,
                                  fit: BoxFit.cover,
                                  errorWidget: fallback,
                                )
                              : fallback,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _label(category.title, selected),
                    ],
                  ),
                ),
              );
            },
          );
          }),
        ],
      ),
    );
  }

  Widget _frame({required bool selected, required Widget child}) =>
      AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.purple : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md - 2),
          child: child,
        ),
      );

  Widget _label(String title, bool selected) => Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: selected ? AppColors.purple : AppColors.ink,
          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          fontSize: AppTypography.caption,
          height: 1.15,
        ),
      );

  /// «الكل»: نفس مقاس وأسلوب باقي الكروت، صورة مجمعة من صور الأقسام نفسها.
  Widget _allCard() {
    final selected = highlightSelection && selectedId == null;
    Widget tile(int i) {
      final category = homeCategories[i];
      final fallback = ColoredBox(
        color: AppColors.purpleSoft,
        child: Icon(category.icon, color: AppColors.purple, size: 16),
      );
      return loadPhotos
          ? CachedNetImage(
              url: category.photoUrl,
              memCacheWidth: 120,
              fit: BoxFit.cover,
              errorWidget: fallback,
            )
          : fallback;
    }

    return Semantics(
      label: 'كل الأقسام',
      button: true,
      selected: selected,
      child: InkWell(
        key: const Key('home-category-$kAllCategoriesId'),
        borderRadius: BorderRadius.circular(13),
        onTap: () => onSelected(null),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: _frame(
                selected: selected,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Column(
                      children: [
                        Expanded(child: Row(children: [
                          Expanded(child: tile(0)), const SizedBox(width: 1.5),
                          Expanded(child: tile(1)),
                        ])),
                        const SizedBox(height: 1.5),
                        Expanded(child: Row(children: [
                          Expanded(child: tile(2)), const SizedBox(width: 1.5),
                          Expanded(child: tile(3)),
                        ])),
                      ],
                    ),
                    ColoredBox(color: AppColors.purpleDeep.withValues(alpha: 0.42)),
                    Center(
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.apps_rounded,
                            color: AppColors.purple, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            _label('الكل', selected),
          ],
        ),
      ),
    );
  }
}
