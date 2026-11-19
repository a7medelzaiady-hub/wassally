import 'package:city_store/services/order_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderGateway.isCatalogMismatch (متى نبطّل نثق في القائمة المجمّعة)', () {
    test('الـ Worker الجديد: الكود هو اللي بيقرر', () {
      expect(
        OrderGateway.isCatalogMismatch(status: 409, code: 'catalog_mismatch', message: 'x'),
        isTrue,
      );
      expect(
        OrderGateway.isCatalogMismatch(status: 409, code: 'other', message: 'سعر أحد الأصناف اتغير'),
        isFalse,
      );
    });

    test('الـ Worker القديم: رسائل السعر/التوفر بس', () {
      for (final m in [
        'سعر أحد الأصناف أو إضافاته اتغير. راجع السلة قبل تأكيد الطلب.',
        'أحد الأصناف لم يعد موجودًا في كتالوج المحل.',
        'أحد الأصناف غير متاح حاليًا.',
      ]) {
        expect(OrderGateway.isCatalogMismatch(status: 409, message: m), isTrue, reason: m);
      }
      for (final m in [
        'المحل مغلق حاليًا.',
        'معرّف الطلب مستخدم بالفعل.',
        'رسوم التوصيل غير مضبوطة في إعدادات الإدارة.',
      ]) {
        expect(OrderGateway.isCatalogMismatch(status: 409, message: m), isFalse, reason: m);
      }
      expect(
        OrderGateway.isCatalogMismatch(status: 503, message: 'سعر أحد الأصناف اتغير'),
        isFalse,
      );
    });

    test('CatalogMismatchError لسه StateError (الشاشات بتعرض رسالته زي الأول)', () {
      expect(CatalogMismatchError('x'), isA<StateError>());
    });
  });
}
