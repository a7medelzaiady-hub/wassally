import 'package:city_store/utils/product_autofill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('اقتراح تفاصيل الصنف من اسمه', () {
    test('خضار بالكيلو', () {
      final s = suggestProduct('طماطم بلدي')!;
      expect(s.unit, 'كيلو');
      expect(s.section, 'خضار');
      expect(s.description, 'طماطم بلدي طازة بالكيلو');
      expect(s.optionGroups, isEmpty);
    });

    test('بيتعامل مع التشكيل والهمزات والتاء المربوطة و«ال»', () {
      expect(suggestProduct('الجِبنة الرومي')!.section, 'ألبان');
      expect(suggestProduct('قهوة تركي')!.optionGroups.single.title, 'السكر');
    });

    test('الأدق قبل الأعم', () {
      expect(suggestProduct('زيت موتور 4 لتر')!.section, 'زيوت وقطع غيار');
      expect(suggestProduct('زيت عباد الشمس')!.section, 'بقالة');
      expect(suggestProduct('شاي ناعم العروسة')!.optionGroups, isEmpty);
      expect(suggestProduct('فلفل اسود مطحون')!.section, 'توابل');
      expect(suggestProduct('بطاطس')!.section, 'خضار');
    });

    test('كلمة كاملة بس: «بن» ما تطابقش «بنادول»', () {
      expect(suggestProduct('بنادول اكسترا')!.section, 'صيدلية');
      expect(suggestProduct('خلطة سحرية'), isNull);
    });

    test('اسم مش معروف أو قصير = مفيش اقتراح', () {
      expect(suggestProduct('صنف غريب جدا'), isNull);
      expect(suggestProduct('a'), isNull);
      expect(suggestProduct(''), isNull);
    });
  });
}
