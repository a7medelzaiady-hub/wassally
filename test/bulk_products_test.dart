import 'package:city_store/utils/bulk_products.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('تقسيم قايمة الأصناف الملصوقة', () {
    test('بيفهم الأشكال الشائعة للكتابة', () {
      final r = parseBulkProducts('''
طماطم 15
خيار - 10 ج
بصل: ١٢
15 بطاطس
ليمون الكيلو بـ30
زيت 1.5 لتر 95
عيش بلدي = 2 جنيه
جبنة رومي ٢٥٠ ج.م
بيبسي كانز 15ج
''');
      expect(r.skipped, isEmpty);
      expect(
        r.lines.map((l) => '${l.name}|${l.price}').toList(),
        [
          'طماطم|15.0',
          'خيار|10.0',
          'بصل|12.0',
          'بطاطس|15.0',
          'ليمون الكيلو|30.0',
          'زيت 1.5 لتر|95.0',
          'عيش بلدي|2.0',
          'جبنة رومي|250.0',
          'بيبسي كانز|15.0',
        ],
      );
      expect(r.lines.first.description, 'طماطم طازة بالكيلو');
    });

    test('السطور من غير سعر أو المكررة بتتجاهل وتتعرض للمراجعة', () {
      final r = parseBulkProducts('قايمة الأسعار\nطماطم 15\nطماطم 16\n\nبصل 0');
      expect(r.lines.map((l) => l.name), ['طماطم']);
      expect(r.skipped, ['قايمة الأسعار', 'طماطم 16', 'بصل 0']);
    });

    test('حد أقصى للسطور', () {
      final text = List.generate(kBulkMaxLines + 5, (i) => 'صنف رقم$i ${i + 1}').join('\n');
      final r = parseBulkProducts(text);
      expect(r.lines.length, kBulkMaxLines);
      expect(r.skipped.length, 5);
    });
  });

  group('تنبيه السعر الغريب', () {
    test('سعر كبير على قسم معروف = تنبيه', () {
      expect(priceWarningFor('طماطم', 1500), isNotNull);
      expect(priceWarningFor('طماطم', 15), isNull);
    });

    test('صنف مش معروف أو قسم غالي طبيعي = مفيش تنبيه', () {
      expect(priceWarningFor('صنف غريب', 9000), isNull);
      expect(priceWarningFor('زيت موتور 4 لتر', 1500), isNull);
    });

    test('زيادة 5 أضعاف عن السعر القديم = تنبيه', () {
      expect(priceWarningFor('صنف غريب', 500, previousPrice: 50), isNotNull);
      expect(priceWarningFor('صنف غريب', 60, previousPrice: 50), isNull);
    });

    test('القايمة الملصوقة بتعلّم الأسعار الغريبة', () {
      final r = parseBulkProducts('طماطم 1500\nخيار 10');
      expect(r.lines.first.priceWarning, isNotNull);
      expect(r.lines.last.priceWarning, isNull);
    });
  });
}
