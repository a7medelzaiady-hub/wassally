import 'package:city_store/models/order.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:city_store/utils/store_wait.dart';
import 'package:city_store/widgets/store_wait_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _sent = DateTime(2026, 11, 27, 18, 0);

AppOrder _order({
  OrderStatus status = OrderStatus.newOrder,
  DateTime? createdAt,
  List<String> unavailable = const [],
}) =>
    AppOrder(
      id: 'abcdef123456',
      storeName: 'سوبر ماركت النور',
      items: const [OrderLine('لبن', 30, 1)],
      subtotal: 30,
      deliveryFee: 15,
      total: 45,
      status: status,
      createdAt: createdAt ?? _sent,
      address: 'شارع الجمهورية',
      phone: '01000000000',
      notes: '',
      unavailableItems: unavailable,
    );

Widget _app(AppOrder order, DateTime now) => MaterialApp(
      theme: buildAppTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: StoreWaitBanner(order: order, clock: () => now)),
      ),
    );

void main() {
  group('حالة انتظار تأكيد المحل (من غير قراءات)', () {
    StoreWaitStage stage(AppOrder o, Duration after) =>
        storeWaitStageOf(o, _sent.add(after));

    test('طلب جديد لسه في الوقت الطبيعي = مستني', () {
      expect(stage(_order(), const Duration(minutes: 2)), StoreWaitStage.waiting);
    });

    test('بعد 5 دقايق من غير تأكيد = متأخر (نفس حد تنبيه الإدارة)', () {
      expect(kStoreReplyGrace, const Duration(minutes: 5));
      expect(stage(_order(), const Duration(minutes: 5)), StoreWaitStage.late);
      expect(stage(_order(), const Duration(minutes: 40)), StoreWaitStage.late);
    });

    test('المحل بدأ يجهّز أو الطلب خلص = مفيش انتظار', () {
      for (final s in [
        OrderStatus.preparing,
        OrderStatus.onTheWay,
        OrderStatus.delivered,
        OrderStatus.cancelled,
      ]) {
        expect(stage(_order(status: s), const Duration(minutes: 30)), StoreWaitStage.none);
      }
    });

    test('المحل علّم أصناف مش متاحة = رد فعلًا، مفيش شريط انتظار', () {
      expect(
        stage(_order(unavailable: const ['لبن']), const Duration(minutes: 30)),
        StoreWaitStage.none,
      );
    });

    test('ساعة الموبايل متأخرة عن الخادم: الوقت ما يبقاش سالب', () {
      final now = _sent.subtract(const Duration(minutes: 3));
      expect(storeWaitElapsed(_sent, now), Duration.zero);
      expect(storeWaitStageOf(_order(), now), StoreWaitStage.waiting);
    });

    test('صيغة المدة بالعامية', () {
      expect(storeWaitAgeText(const Duration(seconds: 20)), 'لسه حالًا');
      expect(storeWaitAgeText(const Duration(minutes: 1)), 'بقاله دقيقة');
      expect(storeWaitAgeText(const Duration(minutes: 2)), 'بقاله دقيقتين');
      expect(storeWaitAgeText(const Duration(minutes: 7)), 'بقاله 7 دقايق');
      expect(storeWaitAgeText(const Duration(minutes: 12)), 'بقاله 12 دقيقة');
      expect(storeWaitAgeText(const Duration(minutes: 65)), 'بقاله ساعة');
    });

    test('اسم الحالة في «طلباتي» ما يقولش «المحل استلم» قبل التأكيد', () {
      expect(customerStatusLabel(_order(), _sent.add(const Duration(minutes: 1))),
          'مستني تأكيد المحل');
      expect(customerStatusLabel(_order(), _sent.add(const Duration(minutes: 9))),
          'المحل اتأخر في التأكيد');
      expect(
        customerStatusLabel(
            _order(status: OrderStatus.preparing), _sent.add(const Duration(minutes: 9))),
        OrderStatus.preparing.label,
      );
    });
  });

  group('شريط العميل في تفاصيل الطلب', () {
    testWidgets('مستني: رسالة هادية ومن غير زرار دعم', (tester) async {
      await tester.pumpWidget(_app(_order(), _sent.add(const Duration(minutes: 3))));
      expect(find.byKey(const Key('store-wait-waiting')), findsOneWidget);
      expect(find.text('مستني المحل يأكد طلبك'), findsOneWidget);
      expect(find.textContaining('بقاله 3 دقايق'), findsOneWidget);
      expect(find.byKey(const Key('store-wait-support')), findsNothing);
    });

    testWidgets('متأخر: تنبيه أحمر وزرار واتساب للدعم', (tester) async {
      await tester.pumpWidget(_app(_order(), _sent.add(const Duration(minutes: 12))));
      expect(find.byKey(const Key('store-wait-late')), findsOneWidget);
      expect(find.text('المحل اتأخر في تأكيد طلبك'), findsOneWidget);
      expect(find.byKey(const Key('store-wait-support')), findsOneWidget);
    });

    testWidgets('المحل بدأ يجهّز: الشريط بيختفي', (tester) async {
      await tester.pumpWidget(_app(_order(), _sent.add(const Duration(minutes: 12))));
      expect(find.byKey(const Key('store-wait-late')), findsOneWidget);
      await tester.pumpWidget(_app(
        _order(status: OrderStatus.preparing),
        _sent.add(const Duration(minutes: 13)),
      ));
      expect(find.byKey(const Key('store-wait-late')), findsNothing);
      expect(find.byKey(const Key('store-wait-waiting')), findsNothing);
    });

    testWidgets('مقاس 320px: من غير overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(_order(), _sent.add(const Duration(minutes: 90))));
      expect(tester.takeException(), isNull);
    });
  });
}
