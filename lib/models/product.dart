class Product {
  final String name;
  final double price;

  /// رابط صورة الصنف
  final String imageUrl;

  /// معرّف مستند الصنف في Firestore
  final String id;

  /// false = صاحب المحل أو المدير أوقف الصنف مؤقتًا (مش بيظهر للعملاء).
  final bool available;

  /// السعر قبل الخصم (0 = مفيش عرض).
  final double oldPrice;

  bool get hasOffer => oldPrice > price;

  /// نص العرض الحر (مثل «2+1 مجانًا»)، فاضي = مفيش.
  final String offerText;

  /// تاريخ انتهاء العرض (اختياري). العرض المنتهي بيتجاهله التطبيق عند العرض للعميل.
  final DateTime? offerEndsAt;

  // حافظنا على توافق المنشئ القديم مع إضافة id اختياري
  const Product(
    this.name,
    this.price, [
    this.imageUrl = '',
    this.id = '',
    this.available = true,
    this.oldPrice = 0,
    this.offerText = '',
    this.offerEndsAt,
  ]);

  @override
  bool operator ==(Object other) =>
      other is Product && other.name == name && other.price == price;

  @override
  int get hashCode => Object.hash(name, price);

  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    if (imageUrl.isNotEmpty) 'image': imageUrl,
  };
}
