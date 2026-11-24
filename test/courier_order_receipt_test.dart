import 'package:city_store/models/order.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:city_store/widgets/courier_order_receipt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget screen({
    required List<OrderLine> items,
    Map<String, dynamic>? specialRequest,
    String notes = '',
  }) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: ListView(
            children: [
              CourierOrderReceipt(
                items: items,
                specialRequest: specialRequest,
                notes: notes,
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('تظهر كل أصناف الطلب وخياراتها والكميات فورًا في الفاتورة',
      (tester) async {
    await tester.pumpWidget(screen(
      items: const [
        OrderLine('سندوتش شاورما', 35, 2, '', ['زيادة طحينة']),
        OrderLine('عصير مانجو', 25, 1),
      ],
      notes: 'من فضلك من غير بصل',
      specialRequest: {
        'description': 'محتاج نوع عصير غير موجود في القائمة',
        'quantity': 3,
        'imageUrl': 'https://example.invalid/secret-attachment.png',
        'address': 'private street not allowed',
      },
    ));
    expect(find.text('فاتورة طلب العميل'), findsOneWidget);
    expect(find.text('2 ×'), findsOneWidget);
    expect(find.text('سندوتش شاورما'), findsOneWidget);
    expect(find.text('زيادة طحينة'), findsOneWidget);
    expect(find.text('70 ج.م'), findsOneWidget);
    expect(find.text('عصير مانجو'), findsOneWidget);
    expect(find.text('25 ج.م'), findsOneWidget);
    expect(find.textContaining('محتاج نوع عصير'), findsOneWidget);
    expect(find.text('📎 صورة مرفقة بالطلب'), findsOneWidget);
    expect(find.textContaining('من غير بصل'), findsOneWidget);
    // لا تعرض رابط صورة العميل ولا أي حقل خصوصية غير مخصص للفاتورة.
    expect(find.textContaining('secret-attachment'), findsNothing);
    expect(find.textContaining('private street'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('الفاتورة لا تكسر شاشة المندوب الضيقة بنصوص طويلة', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(screen(items: [
      OrderLine('تفاصيل صنف طويلة للغاية ومكتوبة بالعربية ' * 4,
          12.5, 4, '', ['إضافة طويلة بدون رسوم ' * 3]),
    ]));
    await tester.pump();
    expect(find.byKey(const Key('courier-order-receipt')), findsOneWidget);
    expect(find.text('50 ج.م'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('الطلبات القديمة بدون أصناف تعرض حالة مفهومة', (tester) async {
    await tester.pumpWidget(screen(items: const []));
    expect(find.text('لا توجد أصناف مسجلة في الطلب.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
