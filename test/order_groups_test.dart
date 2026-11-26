import 'dart:math';

import 'package:city_store/models/order.dart';
import 'package:city_store/models/product.dart';
import 'package:city_store/screens/courier_orders_page.dart';
import 'package:city_store/screens/my_carts_page.dart';
import 'package:city_store/services/cart_book.dart';
import 'package:city_store/services/cart_model.dart';
import 'package:city_store/services/order_status_writer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _rice = Product('رز', 30);
const _chicken = Product('فراخ', 120);
final _groupFormat = RegExp(r'^grp_[A-Za-z0-9]{20}$');

CartBook _bookWithTwoCarts() {
  final book = CartBook(CartModel());
  book.active.add(_rice, storeId: 'g', storeName: 'بقالة الخير');
  book.switchTo('p');
  book.active.add(_chicken, storeId: 'p', storeName: 'دواجن النور');
  return book;
}

void main() {
  group('تجميع الطلبات في «سلّاتي»', () {
    test('مقفول افتراضيًا: الطلبات بتتبعت لوحدها', () {
      final book = _bookWithTwoCarts();
      expect(book.groupingOn, isFalse);
      expect(book.groupIdFor('g'), isNull);
      expect(book.groupCode, isNull);
    });

    test('لما العميل يختار التجميع: رقم واحد بالصيغة الصح ومن غير بيانات العميل', () {
      final book = _bookWithTwoCarts()..setGrouping(true, random: Random(7));
      final id = book.groupIdFor('g');
      expect(id, matches(_groupFormat));
      expect(book.groupIdFor('p'), id);
      expect(book.groupCode, id!.substring(id.length - 6).toUpperCase());
    });

    test('المحل اللي اتطلب منه ما يتكررش في نفس المجموعة', () {
      final book = _bookWithTwoCarts()..setGrouping(true);
      book.markGroupedOrder('g');
      expect(book.groupIdFor('g'), isNull);
      expect(book.groupIdFor('p'), isNotNull);
    });

    test('أقصى 5 طلبات، وبعد المدة الطلب يتبعت لوحده', () {
      final book = _bookWithTwoCarts()..setGrouping(true);
      for (var i = 0; i < CartBook.groupMaxOrders; i++) {
        book.markGroupedOrder('s$i');
      }
      expect(book.groupIdFor('new-store'), isNull);

      final fresh = _bookWithTwoCarts()..setGrouping(true);
      final later = DateTime.now().add(const Duration(hours: 6));
      expect(fresh.groupIdFor('g', now: later), isNull);
    });

    test('التجميع بيخلص لوحده لما كل السلات تتأكد أو تتمسح، ومع تسجيل الخروج', () {
      final book = _bookWithTwoCarts()..setGrouping(true);
      book.removeParked('g');
      expect(book.groupingOn, isTrue); // لسه فيه سلة
      book.active.clear();
      expect(book.groupingOn, isFalse);

      final other = _bookWithTwoCarts()..setGrouping(true);
      other.clearAll();
      expect(other.groupingOn, isFalse);
    });

    test('قفل التجميع يدويًا', () {
      final book = _bookWithTwoCarts()..setGrouping(true);
      book.setGrouping(false);
      expect(book.groupIdFor('g'), isNull);
    });
  });

  group('كود التجميع عند المندوب', () {
    test('الطلب بيقرا groupCode، والطلب القديم من غير كود', () {
      final grouped = AppOrder.fromMap('o1', {'storeName': 'S', 'items': [], 'status': 'preparing', 'groupCode': 'OPQR12'});
      final plain = AppOrder.fromMap('o2', {'storeName': 'S', 'items': [], 'status': 'preparing'});
      expect(grouped.groupCode, 'OPQR12');
      expect(plain.groupCode, '');
    });

    test('نسخة قايمة المناديب فيها الكود بس، من غير groupId ولا بيانات العميل', () {
      final feed = OrderStatusWriter.feedData({
        'storeId': 's1', 'storeName': 'S', 'items': [], 'subtotal': 10, 'deliveryFee': 20, 'total': 35,
        'groupId': 'grp_AbCdEfGhIjKlMnOpQr12', 'groupCode': 'OPQR12',
        'userId': 'cust1', 'customerName': 'Ali',
      });
      expect(feed['groupCode'], 'OPQR12');
      for (final key in ['groupId', 'userId', 'customerName']) {
        expect(feed.containsKey(key), isFalse, reason: key);
      }
      expect(OrderStatusWriter.feedData({'storeId': 's1', 'items': []}).containsKey('groupCode'), isFalse);
    });

    testWidgets('شارة المجموعة بتظهر الكود', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GroupCodeBadge(code: 'OPQR12'))));
      expect(find.text('مجموعة #OPQR12'), findsOneWidget);
    });
  });

  group('اختيار التجميع في صفحة «سلّاتي»', () {
    Future<void> pump(WidgetTester tester, CartBook book, {required bool allow}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: MyCartsPage(book: book, allowGrouping: allow)));
      await tester.pumpAndSettle();
    }

    testWidgets('يظهر مع سلتين وبوابة الطلبات، والضغط بيشغّله', (tester) async {
      final book = _bookWithTwoCarts();
      await pump(tester, book, allow: true);
      expect(find.byKey(const Key('carts-group-switch')), findsOneWidget);
      await tester.tap(find.byKey(const Key('carts-group-switch')));
      await tester.pumpAndSettle();
      expect(book.groupingOn, isTrue);
      // رقم المجموعة للمندوب بس، مش بيظهر للعميل في «سلّاتي».
      expect(find.textContaining('مفعّل'), findsOneWidget);
      expect(find.textContaining('#${book.groupCode}'), findsNothing);
    });

    testWidgets('ما يظهرش من غير بوابة الطلبات أو مع سلة واحدة', (tester) async {
      await pump(tester, _bookWithTwoCarts(), allow: false);
      expect(find.byKey(const Key('carts-group-switch')), findsNothing);

      final single = CartBook(CartModel())..active.add(_rice, storeId: 'g', storeName: 'بقالة الخير');
      await pump(tester, single, allow: true);
      expect(find.byKey(const Key('carts-group-switch')), findsNothing);
    });
  });
}
