import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../utils/format.dart';
import '../utils/img.dart';
import 'cached_net_image.dart';

/// بيانات شريحة عرض صنف (من نفس العروض المحمّلة في الرئيسية، بدون قراءات).
class OfferSlide {
  const OfferSlide({
    required this.name,
    required this.storeName,
    required this.price,
    this.oldPrice = 0,
    this.offerText = '',
    this.image = '',
    required this.onTap,
  });

  final String name;
  final String storeName;
  final double price;
  final double oldPrice;
  final String offerText;
  final String image;
  final VoidCallback onTap;

  bool get hasDiscount => oldPrice > price && oldPrice > 0;
  String get badge => hasDiscount
      ? 'خصم ${((1 - price / oldPrice) * 100).round()}%'
      : offerText;
}

/// بانرات متحركة لعروض الأصناف: بتتقلب لوحدها كل كام ثانية، ويقدر العميل
/// يسحبها بإيده. الضغط بيفتح المحل.
class OfferCarousel extends StatefulWidget {
  const OfferCarousel({
    super.key,
    required this.slides,
    this.autoPlay = true,
    this.loadImages = true,
  });

  final List<OfferSlide> slides;
  final bool autoPlay;
  final bool loadImages;

  @override
  State<OfferCarousel> createState() => _OfferCarouselState();
}

class _OfferCarouselState extends State<OfferCarousel> {
  final _controller = PageController(viewportFraction: 0.9);
  Timer? _timer;
  int _page = 0;

  static const _palettes = <List<Color>>[
    [Color(0xFF8C22E0), Color(0xFF5A0EA0)],
    [Color(0xFFFF8A1F), Color(0xFFD9530A)],
    [Color(0xFF2B1570), Color(0xFF7A14CC)],
  ];

  @override
  void initState() {
    super.initState();
    if (widget.autoPlay && widget.slides.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted || !_controller.hasClients) return;
        final next = (_page + 1) % widget.slides.length;
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _slide(OfferSlide s, int index) {
    final colors = _palettes[index % _palettes.length];
    final fallback = Center(
      child: Icon(Icons.local_offer_rounded,
          size: 48, color: Colors.white.withValues(alpha: 0.85)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Material(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: s.onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: colors,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (s.badge.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              s.badge,
                              maxLines: 1,
                              style: TextStyle(
                                color: colors.last,
                                fontSize: AppTypography.caption,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: AppTypography.title,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          s.storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: AppTypography.label,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(children: [
                          Text(
                            formatPrice(s.price),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: AppTypography.titleSmall,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (s.hasDiscount) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              formatPrice(s.oldPrice),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: AppTypography.caption,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Colors.white70,
                              ),
                            ),
                          ],
                        ]),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: s.image.isEmpty || !widget.loadImages
                          ? fallback
                          : CachedNetImage(
                              url: thumb(s.image, w: 400),
                              memCacheWidth: 400,
                              fit: BoxFit.cover,
                              errorWidget: fallback,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    if (slides.isEmpty) return const SizedBox.shrink();
    final height = MediaQuery.textScalerOf(context).scale(1) * 150;
    return Column(
      key: const Key('offer-carousel'),
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _controller,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => _slide(slides[i], i),
          ),
        ),
        if (slides.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < slides.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? AppColors.orange : AppColors.line,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
