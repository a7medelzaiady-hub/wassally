/// اختيار واحد جوه مجموعة (مثلاً «بدون سكر» أو «كوكيز +90»).
class ProductOption {
  final String name;

  /// السعر الإضافي (0 = من غير زيادة).
  final double price;
  const ProductOption(this.name, [this.price = 0]);

  Map<String, dynamic> toMap() => {'name': name, if (price > 0) 'price': price};

  static ProductOption? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final p = raw['price'];
    final price = p is num && p > 0 ? p.toDouble() : 0.0;
    return ProductOption(name, price);
  }
}

/// مجموعة خيارات للصنف، زي «السكر» (اختيار واحد) أو «إضافات» (لحد 3).
class OptionGroup {
  final String title;

  /// أقل عدد اختيارات مطلوب (0 = اختياري، 1 أو أكتر = إجباري).
  final int min;

  /// أقصى عدد اختيارات (1 = اختيار واحد/راديو، أكتر = اختيار متعدد).
  final int max;
  final List<ProductOption> options;

  const OptionGroup(this.title, this.options, {this.min = 0, this.max = 1});

  bool get required => min > 0;
  bool get single => max == 1;

  Map<String, dynamic> toMap() => {
    'title': title,
    'min': min,
    'max': max,
    'options': options.map((o) => o.toMap()).toList(),
  };

  static OptionGroup? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final title = (raw['title'] ?? '').toString().trim();
    final opts = <ProductOption>[
      for (final o in (raw['options'] is List ? raw['options'] as List : const []))
        if (ProductOption.tryParse(o) case final parsed?) parsed,
    ];
    if (title.isEmpty || opts.isEmpty) return null;
    final rawMax = raw['max'];
    final rawMin = raw['min'];
    final max = (rawMax is num ? rawMax.toInt() : 1).clamp(1, opts.length);
    final min = (rawMin is num ? rawMin.toInt() : 0).clamp(0, max);
    return OptionGroup(title, opts, min: min, max: max);
  }
}

/// بيقرا مجموعات الخيارات من حقل `optionGroups` في مستند الصنف (بيتجاهل الغلط).
List<OptionGroup> parseOptionGroups(Object? raw) => [
  for (final g in (raw is List ? raw : const []))
    if (OptionGroup.tryParse(g) case final parsed?) parsed,
];

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
    this.description = '',
    this.optionGroups = const [],
    this.chosen = const [],
  ]);

  /// وصف الصنف (اختياري).
  final String description;

  /// مجموعات الخيارات اللي صاحب المحل ضافها (سكر، إضافات...).
  final List<OptionGroup> optionGroups;

  /// الاختيارات اللي العميل اختارها (بيكون فيها حاجة بس في سطر السلة).
  final List<ProductOption> chosen;

  bool get hasOptions => optionGroups.isNotEmpty;

  /// مجموع أسعار الاختيارات الإضافية.
  double get chosenTotal => chosen.fold(0.0, (a, o) => a + o.price);

  /// نسخة من الصنف بالاختيارات دي: الاسم بيتضاف له الاختيارات والسعر بيزيد بقيمتها،
  /// فكل تركيبة بتبقى سطر مستقل في السلة. المعرّف ثابت عشان نرجع للكتالوج.
  Product withChoices(List<ProductOption> picks) {
    if (picks.isEmpty) return this;
    final extra = picks.fold(0.0, (a, o) => a + o.price);
    return Product(
      '$name (${picks.map((o) => o.name).join('، ')})',
      price + extra,
      imageUrl,
      id,
      available,
      0,
      '',
      null,
      description,
      const [],
      picks,
    );
  }

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
