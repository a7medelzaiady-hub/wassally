import '../utils/format.dart';

/// نصوص مشاركة وصّلي (محل/منتج/QR). كلها بتتبني من بيانات معروضة أصلًا:
/// صفر قراءات وصفر كتابات.
class ShareLinks {
  const ShareLinks._();

  static const packageName = 'com.wassally.app';

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
        '${playLink(storeId: storeId)}';
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
        '${playLink(storeId: storeId)}';
  }
}
