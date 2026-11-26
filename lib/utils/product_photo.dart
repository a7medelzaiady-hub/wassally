/// صورة توضيحية للصنف عند عدم رفع صاحب المحل صورة.
///
/// القاموس محلي وثابت: لا ذكاء اصطناعي، ولا بحث شبكة، ولا قراءات/كتابات
/// Firestore. الصور URLs ثابتة ومصغرة، ويعيد كاش الصور استخدام الصورة بين
/// كل المنتجات التي تنتمي لنفس النوع. الصور للتوضيح وليست صورة العبوة الفعلية.
class ProductPhoto {
  final String url;

  /// true لو وجدنا اسم منتج واضح؛ false لو استخدمنا صورة القسم العامة.
  final bool matchedName;
  const ProductPhoto(this.url, {this.matchedName = false});
}

class _PhotoRule {
  final List<String> words;
  final String url;
  const _PhotoRule(this.words, this.url);
}

class _IndexedRule {
  final List<String> words;
  final String url;
  const _IndexedRule(this.words, this.url);
}

const _base = 'https://images.unsplash.com/';

// صور محددة وليست بحثًا متغيرًا عند كل طلب. 320px وجودة 65 لتوفير الباقة.
// نستخدم الصورة نفسها لكل مرادفات النوع؛ هذا يسمح بمشاركتها من كاش الصور.
String _unsplash(String id) =>
    '$_base$id?w=320&h=320&fit=crop&auto=format&q=65';

// إبقاء روابط الأطباق المصرية الحالية؛ الروابط ثابتة وليست طلب بحث.
String _unsplashPhoto(String id) =>
    'https://unsplash.com/photos/$id/download?force=true&w=320';

