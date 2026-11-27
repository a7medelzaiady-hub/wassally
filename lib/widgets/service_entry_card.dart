import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// كارت خدمة زي صفحة ما بعد الدخول: الصورة على اليسار بألوانها كاملة، وحرفها بس
/// بيسيح تدريجي في الأبيض ناحية النص (من غير فاصل)، والعنوان والوصف والزر البرتقالي
/// على اليمين. نفس الكارت بيتستخدم في الرئيسية لـ«وصّلي ع السريع».
/// [asset] فاضي = لوحة بنفسجي بأيقونة [icon].
class ServiceEntryCard extends StatelessWidget {
  const ServiceEntryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.action,
    this.asset,
    this.icon = Icons.delivery_dining_rounded,
    required this.onTap,
    required this.height,
  });

  final String title;
  final String subtitle;
  final String action;
  final String? asset;
  final IconData icon;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final asset = this.asset;
    return SizedBox(
      height: height,
      child: Material(
        elevation: 3,
        shadowColor: AppColors.ink.withValues(alpha: 0.12),
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: const BorderSide(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('entry-card-$title'),
          onTap: onTap,
          splashColor: AppColors.purple.withValues(alpha: 0.08),
          highlightColor: AppColors.purple.withValues(alpha: 0.04),
          child: LayoutBuilder(builder: (context, box) {
            final artWidth = box.maxWidth * 0.66;
            return Stack(
              children: [
                // الصورة واضحة لحد ~نص الكارت، وبعدها بس بتذوب في الأبيض
                // (شفافية مش طبقة بيضا فوقها)، فمفيش حد ظاهر ولا صورة باهتة.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: artWidth,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: [0.0, 0.72, 0.86, 1.0],
                      colors: [Colors.black, Colors.black, Color(0x80000000), Color(0x00000000)],
                    ).createShader(rect),
                    child: asset != null
                        ? Image.asset(
                            asset,
                            key: ValueKey<String>('entry-art-$title'),
                            fit: BoxFit.cover,
                            alignment: Alignment.centerLeft,
                            excludeFromSemantics: true,
                          )
                        : DecoratedBox(
                            key: ValueKey<String>('entry-art-$title'),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [AppColors.purpleDarker, AppColors.purple],
                              ),
                            ),
                            child: Align(
                              alignment: const Alignment(-0.45, 0),
                              child: FractionallySizedBox(
                                heightFactor: 0.6,
                                child: FittedBox(
                                  child: Icon(icon, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: box.maxWidth * 0.56,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            title,
                            maxLines: 1,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 17,
                              height: 1.2,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: AppTypography.caption - 1,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.orangeLight, AppColors.orange, AppColors.orangeDeep],
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.orange.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          // يفضل في سطر واحد كامل من غير «...» حتى في الشاشات الضيقة.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              action,
                              maxLines: 1,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: AppTypography.label - 1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
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
