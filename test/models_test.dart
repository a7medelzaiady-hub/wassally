import 'package:city_store/models/order.dart';
import 'package:city_store/models/store.dart';
import 'package:city_store/utils/format.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Store.fromMap', () {
    test('بيقرأ البيانات الكاملة', () {
      final s = Store.fromMap('x', {
        'name': 'مطعم',
        'category': 'مطاعم',
        'icon': 'restaurant',
        'color': 0xFFF75A07,
        'rating': 4.5,
        'time': '20-30 د',
        'order': 2,
        'products': [
          {'name': 'فول', 'price': 8},
          {'name': 'طعمية', 'price': '6.5'},
        ],
      });
      expect(s.name, 'مطعم');
      expect(s.products.length, 2);
      expect(s.products[1].price, 6.5);
      expect(s.order, 2);
      expect(s.active, isTrue);
    });

    test('بيستحمل بيانات ناقصة', () {
      final s = Store.fromMap('y', {});
      expect(s.name, '');
      expect(s.category, 'أخرى');
      expect(s.products, isEmpty);
    });
  });

  group('OrderStatus', () {
    test('parse بيرجع الحالة الصح والافتراضي new', () {
      expect(OrderStatus.parse('delivered'), OrderStatus.delivered);
      expect(OrderStatus.parse('on_the_way'), OrderStatus.onTheWay);
      expect(OrderStatus.parse('???'), OrderStatus.newOrder);
      expect(OrderStatus.parse(null), OrderStatus.newOrder);
    });
  });

  group('AppOrder.fromMap', () {
    test('بيحوّل الطلب بالمنتجات والتاريخ', () {
      final date = DateTime(2026, 11, 3, 16, 5);
      final o = AppOrder.fromMap('abc123', {
        'storeName': 'سوبر',
        'items': [
          {'name': 'أرز', 'price': 35, 'qty': 2},
        ],
        'subtotal': 70,
        'deliveryFee': 10,
        'total': 80,
        'status': 'preparing',
        'createdAt': Timestamp.fromDate(date),
      });
      expect(o.items.single.total, 70);
      expect(o.total, 80);
      expect(o.status, OrderStatus.preparing);
      expect(o.createdAt, date);
    });
  });

  group('format', () {
    test('formatPrice', () {
      expect(formatPrice(35), '35 ج.م');
      expect(formatPrice(12.5), '12.5 ج.م');
    });

    test('formatDateTime', () {
      expect(formatDateTime(DateTime(2026, 11, 3, 16, 5)), '03/11/2026 - 4:05 م');
      expect(formatDateTime(DateTime(2026, 1, 9, 0, 7)), '09/01/2026 - 12:07 ص');
    });

    test('shortOrderId', () {
      expect(shortOrderId('abcdefgh'), '#ABCDE');
      expect(shortOrderId('ab'), '#AB');
    });

    test('isValidEgyptianMobile', () {
      expect(isValidEgyptianMobile('01012345678'), isTrue);
      expect(isValidEgyptianMobile('010 1234 5678'), isTrue);
      expect(isValidEgyptianMobile('01312345678'), isFalse);
      expect(isValidEgyptianMobile('0101234'), isFalse);
    });
  });
}
