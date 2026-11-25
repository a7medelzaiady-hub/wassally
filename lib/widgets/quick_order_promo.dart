import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// ميزة «صوّر طلبك» (#242). الإعلان بتاعها بيظهر بس لما الميزة تتفعل،
/// علشان ما نعلنش عن حاجة العميل مش هيلاقيها.
const bool kQuickPhotoOrdersEnabled = false;

/// إطار إعلان موحد: صورة حقيقية على طرف بتذوب في الخلفية والكلام فوقها.
/// الكلام بيصغر لوحده لو المساحة ضيقة بدل ما يتقص.
class _PromoFrame extends StatelessWidget {
  const _PromoFrame({
    required this.promoKey,
    required this.colors,
    required this.photo,
    required this.onTap,
    required this.child,
    this.photoAlignment = const Alignment(-0.2, 0),
    this.photoWidth = 0.4,
  });

  final Key promoKey;
  final List<Color> colors;
  final String photo;
  final Alignment photoAlignment;
  final double photoWidth;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: promoKey,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shadowColor: AppColors.purple.withValues(alpha: 0.3),
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: colors,
            ),
          ),
          child: LayoutBuilder(builder: (context, box) {
            final textWidth = box.maxWidth * (1 - photoWidth + 0.06) - AppSpacing.lg * 2;
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: box.maxWidth * photoWidth,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: [0, 0.6, 1],
                      colors: [Colors.white, Colors.white, Color(0x00FFFFFF)],
                    ).createShader(rect),
                    child: Image.asset(
                      photo,
                      fit: BoxFit.cover,
                      alignment: photoAlignment,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: AppSpacing.lg,
                  top: AppSpacing.md,
                  bottom: AppSpacing.md,
                  width: textWidth,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: SizedBox(width: textWidth, child: child),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

Widget _badge() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.orange,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bolt_rounded, size: 15, color: Colors.white),
        Text('وصّلي ع السريع', style: TextStyle(
          color: Colors.white,
          fontSize: AppTypography.caption,
          fontWeight: FontWeight.w900,
        )),
      ]),
    );

Widget _chip(IconData icon, String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(
          color: Colors.white,
          fontSize: AppTypography.caption,
          fontWeight: FontWeight.w800,
        )),
      ]),
    );

Widget _cta(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        gradient: AppColors.actionGradient,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(
          color: Colors.white,
          fontSize: AppTypography.bodySmall,
          fontWeight: FontWeight.w900,
        )),
        const SizedBox(width: 2),
        const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 20),
      ]),
    );

/// إعلان «وصّلي ع السريع»: ريّح دماغك — أي حاجة من أي محل.
class QuickOrderPromo extends StatelessWidget {
  const QuickOrderPromo({super.key, required this.onTap});

  final VoidCallback onTap;

  static const photoAsset = 'assets/images/entry_quick.jpg';

  @override
  Widget build(BuildContext context) => _PromoFrame(
        promoKey: const Key('quick-order-promo'),
        colors: const [Color(0xFF8C22E0), Color(0xFF5A0EA0)],
        photo: photoAsset,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _badge(),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'ريّح دماغك… اطلب أي حاجة من أي مكان',
              style: TextStyle(
                color: Colors.white,
                fontSize: AppTypography.title,
                height: 1.25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'اكتب طلباتك بكلامك، ومندوب معتمد يشتريها ويوصّلها لحد بابك.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: AppTypography.label,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip(Icons.storefront_rounded, 'أي محل'),
              _chip(Icons.shopping_basket_rounded, 'أي حاجة'),
              _chip(Icons.phone_in_talk_rounded, 'بمكالمة واحدة'),
            ]),
            const SizedBox(height: AppSpacing.md),
            _cta('اطلب دلوقتي'),
          ],
        ),
      );
}

/// إعلان «صوّر ورقتك… وابعتها على التطبيق» (ميزة #242).
class PhotoOrderPromo extends StatelessWidget {
  const PhotoOrderPromo({super.key, required this.onTap});

  final VoidCallback onTap;

  static const photoAsset = 'assets/images/quick_photo_ad.jpg';

  @override
  Widget build(BuildContext context) => _PromoFrame(
        promoKey: const Key('photo-order-promo'),
        colors: const [Color(0xFF4A0C80), Color(0xFF26104F)],
        photo: photoAsset,
        photoWidth: 0.44,
        photoAlignment: const Alignment(-0.1, -0.2),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _badge(),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'صوّر ورقتك… وابعتها على التطبيق',
              style: TextStyle(
                color: Colors.white,
                fontSize: AppTypography.title,
                height: 1.25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Text(
              'واحنا نجيبهالك لحد عندك',
              style: TextStyle(
                color: AppColors.orangeLight,
                fontSize: AppTypography.titleSmall,
                height: 1.3,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'اكتب طلباتك في ورقة، صوّرها وابعتها. مندوب معتمد يشتري اللي فيها ويوصّله لحد بابك.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: AppTypography.label,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip(Icons.photo_camera_outlined, 'صوّر الورقة'),
              _chip(Icons.send_rounded, 'ابعتها'),
              _chip(Icons.inventory_2_outlined, 'استلم طلبك'),
            ]),
            const SizedBox(height: AppSpacing.md),
            _cta('جرّبها دلوقتي'),
          ],
        ),
      );
}

/// إعلانات متحركة: بتتقلب لوحدها، والعميل يقدر يسحبها. تقبل أي عدد إعلانات.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({super.key, required this.slides, this.autoPlay = true});

  final List<Widget> slides;
  final bool autoPlay;

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    if (widget.autoPlay && widget.slides.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.animateToPage(
          (_page + 1) % widget.slides.length,
          duration: const Duration(milliseconds: 500),
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

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    if (slides.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      final height = (box.maxWidth * 0.68).clamp(230.0, 320.0);
      return Column(
        key: const Key('promo-carousel'),
        children: [
          SizedBox(
            height: height,
            child: slides.length == 1
                ? slides.first
                : PageView.builder(
                    controller: _controller,
                    itemCount: slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => slides[i],
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
    });
  }
}
