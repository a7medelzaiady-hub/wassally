import 'package:city_store/models/order.dart';
import 'package:city_store/services/order_contact_service.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:city_store/widgets/courier_order_details_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppOrder _sampleOrder() => AppOrder(
      id: 'courier-order-10',
      storeName: 'مخبز البلد',
      items: const [
        OrderLine('عيش بلدي', 5, 4),
        OrderLine('مخبوزات', 15, 2),
      ],
      subtotal: 50,
      deliveryFee: 20,
      total: 70,
      status: OrderStatus.onTheWay,
      createdAt: DateTime(2026, 11, 25),
      address: '', // The public order must never be used for private data.
      phone: '',
      notes: 'من غير شطة',
      area: 'وسط البلد',
    );

Widget _screen(ValueNotifier<bool> access, {OrderContact? contact}) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SizedBox(
        height: 740,
        child: CourierOrderDetailsSheet(
          order: _sampleOrder(),
          orderNumber: '100042',
          contact: contact,
          canSeePrivateContact: access,
          onOpenMap: () {},
          onCall: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('تفاصيل المندوب فاتورة كاملة بدون تحميل إضافي على 320px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final access = ValueNotifier(false);
    addTearDown(access.dispose);
    await tester.pumpWidget(_screen(access));
    await tester.pump();
    expect(find.byKey(const Key('courier-order-details-sheet')), findsOneWidget);
    expect(find.text('تفاصيل الطلب رقم 100042'), findsOneWidget);
    expect(find.text('فاتورة طلب العميل'), findsOneWidget);
    expect(find.text('عيش بلدي'), findsOneWidget);
    expect(find.text('4 ×'), findsOneWidget);
    expect(find.textContaining('المطلوب تحصيله: 70 ج.م'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('لا تظهر هوية أو عنوان أو رقم هاتف إلا أثناء التعيين',
      (tester) async {
    final access = ValueNotifier(false);
    addTearDown(access.dispose);
    const contact = OrderContact(
      name: 'العميلة الخاصة',
      phone: '01012345678',
      address: 'عنوان سري - شارع 1',
      courierNotes: 'الدور الثالث',
    );
    await tester.pumpWidget(_screen(access, contact: contact));
    await tester.pump();
    expect(find.textContaining('عنوان سري'), findsNothing);
    expect(find.textContaining('01012345678'), findsNothing);
    expect(find.byKey(const Key('courier-details-map')), findsNothing);

    access.value = true;
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('courier-details-map')), 150,
    );
    expect(find.textContaining('عنوان سري'), findsOneWidget);
    expect(find.textContaining('01012345678'), findsOneWidget);
    expect(find.byKey(const Key('courier-details-call')), findsOneWidget);

    // Revocation while the details sheet is still open masks PII immediately.
    access.value = false;
    await tester.pump();
    expect(find.textContaining('عنوان سري'), findsNothing);
    expect(find.textContaining('01012345678'), findsNothing);
    expect(find.byKey(const Key('courier-details-call')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
