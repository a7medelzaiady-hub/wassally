import '../utils/format.dart';

/// نصوص مشاركة وصّلي (محل/منتج/QR). كلها بتتبني من بيانات معروضة أصلًا:
/// صفر قراءات وصفر كتابات.
class ShareLinks {
  const ShareLinks._();

  static const packageName = 'com.wassally.app';

  /// نفس دومين الـWorker (بيقدّم صفحة /s/ وملف التحقق assetlinks.json).
  static const linkHost = 'throbbing-water-4ef7.a7medelzaiady.workers.dev';

  /// رابط المحل: بيفتح التطبيق على المحل لو متسطب، وإلا جوجل بلاي.
  static String storeLink(String storeId) =>
      Uri.https(linkHost, '/s/${Uri.encodeComponent(storeId.trim())}').toString();

  /// رقم المحل من مسار رابط المشاركة (/s/<id>)، أو null.
  static String? storeIdFromRoute(String? route) {
    if (route == null) return null;
    final path = Uri.tryParse(route)?.path ?? route;
    final m = RegExp(r'^/s/([A-Za-z0-9_-]{1,128})/?$').firstMatch(path);
    return m?.group(1);
  }

  /// رابط التطبيق على جوجل بلاي. [storeId] بيتحط في referrer علشان نقدر
  /// بعدين نفتح المحل نفسه بعد التنزيل (من غير ما يأثر على الرابط دلوقتي).
  static String playLink({String? storeId}) {
    final id = storeId?.trim() ?? '';
    final params = <String, String>{
      'id': packageName,
      if (id.isNotEmpty) 'referrer': 'utm_source=share&utm_content=store_$id',
    };
    return Uri.https('play.google.com', '/store/apps/details', params).toString();
  }

  static String storeMessage({required String storeName, required String storeId}) {
    final name = storeName.trim().isEmpty ? 'المحل ده' : 'محل ${storeName.trim()}';
    return 'شوف $name على تطبيق وصّلي، واطلب واستلم لحد باب البيت 👇\n'
        '${storeId.trim().isEmpty ? playLink() : storeLink(storeId)}';
  }

  static String productMessage({
    required String productName,
    required double price,
    double oldPrice = 0,
    required String storeName,
    required String storeId,
  }) {
    final offer = oldPrice > price ? ' بدل ${formatPrice(oldPrice)}' : '';
    final store = storeName.trim().isEmpty ? '' : ' من ${storeName.trim()}';
    return '${productName.trim()} بـ ${formatPrice(price)}$offer$store على تطبيق وصّلي 👇\n'
        '${storeId.trim().isEmpty ? playLink() : storeLink(storeId)}';
  }
}
