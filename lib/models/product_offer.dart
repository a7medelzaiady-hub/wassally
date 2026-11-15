/// أنواع العروض التي يمكن إعدادها دون ربطها بالتخزين أو واجهات العميل.
///
/// هذا النموذج مستقل عمدًا عن Firebase وProduct؛ يمكن ربطه لاحقًا بطبقة
/// المستودع وواجهات صاحب المحل/العميل بعد اعتماد مخطط Firestore.
enum ProductOfferType {
  percentage,
  fixedPrice,
  text,
}

/// تمثيل نطاقي (Domain) لعرض على صنف.
///
/// - percentage: يحسب السعر بعد الخصم من السعر الأصلي.
/// - fixedPrice: يحدد سعرًا جديدًا مع الاحتفاظ بالسعر الأصلي.
/// - text: عرض وصفي مثل "2 + 1 مجانًا" دون تغيير سعر الوحدة.
///
/// لا يحتوي هذا الكلاس على toMap/fromMap أو أي اعتماد على Firebase؛
/// لذلك إنشاؤه أو اختباره لا يقرأ أو يكتب أي مستندات أو طلبات.
class ProductOffer {
  final ProductOfferType type;
  final double originalPrice;
  final double? offerPrice;
  final double? percentage;
  final String? description;

  const ProductOffer._({
    required this.type,
    required this.originalPrice,
    this.offerPrice,
    this.percentage,
    this.description,
  });

  /// إنشاء عرض بنسبة خصم من السعر الأصلي.
  factory ProductOffer.percentage({
    required double originalPrice,
    required double percentage,
  }) {
    _validatePrice(originalPrice, 'السعر الأصلي');
    final basePrice = _money(originalPrice);
    if (!percentage.isFinite || percentage <= 0 || percentage >= 100) {
      throw ArgumentError.value(
        percentage,
        'percentage',
        'نسبة الخصم يجب أن تكون أكبر من 0 وأقل من 100.',
      );
    }

    final discounted = _money(basePrice * (1 - percentage / 100));
    if (discounted <= 0 || discounted >= basePrice) {
      throw ArgumentError('نسبة الخصم لا تنتج سعرًا صالحًا.');
    }

    return ProductOffer._(
      type: ProductOfferType.percentage,
      originalPrice: basePrice,
      offerPrice: discounted,
      percentage: percentage,
    );
  }

  /// إنشاء عرض بسعر جديد مباشر مع الاحتفاظ بالسعر الأصلي.
  factory ProductOffer.fixedPrice({
    required double originalPrice,
    required double offerPrice,
  }) {
    _validatePrice(originalPrice, 'السعر الأصلي');
    _validatePrice(offerPrice, 'سعر العرض');
    final basePrice = _money(originalPrice);
    final newPrice = _money(offerPrice);
    if (newPrice <= 0 || newPrice >= basePrice) {
      throw ArgumentError.value(
        offerPrice,
        'offerPrice',
        'سعر العرض يجب أن يكون أقل من السعر الأصلي.',
      );
    }

    return ProductOffer._(
      type: ProductOfferType.fixedPrice,
      originalPrice: basePrice,
      offerPrice: newPrice,
    );
  }

  /// إنشاء عرض نصي لا يغيّر سعر الوحدة، مثل "2 + 1 مجانًا".
  factory ProductOffer.text({
    required double originalPrice,
    required String description,
  }) {
    _validatePrice(originalPrice, 'السعر الأصلي');
    final cleanDescription = description.trim();
    if (cleanDescription.isEmpty || cleanDescription.length > 120) {
      throw ArgumentError.value(
        description,
        'description',
        'اكتب وصفًا للعرض من 1 إلى 120 حرفًا.',
      );
    }

    return ProductOffer._(
      type: ProductOfferType.text,
      originalPrice: _money(originalPrice),
      description: cleanDescription,
    );
  }

  /// السعر الذي يستخدمه منطق التسعير عند تفعيل العرض.
  /// العرض النصي لا يغيّر سعر الوحدة.
  double get effectivePrice => offerPrice ?? originalPrice;

  /// مقدار التوفير النقدي، ويساوي صفرًا للعروض النصية.
  double get savings => _money(originalPrice - effectivePrice);

  /// نسبة التوفير المحسوبة للعروض السعرية فقط.
  double? get calculatedPercentage {
    if (type == ProductOfferType.text) return null;
    return _money((savings / originalPrice) * 100);
  }

  /// السعر الذي يجب استعادته عند إلغاء العرض.
  double get restoredPrice => originalPrice;

  bool get changesUnitPrice => type != ProductOfferType.text;

  static void _validatePrice(double value, String label) {
    if (!value.isFinite || value <= 0 || value > 20000) {
      throw ArgumentError.value(
        value,
        label,
        '$label يجب أن يكون أكبر من صفر ولا يتجاوز 20000.',
      );
    }
  }

  static double _money(double value) =>
      (value * 100).roundToDouble() / 100;
}

/// ما يُعرض للعميل فعليًا بعد تجاهل العرض المنتهي.
class OfferDisplay {
  final double price;
  final double oldPrice;
  final String text;
  final DateTime? endsAt;

  const OfferDisplay({
    required this.price,
    required this.oldPrice,
    required this.text,
    required this.endsAt,
  });
}

/// هل انتهى العرض؟ (بدون تاريخ انتهاء = مفتوح).
bool isOfferExpired(DateTime? endsAt, DateTime now) =>
    endsAt != null && !now.isBefore(endsAt);

/// بيحدّد السعر والعرض اللي يظهروا للعميل. لو العرض انتهى بيتجاهله: السعر يرجع للسعر
/// الأصلي (oldPrice) وبيتشال خصم النسبة ونص العرض. السعر المخزّن في Firestore بيفضل زي ما هو
/// لحد ما صاحب المحل يلغي العرض أو يجدده.
OfferDisplay resolveOfferDisplay({
  required double price,
  double oldPrice = 0,
  String text = '',
  DateTime? endsAt,
  DateTime? now,
}) {
  if (isOfferExpired(endsAt, now ?? DateTime.now())) {
    return OfferDisplay(
      price: oldPrice > price ? oldPrice : price,
      oldPrice: 0,
      text: '',
      endsAt: null,
    );
  }
  return OfferDisplay(
    price: price,
    oldPrice: oldPrice > price ? oldPrice : 0,
    text: text.trim(),
    endsAt: endsAt,
  );
}
