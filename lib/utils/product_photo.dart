/// صورة توضيحية للصنف عند عدم رفع صاحب المحل صورة.
///
/// جميع الروابط ثابتة ومصغّرة ومخزنة في كاش الصور العام: لا بحث مباشر،
/// ولا استدعاءات Firebase/AI ولا حفظ رابط تخميني داخل مستند المنتج.
/// الصورة الأصلية التي يرفعها المحل لها الأولوية دائمًا.
/// لا تُستخدم الصور التوضيحية باعتبارها توثيقًا لشكل أو مكونات الصنف.
class ProductPhoto {
  final String url;
  final bool matchedName;
  const ProductPhoto(this.url, {this.matchedName = false});
}

class _PhotoRule {
  final List<String> words;
  final String url;
  const _PhotoRule(this.words, this.url);
}

const _base = 'https://images.unsplash.com/';

String _unsplash(String id) =>
    '$_base$id?w=360&h=360&fit=crop&auto=format&q=75';

String _normalizeProductName(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
    .replaceAll('أ', 'ا')
    .replaceAll('إ', 'ا')
    .replaceAll('آ', 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// الترتيب مهم: اسم طبق محدد قبل "ساندوتش" و"بطاطس".
final _rules = <_PhotoRule>[
  // صورة طبق باذنجان مطبوخ، وليست وعدًا أن المسقعة من نفس الوصفة.
  _PhotoRule(['مسقعه', 'moussaka'],
      _unsplash('photo-1546069901-ba9599a7e63c')),
  _PhotoRule(['كشري', 'koshari'],
      _unsplash('photo-1547592180-85f173990554')),
  _PhotoRule(['ساندوتش بطاطس', 'سندوتش بطاطس', 'سندويتش بطاطس'],
      _unsplash('photo-1553909489-cd47e0ef937f')),
  _PhotoRule(['فرايز', 'بطاطس محمره', 'بطاطس مقليه', 'fries'],
      _unsplash('photo-1573080496219-bb080dd4f877')),
  _PhotoRule(['فلافل', 'طعميه', 'falafel'],
      _unsplash('photo-1546069901-ba9599a7e63c')),
  _PhotoRule(['بيتزا', 'pizza'],
      _unsplash('photo-1513104890138-7c749659a591')),
  _PhotoRule(['برجر', 'بورجر', 'برغر', 'burger'],
      _unsplash('photo-1568901346375-23c9450c58cd')),
  _PhotoRule(['ساندوتش', 'سندوتش', 'سندويتش', 'sandwich'],
      _unsplash('photo-1553909489-cd47e0ef937f')),
  _PhotoRule(['بطاطس', 'بطاطا', 'potato'],
      _unsplash('photo-1573080496219-bb080dd4f877')),
  _PhotoRule(['سلطه', 'salad'],
      _unsplash('photo-1512621776951-a57141f2eefd')),
  _PhotoRule(['قهوه', 'كابتشينو', 'لاتيه', 'coffee'],
      _unsplash('photo-1495474472287-4d71bcdd2085')),
  _PhotoRule(['عيش', 'خبز', 'رغيف', 'مخبوز', 'bread'],
      _unsplash('photo-1509440159596-0249088772ff')),
  _PhotoRule(['لحمه', 'لحم', 'ستيك', 'meat'],
      _unsplash('photo-1607623814075-e51df1bdc82f')),
  _PhotoRule(['خضار', 'فاكهه', 'طماطم', 'باذنجان', 'خيار', 'vegetable'],
      _unsplash('photo-1542838132-92c53300491e')),
  _PhotoRule(['ورد', 'زهور', 'بوكيه', 'flower'],
      _unsplash('photo-1490750967868-88aa4486c946')),
  _PhotoRule(['بهارات', 'توابل', 'عطاره', 'spice'],
      _unsplash('photo-1596040033229-a9821ebd058d')),
];

/// رابط الصورة المعروضة، دون تغيير بيانات الكتالوج أو زيادة قراءات Firestore.
ProductPhoto productPhotoFor({
  required String name,
  String uploadedUrl = '',
  String storeCategory = '',
}) {
  if (uploadedUrl.trim().isNotEmpty) {
    return ProductPhoto(uploadedUrl.trim());
  }
  final normalized = _normalizeProductName(name);
  for (final rule in _rules) {
    if (rule.words.any(normalized.contains)) {
      return ProductPhoto(rule.url, matchedName: true);
    }
  }
  final category = _normalizeProductName(storeCategory);
  if (category.contains('مطعم') || category.contains('اكل') ||
      category.contains('وجبات') || category.contains('كافيه')) {
    return ProductPhoto(_unsplash('photo-1546069901-ba9599a7e63c'));
  }
  if (category.contains('مخبوز') || category.contains('حلويات')) {
    return ProductPhoto(_unsplash('photo-1509440159596-0249088772ff'));
  }
  if (category.contains('ورد')) {
    return ProductPhoto(_unsplash('photo-1490750967868-88aa4486c946'));
  }
  if (category.contains('لحوم') || category.contains('دواجن')) {
    return ProductPhoto(_unsplash('photo-1607623814075-e51df1bdc82f'));
  }
  // الخلفية العامة صورة منتجات متجر، وليست صنفًا دقيقًا.
  return ProductPhoto(_unsplash('photo-1542838132-92c53300491e'));
}
