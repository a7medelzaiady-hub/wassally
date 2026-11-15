import 'package:city_store/models/order.dart';
import 'package:city_store/models/product.dart';
import 'package:city_store/models/store.dart';
import 'package:city_store/services/price_check.dart';
import 'package:flutter_test/flutter_test.dart';

Store _store() => Store.fromMap('s1', {
      'name': 'مطعم',
      'products': [
        {'name': 'فول', 'price': 8},
        {'name': 'طعمية', 'price': 6.5},
      ],
    });

AppOrder _order(List<OrderLine> items, double total) => AppOrder(
      id: 'o1',
      storeName: 'مطعم',
      items: items,
      subtotal: total - 10,
      deliveryFee: 10,
      total: total,
      status: OrderStatus.newOrder,
      createdAt: null,
      address: '',
      phone: '',
      notes: '',
      storeId: 's1',
    );

void main() {
  group('checkOrderPrices', () {
    test('أسعار مطابقة للكتالوج', () {
      // 2 فول (16) + 2 طعمية (13) + توصيل 10 = 39
      final o = _order([
        const OrderLine('فول', 8, 2),
        const OrderLine('طعمية', 6.5, 2),
      ], 39);
      final r = checkOrderPrices(o, _store());
      expect(r.status, PriceCheckStatus.match);
      expect(r.expectedTotal, 39);
      expect(r.issues, isEmpty);
    });

    test('عميل غيّر السعر: بيطلع فرق والإجمالي الصحيح من الكتالوج', () {
      final o = _order([const OrderLine('فول', 0.5, 10)], 15);
      final r = checkOrderPrices(o, _store());
      expect(r.status, PriceCheckStatus.mismatch);
      expect(r.expectedTotal, 90); // 10 × 8 + 10
      expect(r.issues.single.name, 'فول');
      expect(r.issues.single.catalogPrice, 8);
    });

    test('إجمالي غلط مع أسعار أصناف صح بيعتبر فرق', () {
      final o = _order([const OrderLine('فول', 8, 1)], 12);
      final r = checkOrderPrices(o, _store());
      expect(r.status, PriceCheckStatus.mismatch);
      expect(r.expectedTotal, 18);
    });

    test('صنف مش موجود في الكتالوج = unknown', () {
      final o = _order([const OrderLine('صنف قديم', 5, 1)], 15);
      final r = checkOrderPrices(o, _store());
      expect(r.status, PriceCheckStatus.unknown);
      expect(r.issues.single.missing, isTrue);
    });

    test('أصناف النظام الجديد (extraProducts) بتتحسب', () {
      final store = Store.fromMap('s2', {'name': 'محل'}); // من غير مصفوفة أصناف
      final o = _order([const OrderLine('عصير', 12, 2)], 34);
      final r = checkOrderPrices(
        o,
        store,
        extraProducts: const [Product('عصير', 12)],
      );
      expect(r.status, PriceCheckStatus.match);
      expect(r.expectedTotal, 34);
    });

    test('محل مش موجود = unknown', () {
      final o = _order([const OrderLine('فول', 8, 1)], 18);
      expect(checkOrderPrices(o, null).status, PriceCheckStatus.unknown);
    });
  });

  group('AppOrder.payable', () {
    test('بيرجّع الإجمالي المعتمد لو موجود وإلا الإجمالي الأصلي', () {
      final plain = _order([const OrderLine('فول', 8, 1)], 18);
      expect(plain.isVerified, isFalse);
      expect(plain.payable, 18);

      final verified = AppOrder.fromMap('o2', {
        'total': 15,
        'verifiedTotal': 90,
        'storeId': 's1',
      });
      expect(verified.isVerified, isTrue);
      expect(verified.payable, 90);
      expect(verified.storeId, 's1');
    });
  });
}
