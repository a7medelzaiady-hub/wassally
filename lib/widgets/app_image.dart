import 'package:flutter/material.dart';

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
          : Image.network(
              url,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: width,
                  height: height,
                  color: color.withValues(alpha: 0.08),
                );
              },
            ),
    );
  }
}
