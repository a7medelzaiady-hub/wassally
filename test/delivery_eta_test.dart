import 'package:city_store/models/order.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:city_store/utils/delivery_eta.dart';
import 'package:city_store/widgets/delivery_eta_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 11, 27, 18, 0);

AppOrder _order(OrderStatus status, {DateTime? pickedUpAt, DateTime? arrivedAt}) => AppOrder(
      id: 'o1',
      storeId: 'shop1',
      storeName: 'محل',
      items: const [OrderLine('لبن', 30, 1)],
      subtotal: 30,
      deliveryFee: 15,
      total: 45,
      status: status,
      createdAt: _t0,
      address: '',
      phone: '',
      notes: '',
      pickedUpAt: pickedUpAt,
      courierArrivedAt: arrivedAt,
    );

void main() {
  group('فهم وقت المحل', () {
    test('الصيغ المعتادة', () {
      expect(parseStoreEta('25-35 د'), (min: 25, max: 35));
      expect(parseStoreEta('٢٥ - ٣٥ دقيقة'), (min: 25, max: 35));
      expect(parseStoreEta('20–30'), (min: 20, max: 30));
      expect(parseStoreEta('35-25'), (min: 25, max: 35));
      expect(parseStoreEta('30'), (min: 30, max: 40));
    });

    test('مش مفهوم أو برا الحدود = التقدير العام', () {
      expect(parseStoreEta(''), isNull);
      expect(parseStoreEta('سريع'), isNull);
      expect(parseStoreEta('1-2'), isNull);
      expect(parseStoreEta('10-500'), isNull);
      expect(parseStoreEta('10-20-30'), isNull);
      expect(storeEtaOrDefault(null), kDefaultStoreEta);
      expect(storeEtaOrDefault('مش عارف'), kDefaultStoreEta);
    });

    test('النص', () {
      expect(etaRangeText((min: 25, max: 35)), '25–35 دقيقة');
      expect(etaWindowText(DateTime(2026, 1, 1, 18, 25), DateTime(2026, 1, 1, 18, 40)), 'بين 6:25 و 6:40 م');
      expect(etaWindowText(DateTime(2026, 1, 1, 11, 50), DateTime(2026, 1, 1, 12, 5)), 'بين 11:50 ص و 12:05 م');
    });
  });

  group('الوقت المتوقع حسب حالة الطلب', () {
    const store = (min: 25, max: 35);

    test('جديد (المحل لسه ما أكدش): مفيش تقدير', () {
      expect(deliveryEtaFor(_order(OrderStatus.newOrder), store, _t0), isNull);
    });

    test('بيجهّز: من وقت الطلب + وقت المحل', () {
      final eta = deliveryEtaFor(_order(OrderStatus.preparing), store, _t0.add(const Duration(minutes: 5)))!;
      expect(eta.from, _t0.add(const Duration(minutes: 25)));
      expect(eta.to, _t0.add(const Duration(minutes: 35)));
      expect(eta.overdue, isFalse);
    });

    test('في الطريق: من وقت استلام المندوب + مشوار الحي', () {
      final picked = _t0.add(const Duration(minutes: 20));
      final eta = deliveryEtaFor(_order(OrderStatus.onTheWay, pickedUpAt: picked), store, picked)!;
      expect(eta.from, picked.add(const Duration(minutes: 10)));
      expect(eta.to, picked.add(const Duration(minutes: 20)));
    });

    test('عدّى الوقت المتوقع: متأخر', () {
      final eta = deliveryEtaFor(_order(OrderStatus.preparing), store, _t0.add(const Duration(minutes: 50)))!;
      expect(eta.overdue, isTrue);
    });

    test('المندوب وصل أو الطلب خلص: مفيش تقدير', () {
      expect(deliveryEtaFor(_order(OrderStatus.onTheWay, arrivedAt: _t0), store, _t0), isNull);
      expect(deliveryEtaFor(_order(OrderStatus.delivered), store, _t0), isNull);
      expect(deliveryEtaFor(_order(OrderStatus.cancelled), store, _t0), isNull);
    });
  });

  group('سطر الوقت المتوقع في تفاصيل الطلب', () {
    Future<void> pump(WidgetTester tester, AppOrder order, DateTime now) => tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: OrderEtaLine(order: order, clock: () => now, storeEtaOverride: (min: 25, max: 35)),
            ),
          ),
        ));

    testWidgets('بيجهّز: متوقع يوصلك بين...', (tester) async {
      await pump(tester, _order(OrderStatus.preparing), _t0.add(const Duration(minutes: 3)));
      expect(find.byKey(const Key('order-eta')), findsOneWidget);
      expect(find.textContaining('متوقع يوصلك بين 6:25 و 6:35 م'), findsOneWidget);
    });

    testWidgets('اتأخر: رسالة هادية', (tester) async {
      await pump(tester, _order(OrderStatus.preparing), _t0.add(const Duration(minutes: 60)));
      expect(find.byKey(const Key('order-eta-overdue')), findsOneWidget);
    });

    testWidgets('جديد: مفيش سطر', (tester) async {
      await pump(tester, _order(OrderStatus.newOrder), _t0);
      expect(find.byKey(const Key('order-eta')), findsNothing);
      expect(find.byKey(const Key('order-eta-overdue')), findsNothing);
    });
  });
}
