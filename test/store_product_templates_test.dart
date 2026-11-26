import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/utils/store_product_templates.dart';

void main() {
  group('offline owner product templates', () {
    test('templates cover everyday Egyptian stores and remain price-free', () {
      expect(storeProductTemplates.length, greaterThanOrEqualTo(6));
      final grocery = storeProductTemplates.firstWhere(
          (t) => t.label.contains('بقالة'));
      expect(grocery.products, contains('سكر 1 كيلو'));
      expect(grocery.products, contains('لبن 1 لتر'));
      expect(storeProductTemplates.expand((e) => e.products).length,
          greaterThanOrEqualTo(65));
    });

    test('each template has unique product names', () {
      for (final t in storeProductTemplates) {
        expect(t.products.length,
            t.products.map(normalizeProductKey).toSet().length,
            reason: t.label);
      }
    });

    test('duplicate checker ignores common spellings and spacing', () {
      expect(normalizeProductKey('  الأَرُز  المصري '),
          normalizeProductKey('الارز المصري'));
      expect(normalizeProductKey('جبنة - رومي'),
          normalizeProductKey('جبنه  رومي'));
      expect(normalizeProductKey('شاي  أخضر'),
          normalizeProductKey('شاي اخضر'));
      expect(normalizeProductKey('الجبنة الرومي'),
          normalizeProductKey('جبنه رومي'));
      expect(normalizeProductKey('الأرز المصري'),
          normalizeProductKey('ارز مصري'));
    });

    test('percentage prices round safely', () {
      expect(adjustedProductPrice(100, 10), 110);
      expect(adjustedProductPrice(100, -5), 95);
      expect(adjustedProductPrice(7.25, 10), 7.98);
    });
  });
}
