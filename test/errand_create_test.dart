import 'package:city_store/models/quick_courier_order.dart';
import 'package:city_store/screens/errand_create_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('مشوارك علينا: تصميم مضغوط ونوع المشوار وعنوانين منفصلين', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ErrandCreatePage(prefillFromAccount: false),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('مشوارك علينا'), findsOneWidget);
    expect(find.byKey(const Key('errand-pickup')), findsOneWidget);
    expect(find.byKey(const Key('errand-destination')), findsOneWidget);
    expect(find.byKey(const Key('errand-mission')), findsOneWidget);
    expect(find.byKey(const Key('errand-submit')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('errand-type-documents')));
    await tester.pumpAndSettle();
    final chip = tester.widget<ChoiceChip>(find.byKey(const Key('errand-type-documents')));
    expect(chip.selected, isTrue);
    expect(find.textContaining('أجرة'), findsWidgets);
  });

  testWidgets('مشوار ناقص: لا يحاول إرسال بيانات غير صحيحة', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ErrandCreatePage(prefillFromAccount: false),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('errand-submit')));
    await tester.pump();
    expect(find.textContaining('رقم موبايل مصري صحيح'), findsOneWidget);
  });

  test('تمييز المشاوير دون تغيير الحساب السريع العادي', () {
    const common = <String, dynamic>{
      'status': 'accepted', 'courierId': 'courier1',
      'stores': [{'name': '', 'items': 'استلم أوراق من المحل'}],
    };
    final errand = QuickCourierOrder.fromMap('e1', {
      ...common,
      'kind': 'errand',
      'errandType': 'documents',
      'errandQuotePiastres': 3500,
      'errandQuoteStatus': 'accepted',
    });
    expect(errand.isErrand, isTrue);
    expect(errand.errandTypeLabel, 'استلام أوراق');
    expect(errand.quoteApproved, isTrue);
    expect(errand.previewTotals(3500).serviceFee, 0);
    expect(errand.previewTotals(3500).due, 3500);

    final quick = QuickCourierOrder.fromMap('q1', common);
    expect(quick.isErrand, isFalse);
    expect(quick.quoteApproved, isFalse);
  });
}