String _normalizeProductName(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
    .replaceAll('أ', 'ا')
    .replaceAll('إ', 'ا')
    .replaceAll('آ', 'ا')
    .replaceAll('ٱ', 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي')
    .replaceAll(RegExp(r'[^a-z0-9\u0621-\u064A]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// مطابقة كلمات كاملة، مش احتواء جزئي: "رز" لا يطابق "أرزاق"، و"ورد"
/// لا يطابق "مورد". وتدعم الكلمات المركبة زي "زيت موتور".
bool _hasPhrase(String normalized, String phrase) =>
    normalized.isNotEmpty &&
    phrase.isNotEmpty &&
    ' $normalized '.contains(' $phrase ');

// الأولوية للأسماء المحددة قبل الكلمات العامة؛ مثال: زيت شعر قبل زيت،
/// بطاطس مقلية قبل بطاطس، وساندوتش قبل بطاطس.
final _rules = <_PhotoRule>[
  // مطاعم وأكلات سريعة.
  _PhotoRule(['مسقعة', 'moussaka'], _unsplashPhoto('TGNW6qxGrOw')),
  _PhotoRule(['كشري', 'koshari'], _unsplashPhoto('9Tz8JEXfNQU')),
  _PhotoRule(['ساندوتش بطاطس', 'سندوتش بطاطس', 'سندويتش بطاطس'],
      _unsplash('photo-1553909489-cd47e0ef937f')),
  _PhotoRule(['بطاطس محمرة', 'بطاطس مقلية', 'فرنش فرايز', 'فرايز', 'fries'],
      _unsplash('photo-1573080496219-bb080dd4f877')),
  _PhotoRule(['فلافل', 'طعمية', 'طعمية بلدي', 'falafel'],
      _unsplashPhoto('V3OnqusloQE')),
  _PhotoRule(['بيتزا', 'pizza'], _unsplash('photo-1513104890138-7c749659a591')),
  _PhotoRule(['برجر', 'بورجر', 'برغر', 'burger'],
      _unsplash('photo-1568901346375-23c9450c58cd')),
  _PhotoRule(['ساندوتش', 'سندوتش', 'سندويتش', 'شاورما', 'shawarma', 'sandwich'],
      _unsplash('photo-1553909489-cd47e0ef937f')),
  _PhotoRule(['مكرونة بشاميل', 'باستا', 'اسباجتي', 'سباجيتي', 'pasta'],
      _unsplash('photo-1551183053-bf91a1d81141')),
  _PhotoRule(['سلطة', 'سلطه', 'salad'],
      _unsplash('photo-1512621776951-a57141f2eefd')),

  // زيوت السيارات والعناية قبل كلمة "زيت" الغذائية.
  _PhotoRule(['زيت موتور', 'زيت محرك', 'زيت فتيس', 'زيت فرامل', 'زيت سيارات',
      'بترومين', 'زيت شل هيلكس', 'engine oil', 'motor oil'],
      _unsplash('photo-1487754180451-c456f719a1fc')),
  _PhotoRule(['زيت شعر', 'زيت للجسم', 'hair oil', 'body oil'],
      _unsplash('photo-1608248543803-ba4f8c70ae0b')),

  // ألبان وبيض وأغذية يومية.
  _PhotoRule(['لبن بودرة', 'لبن بودر', 'حليب بودرة', 'حليب مجفف'],
      _unsplash('photo-1550583724-b2692b85b150')),
  _PhotoRule(['لبن', 'حليب', 'milk'],
      _unsplash('photo-1550583724-b2692b85b150')),
  _PhotoRule(['جبنة', 'جبن', 'جبنه', 'cheese'],
      _unsplash('photo-1486297678162-eb2a19b0a32d')),
  _PhotoRule(['زبادي', 'يوغرت', 'yogurt'],
      _unsplash('photo-1550583724-b2692b85b150')),
  _PhotoRule(['بيض', 'بيضة', 'eggs', 'egg'],
      _unsplash('photo-1506976785307-8732e854ad03')),
  _PhotoRule(['زبدة', 'سمنة', 'سمن', 'مارجرين', 'butter'],
      _unsplash('photo-1486297678162-eb2a19b0a32d')),

  // البقالة والعطارة: صور للنوع، مش للعلامة التجارية أو وزن العبوة.
  _PhotoRule(['زيت زيتون', 'olive oil', 'زيت طعام', 'زيت عباد الشمس',
      'زيت ذرة', 'زيت قلي', 'زيت', 'oil'],
      _unsplash('photo-1604908177225-45c3d5f3c7c1')),
  _PhotoRule(['أرز', 'ارز', 'رز', 'بسمتي', 'rice'],
      _unsplash('photo-1586201375761-83865001e31c')),
  _PhotoRule(['مكرونة', 'مكرونه', 'شعرية', 'لسان عصفور', 'مكروني', 'macaroni'],
      _unsplash('photo-1551183053-bf91a1d81141')),
  _PhotoRule(['دقيق', 'طحين', 'خميرة', 'بيكنج بودر', 'flour'],
      _unsplash('photo-1509440159596-0249088772ff')),
  _PhotoRule(['سكر', 'سكر بودرة', 'sugar'],
      _unsplash('photo-1542838132-92c53300491e')),
  _PhotoRule(['ملح', 'فلفل اسود', 'كمون', 'كركم', 'كزبرة ناشفة',
      'قرفة', 'شطة', 'بابريكا', 'بهارات', 'توابل', 'عطارة', 'spice'],
      _unsplash('photo-1596040033229-a9821ebd058d')),
  _PhotoRule(['عدس', 'فول', 'حمص', 'فاصوليا', 'لوبيا', 'ترمس',
      'بقوليات', 'legumes', 'lentils', 'beans'],
      _unsplash('photo-1586201375761-83865001e31c')),
  _PhotoRule(['عسل نحل', 'عسل ابيض', 'عسل', 'honey'],
      _unsplash('photo-1587049352851-8d4e89133924')),
  _PhotoRule(['مربى', 'مربي', 'طحينة', 'طحينه', 'صلصة', 'صلصه',
      'تونة', 'تونه', 'فول معلب', 'معلبات', 'كاتشب', 'مايونيز'],
      _unsplash('photo-1542838132-92c53300491e')),

  // المشروبات: الشاي/القهوة قبل الكلمات المجمّعة.
  _PhotoRule(['شاي', 'tea'], _unsplash('photo-1544787219-7f47ccb76574')),
  _PhotoRule(['قهوة', 'قهوه', 'نسكافيه', 'كابتشينو', 'لاتيه', 'coffee', 'nescafe'],
      _unsplash('photo-1495474472287-4d71bcdd2085')),
  _PhotoRule(['مياه معدنية', 'مياه شرب', 'مياة', 'مياه', 'مية',
      'زجاجة مياه', 'water'],
      _unsplash('photo-1564419320461-6870880221ad')),
  _PhotoRule(['كوكاكولا', 'كوكا كولا', 'بيبسي', 'سفن اب', 'سفن أب',
      'سبرايت', 'فانتا', 'مشروب غازي', 'صودا', 'cola', 'pepsi', 'soda'],
      _unsplash('photo-1581636625402-29b2a704ef13')),
  _PhotoRule(['عصير', 'مانجو عصير', 'عصير برتقال', 'عصائر', 'juice'],
      _unsplash('photo-1613478223719-2ab802602423')),

  // تسالي وحلويات.
  _PhotoRule(['شيبسي', 'شيبس', 'بطاطس شيبسي', 'دوريتوس', 'سناكس',
      'مقرمشات', 'chips', 'crisps'],
      _unsplash('photo-1566478989037-eec170784d0b')),
  _PhotoRule(['بسكويت', 'بسكوت', 'كوكيز', 'cookies', 'biscuits'],
      _unsplash('photo-1499636136210-6f4ee915583e')),
  _PhotoRule(['شكولاتة', 'شوكولاتة', 'شيكولاتة', 'chocolate'],
      _unsplash('photo-1511381939415-e44015466834')),
  _PhotoRule(['كيك', 'كيكة', 'تورتة', 'جاتوه', 'cake'],
      _unsplash('photo-1578985545062-69928b1d9587')),
  _PhotoRule(['عيش', 'خبز', 'رغيف', 'فينو', 'توست', 'مخبوزات', 'bread'],
      _unsplash('photo-1509440159596-0249088772ff')),

  // خضار وفاكهة: الأصناف المحددة قبل صورة الخضار العامة.
  _PhotoRule(['طماطم', 'بندورة', 'tomato'],
      _unsplash('photo-1582284540020-8acbe03f4924')),
  _PhotoRule(['بطاطس', 'بطاطا', 'potato'],
      _unsplash('photo-1518977676601-b53f82aba655')),
  _PhotoRule(['بصل', 'onion'], _unsplash('photo-1508747703725-719777637510')),
  _PhotoRule(['تفاح', 'apple'], _unsplash('photo-1560806887-1e4cd0b6cbd6')),
  _PhotoRule(['موز', 'banana'], _unsplash('photo-1571771894821-ce9b6c11b08e')),
  _PhotoRule(['برتقال', 'يوسفي', 'orange'],
      _unsplash('photo-1547514701-42782101795e')),
  _PhotoRule(['خيار', 'كوسة', 'باذنجان', 'فلفل رومي', 'جزر', 'بامية', 'ملوخية',
      'بسلة', 'خضار', 'خضروات', 'vegetables'],
      _unsplash('photo-1542838132-92c53300491e')),
  _PhotoRule(['فاكهة', 'فاكهه', 'فواكه', 'fruit'],
      _unsplash('photo-1560806887-1e4cd0b6cbd6')),

  // لحوم ومجمدات وأطعمة حيوانية (صور نوعية غير مرتبطة بتغليف).
  _PhotoRule(['فراخ', 'دجاج', 'بانيه', 'صدور فراخ', 'وراك فراخ', 'chicken'],
      _unsplash('photo-1604503468506-a8da13d82791')),
  _PhotoRule(['سمك', 'جمبري', 'سردين', 'فيليه', 'تونة طازة', 'fish'],
      _unsplash('photo-1607623814075-e51df1bdc82f')),
  _PhotoRule(['لحمة', 'لحم', 'لحوم', 'مفروم', 'كفتة', 'ستيك', 'meat', 'steak'],
      _unsplash('photo-1607623814075-e51df1bdc82f')),

  // منظفات وعناية: تمنع ظهور زيت طعام أو صور طعام لمستلزمات البيت.
  _PhotoRule(['صابون غسيل', 'مسحوق غسيل', 'مسحوق', 'برسيل',
      'اريال', 'تايد', 'كلور', 'كلوركس', 'فلاش', 'منظف ارضيات',
      'ديتول', 'سائل مواعين', 'صابون مواعين', 'فيري', 'منظفات',
      'سائل تنظيف', 'detergent', 'cleaner', 'bleach'],
      _unsplash('photo-1585421514738-01798e348b17')),
  _PhotoRule(['شامبو', 'بلسم', 'شاور جل', 'كريم شعر', 'لوشن',
      'معجون اسنان', 'فرشاة اسنان', 'صابون وجه', 'صابون استحمام',
      'صابون', 'عطر', 'برفان', 'مزيل عرق', 'shampoo', 'soap'],
      _unsplash('photo-1608248543803-ba4f8c70ae0b')),
  _PhotoRule(['مناديل', 'مناديل ورق', 'مناديل مبللة', 'حفاضات',
      'بامبرز', 'ورق تواليت', 'محارم', 'tissues', 'diapers'],
      _unsplash('photo-1542838132-92c53300491e')),

  // محلات أخرى.
  _PhotoRule(['ورد', 'زهور', 'بوكيه', 'وردة', 'flowers'],
      _unsplash('photo-1490750967868-88aa4486c946')),
  _PhotoRule(['كشكول', 'كراسة', 'كراسات', 'دفتر', 'قلم', 'اقلام',
      'ادوات مدرسية', 'مكتبة', 'book', 'notebook'],
      _unsplash('photo-1455390582262-044cdead277a')),
  _PhotoRule(['موبايل', 'هاتف', 'تليفون', 'شاحن', 'سماعة',
      'جراب', 'كابل شحن', 'phone', 'charger'],
      _unsplash('photo-1511707171634-5f897ff02aa9')),
  _PhotoRule(['اكل قطط', 'اكل كلاب', 'طعام حيوانات', 'علف', 'pet food'],
      _unsplash('photo-1583337130417-3346a1be7dee')),
];

/// تحميل وتطبيع قواعد الأسماء مرة واحدة بدل إعادة حسابها مع كل كارت منتج.
final _indexedRules = <_IndexedRule>[
  for (final rule in _rules)
    _IndexedRule(
      [for (final word in rule.words) _normalizeProductName(word)],
      rule.url,
    ),
];

final _categoryRules = <_PhotoRule>[
  _PhotoRule(['مطاعم', 'مطعم', 'اكل', 'وجبات', 'كافيه', 'فاست فود'],
      _unsplash('photo-1546069901-ba9599a7e63c')),
  _PhotoRule(['مخبوزات', 'فرن', 'حلويات'], _unsplash('photo-1509440159596-0249088772ff')),
  _PhotoRule(['مشروبات', 'عصائر'], _unsplash('photo-1613478223719-2ab802602423')),
  _PhotoRule(['البان', 'اجبان'], _unsplash('photo-1550583724-b2692b85b150')),
  _PhotoRule(['لحوم', 'جزارة'], _unsplash('photo-1607623814075-e51df1bdc82f')),
  _PhotoRule(['دواجن', 'فراخ'], _unsplash('photo-1604503468506-a8da13d82791')),
  _PhotoRule(['خضار', 'فاكهة', 'فواكه'], _unsplash('photo-1542838132-92c53300491e')),
  _PhotoRule(['عطارة', 'توابل', 'بهارات'], _unsplash('photo-1596040033229-a9821ebd058d')),
  _PhotoRule(['منظفات', 'ادوات منزلية', 'مواد تنظيف'],
      _unsplash('photo-1585421514738-01798e348b17')),
  _PhotoRule(['عناية شخصية', 'مستحضرات تجميل', 'صيدلية', 'صيدليات'],
      _unsplash('photo-1608248543803-ba4f8c70ae0b')),
  _PhotoRule(['مكتبة', 'ادوات مدرسية'], _unsplash('photo-1455390582262-044cdead277a')),
  _PhotoRule(['الكترونيات', 'موبايلات'], _unsplash('photo-1511707171634-5f897ff02aa9')),
  _PhotoRule(['سيارات', 'قطع غيار', 'موتوسيكلات', 'زيوت محركات'],
      _unsplash('photo-1487754180451-c456f719a1fc')),
  _PhotoRule(['زهور', 'ورد'], _unsplash('photo-1490750967868-88aa4486c946')),
  _PhotoRule(['حيوانات', 'مستلزمات حيوانات'], _unsplash('photo-1583337130417-3346a1be7dee')),
];

final _indexedCategoryRules = <_IndexedRule>[
  for (final rule in _categoryRules)
    _IndexedRule(
      [for (final word in rule.words) _normalizeProductName(word)],
      rule.url,
    ),
];

bool _inVehicleStore(String category) =>
    <String>['سيارات', 'قطع غيار', 'موتوسيكلات', 'زيوت محركات']
        .any((word) => _hasPhrase(category, _normalizeProductName(word)));

/// رابط الصورة المعروضة، دون تغيير بيانات المنتج أو عمل أي قراءة إضافية.
/// أسماء العلامات التجارية والأوزان لا تُستخدم للبحث على الإنترنت ولا نعد
/// بصورة العبوة نفسها. عند عدم تطابق الاسم نعرض صورة من نوع المحل.
ProductPhoto productPhotoFor({
  required String name,
  String uploadedUrl = '',
  String storeCategory = '',
}) {
  final uploaded = uploadedUrl.trim();
  if (uploaded.isNotEmpty) return ProductPhoto(uploaded);

  final normalized = _normalizeProductName(name);
  final category = _normalizeProductName(storeCategory);

  // "زيت" لوحدها في محل قطع غيار لا يجب أن تظهر كزيت طعام.
  if (_inVehicleStore(category) && _hasPhrase(normalized, 'زيت')) {
    return ProductPhoto(_unsplash('photo-1487754180451-c456f719a1fc'),
        matchedName: true);
  }

  for (final rule in _indexedRules) {
    if (rule.words.any((word) => _hasPhrase(normalized, word))) {
      return ProductPhoto(rule.url, matchedName: true);
    }
  }
  for (final rule in _indexedCategoryRules) {
    if (rule.words.any((word) => _hasPhrase(category, word))) {
      return ProductPhoto(rule.url);
    }
  }
  // آخر بديل صورة عامة للبقالة، وليست صورة غير موثوقة للصنف.
  return ProductPhoto(_unsplash('photo-1542838132-92c53300491e'));
}
