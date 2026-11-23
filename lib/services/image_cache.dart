import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// كاش صور القرص للصور **العامة** فقط (المحلات، المنتجات، العروض، التصنيفات).
///
/// الحدود:
///  • بحد أقصى [maxObjects] ملف، وكل ملف نسخة مصغّرة من Cloudinary (عادةً أقل من 100KB)،
///    فالمساحة الإجمالية عمليًا أقل من 15MB.
///  • الملف اللي عدّى [stalePeriod] بيتعاد تحميله، وبيتحذف لو فاض الحد.
///  • صور الطلبات والمرفقات الخاصة (صورة الطلب الخاص، إلخ) **ما بتتخزنش هنا أبدًا**؛
///    بتفضل على Image.network.
///  • بيتمسح بالكامل عند تسجيل الخروج وحذف الحساب.
class WasallyImageCache {
  const WasallyImageCache._();

  static const String key = 'wasallyImages';
  static const int maxObjects = 150;
  static const Duration stalePeriod = Duration(days: 7);

  static final CacheManager manager = CacheManager(
    Config(key, stalePeriod: stalePeriod, maxNrOfCacheObjects: maxObjects),
  );

  /// يمسح كاش القرص وكاش الذاكرة. الفشل ما يوقفش تسجيل الخروج.
  static Future<void> clear() async {
    try {
      await manager.emptyCache();
    } catch (_) {}
    try {
      final cache = PaintingBinding.instance.imageCache;
      cache.clear();
      cache.clearLiveImages();
    } catch (_) {}
  }
}
