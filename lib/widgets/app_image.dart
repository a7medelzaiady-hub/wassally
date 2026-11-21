import 'package:flutter/material.dart';

import '../utils/img.dart';
import 'cached_net_image.dart';

/// صورة من الإنترنت مع بديل (أيقونة على خلفية ملوّنة) لو مفيش رابط أو فشل
/// التحميل.
class AppImage extends StatelessWidget {
  final String url;
  final IconData fallbackIcon;
  final Color color;
  final double? width;
  final double? height;
  final double iconSize;
  final BorderRadius borderRadius;

  const AppImage({
    super.key,
    required this.url,
    required this.fallbackIcon,
    required this.color,
    this.width,
    this.height,
    this.iconSize = 40,
    this.borderRadius = BorderRadius.zero,
  });

  /// عرض النسخة المصغّرة بالبكسل (ضعف الحجم المعروض تقريبًا للشاشات الكثيفة).
  int get _thumbWidth {
    final side = [width, height].whereType<double>().fold<double>(0, (a, b) => a > b ? a : b);
    if (side <= 0 || side.isInfinite) return 400;
    return (side * 2).round().clamp(96, 800).toInt();
  }

  Widget _fallback() => Container(
    width: width,
    height: height,
    color: color.withValues(alpha: 0.15),
    alignment: Alignment.center,
    child: Icon(fallbackIcon, color: color, size: iconSize),
  );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: url.isEmpty
          ? _fallback()
          : CachedNetImage(
              url: thumb(url, w: _thumbWidth),
              width: width,
              height: height,
              memCacheWidth: _thumbWidth,
              placeholder: Container(
                width: width,
                height: height,
                color: color.withValues(alpha: 0.08),
              ),
              errorWidget: _fallback(),
            ),
    );
  }
}
