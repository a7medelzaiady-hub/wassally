import 'package:city_store/screens/info_pages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeWhatsAppNumber', () {
    test('رقم مصري بصفر في الأول يتحول للصيغة الدولية', () {
      expect(normalizeWhatsAppNumber('01000197222'), '201000197222');
    });
    test('مسافات وشرط و+ بتتشال', () {
      expect(normalizeWhatsAppNumber('+20 100-019-7222'), '201000197222');
      expect(normalizeWhatsAppNumber('0020 1000197222'), '201000197222');
    });
    test('رقم دولي جاهز يفضل زي ما هو', () {
      expect(normalizeWhatsAppNumber('201000197222'), '201000197222');
    });
    test('فاضي (مستند contact مش موجود) يرجع الرقم الافتراضي بدل صفحة فاضية', () {
      expect(normalizeWhatsAppNumber(''), '201000197222');
      expect(normalizeWhatsAppNumber('  '), '201000197222');
      expect(kDefaultSupportWhatsApp, isNotEmpty);
    });
  });
}
