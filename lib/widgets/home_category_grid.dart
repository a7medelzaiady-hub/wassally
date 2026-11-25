import 'package:flutter/material.dart';

import '../models/home_category.dart';
import '../theme/brand.dart';
import 'cached_net_image.dart';

/// Four realistic-photo category cards per row, independent of Firestore.
/// All cards work with the existing store directory filters.
class HomeCategoryGrid extends StatelessWidget {
  const HomeCategoryGrid({
    super.key,
    required this.onSelected,
    this.loadPhotos = true,
  });

  final ValueChanged<String> onSelected;

  /// Can be disabled for deterministic widget layout tests (no network).
  final bool loadPhotos;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 11),
            child: Text(
              'أقسامنا المختلفة',
              style: TextStyle(
                color: Brand.ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          GridView.builder(
            key: const Key('home-category-grid'),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: homeCategories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 10,
              childAspectRatio: 0.66,
            ),
            itemBuilder: (context, index) {
              final category = homeCategories[index];
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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
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
                      Text(
                        category.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Brand.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          height: 1.12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
