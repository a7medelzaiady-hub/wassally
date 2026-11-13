import 'package:flutter/material.dart';

import 'product.dart';

String _normalizeStoreCategory(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي');
}

/// تصنيف الصيدليات والأدوية المستبعد من الإصدار الأول.
bool isPharmacyCategory(String category) {
  final value = _normalizeStoreCategory(category);
  return value.contains('صيدلي') ||
      value.contains('ادويه') ||
      value.contains('دواء') ||
      value == 'pharmacy' ||
      value == 'pharmacies' ||
      value == 'drugstore' ||
      value == 'drug store' ||
      value == 'medicine' ||
      value == 'medicines';
}

const Map<String, IconData> iconOptions = {
  'restaurant': Icons.restaurant,
  'basket': Icons.shopping_basket,
  'dairy': Icons.icecream,
  'bakery': Icons.bakery_dining,
  'coffee': Icons.local_cafe,
  'flowers': Icons.local_florist,
  'store': Icons.store,
};

class Store {
  final String id;
  final String name;
  final String category;
  final String iconKey;

  /// رابط صورة المحل (من Firebase Storage). فاضي = بنعرض الأيقونة.
  final String imageUrl;
  final int colorHex;
  final double rating;
  final String time;
  final bool active;
  final int order;
  final List<Product> products;

  const Store({
    required this.id,
    required this.name,
    required this.category,
    required this.iconKey,
    required this.colorHex,
    required this.rating,
    required this.time,
    required this.products,
    this.imageUrl = '',
    this.active = true,
    this.order = 0,
  });

  IconData get icon => iconOptions[iconKey] ?? Icons.store;
  Color get color => Color(colorHex);
  bool get isPharmacy => isPharmacyCategory(category);

  factory Store.fromMap(String id, Map<String, dynamic> m) {
    final raw = (m['products'] as List?) ?? const [];
    final products = <Product>[];
    for (final p in raw) {
      if (p is Map) {
        final rawPrice = p['price'];
        final price = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '') ?? 0.0;
        products.add(
          Product(
            (p['name'] ?? '').toString(),
            price,
            (p['image'] ?? '').toString(),
          ),
        );
      }
    }
    return Store(
      id: id,
      name: (m['name'] ?? '').toString(),
      category: (m['category'] ?? 'أخرى').toString(),
      iconKey: (m['icon'] ?? 'store').toString(),
      // الحقل الجديد imageUrl (لوحة الأدمن) مع الرجوع للقديم image.
      imageUrl: (m['imageUrl'] ?? m['image'] ?? '').toString(),
      colorHex: (m['color'] as num?)?.toInt() ?? 0xFFF75A07,
      rating: _avg(m),
      time: (m['time'] ?? '').toString(),
      active: (m['active'] as bool?) ?? true,
      order: (m['order'] as num?)?.toInt() ?? 0,
      products: products,
    );
  }

  Map<String, dynamic> toMap(int index) => {
    'name': name,
    'category': category,
    'icon': iconKey,
    'image': imageUrl,
    'color': colorHex,
    'rating': rating,
    'time': time,
    'active': active,
    'order': index,
    'products': products.map((p) => p.toMap()).toList(),
  };
}

/// متوسط التقييم: من تقييمات العملاء (ratingSum/ratingCount) لو موجودة، وإلا القيمة اليدوية rating.
double _avg(Map<String, dynamic> m) {
  final n = (m['ratingCount'] as num?)?.toInt() ?? 0;
  final sum = (m['ratingSum'] as num?)?.toDouble() ?? 0;
  if (n > 0) return sum / n;
  return (m['rating'] as num?)?.toDouble() ?? 0;
}
