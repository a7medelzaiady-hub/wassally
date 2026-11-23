import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/image_cache.dart';

/// صورة عامة من الإنترنت بكاش قرص محدود (راجع [WasallyImageCache]).
/// - لو الرابط فاضي أو فشل التحميل بيظهر [errorWidget] (نفس البديل القديم).
/// - [memCacheWidth] بيصغّر فك الترميز في الذاكرة (وبيوفّر RAM).
/// - ما تستخدمهاش لصور خاصة بالمستخدم أو الطلبات؛ استخدم Image.network.
class CachedNetImage extends StatefulWidget {
  final String url;
  final Widget errorWidget;
  final Widget? placeholder;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheWidth;

  /// بعد المدة دي من غير ما الصورة تظهر بنعرض البديل بدل سبينر/فراغ للأبد
  /// (شبكة بطيئة). لو الصورة وصلت بعدها بتظهر عادي.
  final Duration slowAfter;

  const CachedNetImage({
    super.key,
    required this.url,
    required this.errorWidget,
    this.placeholder,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.slowAfter = const Duration(seconds: 10),
  });

  @override
  State<CachedNetImage> createState() => _CachedNetImageState();
}

class _CachedNetImageState extends State<CachedNetImage> {
  Timer? _timer;
  bool _slow = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant CachedNetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _loaded = false;
      _slow = false;
      _arm();
    }
  }

  void _arm() {
    _timer?.cancel();
    if (widget.url.trim().isEmpty) return;
    _timer = Timer(widget.slowAfter, () {
      if (mounted && !_loaded) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.trim().isEmpty) return widget.errorWidget;
    // أثناء التحميل نعرض البديل نفسه (مش فراغ): الدوائر والكروت ما تبانش فاضية.
    final ph = widget.placeholder ?? widget.errorWidget;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        CachedNetworkImage(
          imageUrl: widget.url,
          cacheManager: WasallyImageCache.manager,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          memCacheWidth: widget.memCacheWidth,
          fadeInDuration: const Duration(milliseconds: 120),
          fadeOutDuration: const Duration(milliseconds: 80),
          placeholder: (_, _) => _slow ? widget.errorWidget : ph,
          imageBuilder: (context, provider) {
            if (!_loaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _loaded = true);
              });
            }
            return Image(
              image: provider,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
            );
          },
          errorWidget: (_, _, _) => widget.errorWidget,
        ),
      ],
    );
  }
}
