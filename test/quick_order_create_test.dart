import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:city_store/screens/quick_order_create_page.dart';
import 'package:city_store/utils/maps.dart';

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: QuickOrderCreatePage(prefillFromAccount: false),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('خانة «تحب تبعت طلبك إزاي» بتنسدل وتفتح الطريقة المختارة', (tester) async {
    await _pump(tester);
    expect(find.text('اختار طريقة الطلب'), findsOneWidget);
    for (final label in ['بصوتك', 'تكتبه', 'تصوّره', 'تبعت صورة']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('ابحث عن صنف'), findsNothing);

    await tester.tap(find.byKey(const Key('quick-method-write')));
    await tester.pumpAndSettle();
    expect(find.text('هتكتبه'), findsOneWidget);
    expect(find.text('بصوتك'), findsNothing, reason: 'القايمة اتقفلت');
    expect(find.text('الأصناف والكميات'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('quick-items-0')), '٢ كيلو رز');
    await tester.tap(find.byKey(const Key('quick-method-field')));
    await tester.pumpAndSettle();
    expect(find.text('مكتوب'), findsOneWidget, reason: 'الطلب المكتوب محفوظ');

    await tester.tap(find.byKey(const Key('quick-method-voice')));
    await tester.pumpAndSettle();
    expect(find.text('دوس واتكلم'), findsOneWidget);
    expect(find.text('الأصناف والكميات'), findsNothing);
  });

  testWidgets('«عنوان تاني» بيفتح خانة كتابة العنوان', (tester) async {
    await _pump(tester);
    expect(find.text('على عنواني'), findsOneWidget);
    expect(find.text('اكتب العنوان'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('quick-address-other')));
    await tester.tap(find.byKey(const Key('quick-address-other')));
    await tester.pumpAndSettle();
    expect(find.text('اكتب العنوان'), findsOneWidget);
  });

  testWidgets('الإرسال من غير طلب بيفتح اختيار الطريقة', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('quick-method-voice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('اختار تبعت طلبك إزاي'), findsOneWidget);
    expect(find.text('تكتبه'), findsOneWidget, reason: 'القايمة اتفتحت تاني');
  });

  test('إحداثيات الموقع في العنوان بتفتح النقطة بالظبط على الخريطة', () {
    expect(mapCoordinatesIn('شارع اليرموك، بيلا — الموقع: 31.17234, 31.21987'), '31.17234,31.21987');
    expect(mapCoordinatesIn('بيلا حي المحطة بجوار مسجد الرحمة'), isNull);
  });
}
