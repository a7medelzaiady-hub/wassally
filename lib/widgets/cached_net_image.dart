import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/image_cache.dart';

/// صورة عامة من الإنترنت بكاش قرص محدود (راجع [WasallyImageCache]).
/// - لو الرابط فاضي أو فشل التحميل بيظهر [errorWidget] (نفس البديل القديم).
/// - [memCacheWidth] بيصغّر فك الترميز في الذاكرة (وبيوفّر RAM).
/// - ما تستخدمهاش لصور خاصة بالمستخدم أو الطلبات؛ استخدم Image.network.
class CachedNetImage extends StatelessWidget {
  final String url;
  final Widget errorWidget;
  final Widget? placeholder;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheWidth;

  const CachedNetImage({
    super.key,
    required this.url,
    required this.errorWidget,
    this.placeholder,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) return errorWidget;
    final ph = placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: WasallyImageCache.manager,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: memCacheWidth,
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: const Duration(milliseconds: 80),
      placeholder: ph == null ? null : (_, _) => ph,
      errorWidget: (_, _, _) => errorWidget,
    );
  }
}
