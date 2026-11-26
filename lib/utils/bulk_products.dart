import 'product_autofill.dart';

/// سطر من قايمة أصناف ملصوقة (اسم + سعر)، بعد التقسيم والتنضيف.
class BulkProductLine {
  final String name;
  final double price;

  /// اقتراح التفاصيل من القاموس (ممكن يبقى null).
  final ProductSuggestion? suggestion;

  /// تنبيه لو السعر شكله غلط (null = تمام).
  final String? priceWarning;

  const BulkProductLine(this.name, this.price, {this.suggestion, this.priceWarning});

  String get description => suggestion?.description ?? '';
}

/// نتيجة تقسيم القايمة: الأصناف الصالحة + السطور اللي ما اتفهمتش.
class BulkParseResult {
  final List<BulkProductLine> lines;
  final List<String> skipped;
  const BulkParseResult(this.lines, this.skipped);
}

const int kBulkMaxLines = 300;

const _arabicDigits = {
  '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
  '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9', '٫': '.',
};

String _westernDigits(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(_arabicDigits[ch] ?? ch);
  }
  return b.toString();
}

final _number = RegExp(r'\d+(?:[.,]\d{1,2})?');

// كلمات حوالين السعر بتتشال من الاسم: «ج»، «جنيه»، «ج.م»، «بـ»، «السعر»...
final _priceWords = RegExp(
  r'(?:^|\s)(?:ج\.?م\.?|جنيه(?:ات)?|جم|ج|ل\.?م|egp|le|السعر|سعر|بـ|ب)(?=\s|$)',
  caseSensitive: false,
);

/// بيقسم نص ملصوق (سطر لكل صنف) لأصناف. بيفهم:
/// «طماطم 15»، «طماطم - 15 ج»، «طماطم: ١٥»، «15 طماطم»، «طماطم الكيلو بـ15»، «زيت 1.5 لتر 95».
/// السعر = آخر رقم في السطر (أو أول رقم لو السطر بيبدأ برقم).
BulkParseResult parseBulkProducts(String text) {
  final lines = <BulkProductLine>[];
  final skipped = <String>[];
  final seen = <String>{};
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final original = raw.trim();
    if (original.isEmpty) continue;
    if (lines.length >= kBulkMaxLines) {
      skipped.add(original);
      continue;
    }
    final line = _westernDigits(original)
        .replaceAll(RegExp(r'[‎‏؜]'), '')
        .replaceAll('بـ', ' بـ ');
    final matches = _number.allMatches(line).toList();
    if (matches.isEmpty) {
      skipped.add(original);
      continue;
    }
    final startsWithNumber = line.trimLeft().startsWith(matches.first.group(0)!) &&
        matches.length == 1;
    final priceMatch = startsWithNumber ? matches.first : matches.last;
    final price = double.tryParse(priceMatch.group(0)!.replaceAll(',', '.'));
    var name = (line.substring(0, priceMatch.start) + ' ' + line.substring(priceMatch.end))
        .replaceAll(RegExp(r'[\-–—:=|*•،,]+'), ' ')
        .replaceAll(_priceWords, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (price == null || price <= 0 || price > 20000 || name.isEmpty || name.length > 120) {
      skipped.add(original);
      continue;
    }
    // نفس الاسم مرتين: أول مرة بس.
    if (!seen.add(name)) {
      skipped.add(original);
      continue;
    }
    final suggestion = suggestProduct(name);
    lines.add(BulkProductLine(
      name,
      price,
      suggestion: suggestion,
      priceWarning: priceWarningFor(name, price, suggestion: suggestion),
    ));
  }
  return BulkParseResult(lines, skipped);
}

/// أقصى سعر «طبيعي» لكل قسم (بالجنيه). أعلى منه = تنبيه «متأكد؟» مش منع.
const _maxNormalPrice = <String, double>{
  'خضار': 200,
  'فاكهة': 400,
  'مخبوزات': 100,
  'حلويات ومخبوزات': 1500,
  'ألبان': 800,
  'ألبان وبيض': 400,
  'مشروبات': 300,
  'مشروبات ساخنة': 300,
  'سندوتشات': 400,
  'أكل': 1500,
  'لحوم ودواجن': 1500,
  'أسماك': 2500,
  'بقالة': 1500,
  'توابل': 500,
  'سناكس': 300,
  'منظفات': 1500,
  'عناية شخصية': 2000,
};

/// تنبيه لو السعر شكله غلط (زي «طماطم 1500» بدل «15»). null = مفيش تنبيه.
/// [previousPrice]: السعر القديم وقت التعديل؛ زيادة أكتر من 5 أضعاف = تنبيه.
String? priceWarningFor(
  String name,
  double price, {
  ProductSuggestion? suggestion,
  double? previousPrice,
}) {
  if (previousPrice != null && previousPrice > 0 && price >= previousPrice * 5) {
    return 'السعر الجديد أكبر من القديم (${_fmt(previousPrice)}) بأكتر من 5 مرات.';
  }
  final s = suggestion ?? suggestProduct(name);
  if (s == null) return null;
  final max = _maxNormalPrice[s.section];
  if (max != null && price > max) {
    return 'سعر كبير على ${s.section} (${_fmt(price)} ج.م). يمكن فيه صفر زيادة؟';
  }
  return null;
}

String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
