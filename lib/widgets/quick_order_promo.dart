import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// بانر «وصّلي ع السريع» التسويقي: الميزة الرابحة في التطبيق.
/// الرسالة: ريّح دماغك — اكتب أي حاجة من أي مكان، وإحنا نجيبهالك.
class QuickOrderPromo extends StatelessWidget {
  const QuickOrderPromo({super.key, required this.onTap});

  final VoidCallback onTap;

  static const photoAsset = 'assets/images/entry_quick.jpg';

  Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
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

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('quick-order-promo'),
      borderRadius: BorderRadius.circular(AppRadius.xl),
      clipBehavior: Clip.antiAlias,
      elevation: 6,
      shadowColor: AppColors.purple.withValues(alpha: 0.35),
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF8C22E0), Color(0xFF5A0EA0)],
            ),
          ),
          child: LayoutBuilder(builder: (context, box) {
            return Stack(
              children: [
                // الصورة على الطرف وبتذوب في البنفسجي.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: box.maxWidth * 0.38,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: [0, 0.55, 1],
                      colors: [Colors.white, Colors.white, Color(0x00FFFFFF)],
                    ).createShader(rect),
                    child: Image.asset(
                      photoAsset,
                      fit: BoxFit.cover,
                      alignment: const Alignment(-0.2, 0),
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.lg, AppSpacing.lg, box.maxWidth * 0.30, AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Container(
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
                        ),
                      ]),
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                        decoration: BoxDecoration(
                          gradient: AppColors.actionGradient,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('اطلب دلوقتي', style: TextStyle(
                            color: Colors.white,
                            fontSize: AppTypography.bodySmall,
                            fontWeight: FontWeight.w900,
                          )),
                          SizedBox(width: 2),
                          Icon(Icons.chevron_left_rounded, color: Colors.white, size: 20),
                        ]),
                      ),
                    ],
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
