/// قرار قبول نتيجة الكاش المحلي لاستعلام كتالوج (منطق صافي من غير Firebase عشان يتختبر).
///
/// الفكرة: كل تعديل على الكتالوج بيرفع رقم الإصدار، وعند تغيّر الإصدار كل البصمات بتتمسح.
/// فطول ما الإصدار ثابت، نتيجة الخادم لأي استعلام ثابتة. بنحفظ "بصمة" نتيجة الخادم
/// (عدد المستندات + hash لمعرفاتها مرتبة)، والكاش يتقبل بس لو بصمته مطابقة بالظبط:
/// - مستند اتشال من الكاش (مساحة/مسح) ← البصمة تختلف ← نرجع للخادم.
/// - مستند قديم زيادة في الكاش ← البصمة تختلف ← نرجع للخادم.
/// - نفس العدد بمعرفات مختلفة ← الـ hash يختلف ← نرجع للخادم.
/// - نتيجة فاضية متسجلة ← كاش فاضي مطابق ← صفر قراءات (مش قراءة كل مرة).
/// - مفتاح ما اتجابش من الخادم بالإصدار ده ← مفيش بصمة ← نرجع للخادم.
/// تغيير محتوى أو ترتيب صنف من غير تغيير المعرفات ده تعديل، والتعديل بيرفع الإصدار.
class CatalogCachePolicy {
  const CatalogCachePolicy._();

  /// ضرب في 0x01000193 (= 2^24 + 0x193) من غير ما الرقم يعدّي 2^53 (آمن على الويب كمان).
  static int _mul(int h) => ((h * 0x193) + ((h << 24) & 0xffffffff)) & 0xffffffff;

  /// بصمة ثابتة بين تشغيلات التطبيق (FNV-1a 32-bit، مش String.hashCode).
  static String fingerprint(Iterable<String> ids) {
    final sorted = ids.toList()..sort();
    var h = 0x811c9dc5;
    for (final id in sorted) {
      for (final unit in id.codeUnits) {
        h = _mul(h ^ unit);
      }
      h = _mul(h ^ 0x0a); // فاصل بين المعرفات
    }
    return '${sorted.length}:${h.toRadixString(16)}';
  }

  /// [recorded]: بصمة آخر نتيجة خادم للمفتاح ده بالإصدار الحالي (null لو مفيش).
  static bool cacheIsComplete({
    required String? recorded,
    required Iterable<String> cachedIds,
  }) {
    if (recorded == null || recorded.isEmpty) return false;
    return recorded == fingerprint(cachedIds);
  }

  /// "مفتاح|بصمة" — الصيغة القديمة "مفتاح|عدد" بتتقري عادي لكنها مش هتطابق أي بصمة،
  /// فأول فتح بعد التحديث بيقرا من الخادم مرة واحدة لكل مفتاح.
  static Map<String, String> decode(List<String>? raw) {
    final out = <String, String>{};
    for (final entry in raw ?? const <String>[]) {
      final i = entry.lastIndexOf('|');
      if (i <= 0 || i == entry.length - 1) continue;
      out[entry.substring(0, i)] = entry.substring(i + 1);
    }
    return out;
  }

  static List<String> encode(Map<String, String> keys) =>
      [for (final e in keys.entries) '${e.key}|${e.value}'];
}
