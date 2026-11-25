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

  /// شريحة بأسلوب تطبيقات التوصيل: صورة الصنف مالية الكارت، وطبقة
  /// غامقة تحت عليها الاسم والسعر، وشارة الخصم فوق.
  Widget _slide(OfferSlide s, int index) {
    final colors = _palettes[index % _palettes.length];
    final hasImage = s.image.isNotEmpty && widget.loadImages;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: colors,
        ),
      ),
      child: Align(
        alignment: const AlignmentDirectional(-0.75, -0.2),
        child: Icon(Icons.shopping_basket_rounded,
            size: 72, color: Colors.white.withValues(alpha: 0.22)),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Material(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: s.onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                CachedNetImage(
                  url: thumb(s.image, w: 700),
                  memCacheWidth: 700,
                  fit: BoxFit.cover,
                  errorWidget: fallback,
                )
              else
                fallback,
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.35, 1],
                    colors: [Color(0x00000000), Color(0xCC1C0B3A)],
                  ),
                ),
              ),
              if (s.badge.isNotEmpty)
                PositionedDirectional(
                  top: AppSpacing.md,
                  start: AppSpacing.md,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      s.badge,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: AppTypography.label,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              PositionedDirectional(
                start: AppSpacing.lg,
                end: AppSpacing.lg,
                bottom: AppSpacing.md,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatPrice(s.price),
                            style: const TextStyle(
                              color: AppColors.orangeDeep,
                              fontSize: AppTypography.titleSmall,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (s.hasDiscount)
                            Text(
                              formatPrice(s.oldPrice),
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: AppTypography.caption,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    if (slides.isEmpty) return const SizedBox.shrink();
    final height = MediaQuery.textScalerOf(context).scale(1) * 170;
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
