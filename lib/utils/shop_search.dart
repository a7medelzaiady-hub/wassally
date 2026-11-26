/// بحث محلي بدون استعلامات Firebase: يساوي الهمزات والتشكيل و«الـ»
/// ويفهم أشهر أسماء الأصناف المصرية. لا يرسل النص لأي خدمة خارجية.
String normalizeShopSearch(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
    .replaceAll('أ', 'ا')
    .replaceAll('إ', 'ا')
    .replaceAll('آ', 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp(r'[^a-z0-9\u0621-\u064A]+'), ' ')
    .trim()
    .split(RegExp(r'\s+'))
    .map((word) => word.startsWith('ال') && word.length > 4
        ? word.substring(2)
        : word)
    .join(' ');

const _aliases = <List<String>>[
  ['جبنه', 'جبن', 'cheese'],
  ['لبن', 'حليب', 'milk'],
  ['رز', 'ارز', 'rice'],
  ['مكرونه', 'مكروني', 'pasta'],
  ['شيبسي', 'شيبس', 'chips'],
  ['بيبسي', 'كوكاكولا', 'كولا', 'cola', 'pepsi'],
  ['بندوره', 'طماطم', 'tomato'],
  ['بطاطس', 'بطاطا', 'potato'],
  ['طعميه', 'فلافل', 'falafel'],
  ['سندوتش', 'ساندوتش', 'سندويتش', 'sandwich'],
  ['عصير', 'juice'],
  ['موبيل', 'موبايل', 'هاتف', 'تليفون', 'phone'],
  ['زبادي', 'يوغرت', 'yogurt'],
  ['شوكولاته', 'شيكولاته', 'شكولاته', 'chocolate'],
];

bool matchesShopSearch(String productName, String query) {
  final wanted = normalizeShopSearch(query);
  if (wanted.isEmpty) return true;
  final source = normalizeShopSearch(productName);
  if (source.contains(wanted)) return true;
  final words = source.split(' ');
  final keywords = wanted.split(' ');
  // كل كلمة في البحث لازم تطابق كلمة أو مرادف في اسم الصنف.
  return keywords.every((key) {
    if (words.any((word) => word.startsWith(key))) return true;
    for (final group in _aliases) {
      if (group.any((alias) => alias == key || alias.startsWith(key)) &&
          words.any((word) => group.any((alias) => word == alias))) {
        return true;
      }
    }
    return false;
  });
}
