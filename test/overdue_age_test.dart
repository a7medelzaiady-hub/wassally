import 'package:city_store/widgets/unanswered_orders_alert.dart';
import 'package:city_store/models/order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('الطلب القديم غير المردود يظهر بحالته وعمره بدون ازدحام', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final waiting = AppOrder(
      id: 'test-old-unanswered',
      storeName: 'المحل',
      items: const [],
      subtotal: 0,
      deliveryFee: 0,
      total: 0,
      status: OrderStatus.newOrder,
      createdAt: DateTime.now().subtract(const Duration(hours: 62)),
      address: '',
      phone: '',
      notes: '',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UnansweredOrdersAlert(orders: [waiting])),
    ));
    await tester.pump();
    expect(find.textContaining('بانتظار رد المحل'), findsOneWidget);
    expect(find.textContaining('لسه حالته «جديد» من يومين'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('عمر الطلب المتأخر بيتكتب بوحدة واضحة بدل رقم دقايق خام', () {
    expect(formatOverdueAge(const Duration(minutes: 5)), '5 دقائق');
    expect(formatOverdueAge(const Duration(minutes: 12)), '12 دقيقة');
    expect(formatOverdueAge(const Duration(minutes: 61)), 'ساعة');
    expect(formatOverdueAge(const Duration(hours: 3)), '3 ساعات');
    expect(formatOverdueAge(const Duration(hours: 23, minutes: 59)), '23 ساعة');
    // الحالة اللي ظهرت في الاختبار: 3461 دقيقة
    expect(formatOverdueAge(const Duration(minutes: 3461)), 'يومين');
    expect(formatOverdueAge(const Duration(days: 15)), '15 يوم');
    // ساعة الجهاز متأخرة عن السيرفر: ما يطلعش رقم سالب
    expect(formatOverdueAge(const Duration(minutes: -3)), '0 دقائق');
  });
}
