import 'dart:convert';

import 'package:http/http.dart' as http;

/// بحث يدوي محدود عن صور توضيحية بترخيص CC0 عبر Openverse، بدون مفتاح API.
/// لا يُستدعى أثناء كتابة اسم الصنف أو تصفح العميل، ولا يقرأ Firestore.
/// الصور نتائج بحث وليست إثباتًا لمطابقة العبوة أو العلامة التجارية.
class StockPhotoCandidate {
  final String id;
  final String previewUrl;
  final String sourcePageUrl;
  final String title;
  final String creator;

  const StockPhotoCandidate({
    required this.id,
    required this.previewUrl,
    required this.sourcePageUrl,
    required this.title,
    required this.creator,
  });
}

class _CachedSearch {
  final DateTime fetchedAt;
  final List<StockPhotoCandidate> results;
  const _CachedSearch(this.fetchedAt, this.results);
}

class StockPhotoSearch {
  StockPhotoSearch._();

  static const cacheFor = Duration(hours: 24);
  static const maxResults = 9;
  static final Map<String, _CachedSearch> _cache = {};
 
  /// اقتراح بحث بالإنجليزي لأسماء الأصناف المصرية الشائعة. المعاينة فقط؛
  /// الاسم والسعر والعلامة التجارية في الكتالوج لا تتغير.
  /// التركيبات الخاصة قبل الكلمات العامة لتقليل الصور غير المناسبة.
  static String suggestedQuery(String productName) {
    final name = productName.toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
        .replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا')
        .replaceAll(RegExp(r'[^a-z0-9\u0621-\u064A]+'), ' ').trim();
    const terms = <String, String>{
      'زيت موتور': 'motor engine oil bottle',
      'زيت محرك': 'motor engine oil bottle',
      'لبن بودره': 'powdered milk package',
      'بطاطس مقليه': 'french fries food',
      'عصير برتقال': 'orange juice glass',
      'مسحوق غسيل': 'laundry detergent',
      'زيت شعر': 'hair oil bottle',
      'بيبسي': 'soda drink bottle',
      'كوكا كولا': 'soda drink bottle',
      'شيبسي': 'potato chips snacks',
      'لبن': 'milk carton',
      'حليب': 'milk carton',
      'بيض': 'chicken eggs',
      'جبنه': 'cheese',
      'جبنة': 'cheese',
      'طماطم': 'tomatoes',
      'بطاطس': 'potato vegetables',
      'موز': 'bananas',
      'تفاح': 'apples',
      'برتقال': 'oranges',
      'بصل': 'onions',
      'رز': 'rice grains',
      'ارز': 'rice grains',
      'سكر': 'sugar',
      'قهوه': 'coffee beans',
      'قهوة': 'coffee beans',
      'شاي': 'tea leaves',
      'عيش': 'bread loaf',
      'خبز': 'bread loaf',
      'فراخ': 'chicken meat',
      'دجاج': 'chicken meat',
      'بيتزا': 'pizza',
      'برجر': 'hamburger',
      'شاورما': 'shawarma sandwich',
      'مناديل': 'tissue paper',
      'صابون': 'soap bar',
    };
    final padded = ' $name ';
    for (final term in terms.entries) {
      if (padded.contains(' ${term.key} ')) return term.value;
    }
    return productName.trim();
  }

  /// تُنفّذ فقط بعد ضغط المستخدم «ابحث عن صورة»؛ ليس مع كل ضغطة حرف.
  static Future<List<StockPhotoCandidate>> search(
    String text, {
    http.Client? client,
  }) async {
    final term = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (term.length < 2 || term.length > 90) {
      throw const FormatException('اكتب اسم صنف أو وصف بحث من حرفين إلى 90 حرفًا.');
    }
    final key = term.toLowerCase();
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < cacheFor) {
      return cached.results;
    }
    // Openverse مفتوح بدون API key. فلتر CC0 على الخادم ثم تحقّق محليًا مرة أخرى.
    final uri = Uri.https('api.openverse.org', '/v1/images/', {
      'q': term,
      'license': 'cc0',
      'category': 'photograph',
      'page_size': '$maxResults',
    });
    final response = await (client == null ? http.get(uri) : client.get(uri))
        .timeout(const Duration(seconds: 16));
    if (response.statusCode != 200) {
      throw StateError('خدمة البحث عن الصور غير متاحة الآن (${response.statusCode}).');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final results = parseResults(decoded);
    // حد أقصى 40 مدخلاً في كاش ذاكرة الموبايل. بدون Firebase أو تخزين نتائج كبير.
    if (_cache.length >= 40) _cache.remove(_cache.keys.first);
    _cache[key] = _CachedSearch(DateTime.now(), results);
    return results;
  }

  static List<StockPhotoCandidate> parseResults(Object? data) {
    if (data is! Map || data['results'] is! List) return const [];
    final list = <StockPhotoCandidate>[];
    final seen = <String>{};
    for (final raw in data['results'] as List) {
      if (raw is! Map) continue;
      if ((raw['license'] ?? '').toString().toLowerCase() != 'cc0' ||
          raw['mature'] == true) continue;
      final id = (raw['id'] ?? '').toString();
      final preview = (raw['thumbnail'] ?? '').toString();
      final page = (raw['foreign_landing_url'] ?? '').toString();
      if (id.isEmpty || !seen.add(id) ||
          !isPublicHttpsPhotoUrl(preview) || !isPublicHttpsPhotoUrl(page)) continue;
      list.add(StockPhotoCandidate(
        id: id,
        previewUrl: preview,
        sourcePageUrl: page,
        title: (raw['title'] ?? '').toString(),
        creator: (raw['creator'] ?? '').toString(),
      ));
      if (list.length >= maxResults) break;
    }
    return List.unmodifiable(list);
  }

  /// نرفض الروابط الداخلية وعناوين IP بدل السماح بمسارات محلية أو http.
  static bool isPublicHttpsPhotoUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasPort || uri.host.length > 253) return false;
    final host = uri.host.toLowerCase();
    if (!host.contains('.') || host == 'localhost' ||
        host.endsWith('.localhost') || host.endsWith('.local') ||
        RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host) ||
        host.contains(':')) return false;
    return true;
  }

  static void clearCacheForTesting() => _cache.clear();
}
