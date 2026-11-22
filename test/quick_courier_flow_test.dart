import 'package:city_store/models/quick_courier_order.dart';
import 'package:city_store/screens/quick_courier_order_page.dart';
import 'package:city_store/screens/quick_courier_orders_page.dart';
import 'package:city_store/services/quick_courier_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = 'cust1_abcdefghijklmnop';

Map<String, dynamic> _doc(String status, [Map<String, dynamic> over = const {}]) => {
      'status': status,
      'courierId': status == 'open' ? '' : 'cour1',
      'customerFirstName': 'Ali',
      'area': 'وسط البلد',
      'stores': [
        {'name': 'الخير', 'items': 'عيش بلدي'},
      ],
      'policy': {
        'prepaidThresholdPiastres': 20000,
        'maximumAdvancePiastres': 100000,
        'maximumDeliveryPiastres': 20000,
      },
      'advance': {'amountPiastres': null, 'reference': '', 'sentAt': null, 'confirmedAt': null},
      'receipts': <Object>[],
      'summaryRevision': 0,
      ...over,
    };

const _totals = {'purchases': 15000, 'serviceFee': 500, 'delivery': 3000, 'prepaid': 0, 'due': 18500};

/// Backend وهمي: بيسجّل العمليات وبيرجّع الحالة اللي الاختبار عايزها.
class _FakeBackend implements QuickCourierBackend {
  QuickCourierOrder order;
  final List<MapEntry<String, Map<String, dynamic>>> calls = [];
  Map<String, dynamic> Function(String action, Map<String, dynamic> body)? next;
  bool enabled;

  _FakeBackend(Map<String, dynamic> doc, {this.enabled = true}) : order = QuickCourierOrder.fromMap(_id, doc);

  @override
  Future<QuickCourierOrder> act(String id, String action, [Map<String, dynamic> body = const {}]) async {
    calls.add(MapEntry(action, body));
    if (next != null) order = QuickCourierOrder.fromMap(_id, next!(action, body));
    return order;
  }

  @override
  Future<String?> captureReceipt(String orderId) async => null;

  @override
  Future<bool> isQuickEnabled() async => enabled;

  @override
  Future<QuickContact?> loadContact(String id) async =>
      const QuickContact(name: 'Ali Hassan', phone: '01012345678', address: 'شارع التحرير 10');

  @override
  Future<List<QuickCourierOrder>> loadMine() async => order.courierId.isEmpty ? const [] : [order];

  @override
  Future<List<QuickCourierOrder>> loadOpen() async => order.status == 'open' ? [order] : const [];

  @override
  Future<QuickCourierOrder?> loadOrder(String id) async => order;
}

Future<void> _pumpPage(WidgetTester tester, _FakeBackend backend) async {
  await tester.pumpWidget(MaterialApp(
    home: QuickCourierOrderPage(orderId: _id, backend: backend),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, Key key) {
  final button = tester.widget<ButtonStyleButton>(find.byKey(key));
  return button.onPressed != null;
}

void main() {
  testWidgets('زرار الطلبات السريعة بيظهر للمندوب المعتمد بس', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: QuickCourierEntry(backend: _FakeBackend(_doc('open'), enabled: false)))));
    await tester.pumpAndSettle();
    expect(find.text('الطلبات السريعة'), findsNothing);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: QuickCourierEntry(backend: _FakeBackend(_doc('open'))))));
    await tester.pumpAndSettle();
    expect(find.text('الطلبات السريعة'), findsOneWidget);
  });

  testWidgets('قايمة المتاحة بتعرض الطلب المفتوح', (tester) async {
    await tester.pumpWidget(MaterialApp(home: QuickCourierOrdersPage(backend: _FakeBackend(_doc('open')))));
    await tester.pumpAndSettle();
    expect(find.text('المتاحة (1)'), findsOneWidget);
    expect(find.text('متاح للقبول'), findsOneWidget);
  });

  testWidgets('القبول بيروح للـWorker، وبعده يظهر الاتصال بالعميل', (tester) async {
    final backend = _FakeBackend(_doc('open'))..next = (_, _) => _doc('accepted');
    await _pumpPage(tester, backend);
    expect(find.byKey(const Key('quick-call')), findsNothing);
    await _tap(tester, const Key('quick-accept'));
    expect(backend.calls.single.key, 'accept');
    expect(find.byKey(const Key('quick-call')), findsOneWidget);
    expect(find.text('شارع التحرير 10'), findsOneWidget);
  });

  testWidgets('التقدير: لحد 200 جنيه شراء مباشر، وأكتر يطلب مقدم', (tester) async {
    final backend = _FakeBackend(_doc('accepted'))..next = (_, _) => _doc('purchasing');
    await _pumpPage(tester, backend);
    expect(_enabled(tester, const Key('quick-start')), isFalse);

    await tester.enterText(find.descendant(of: find.byKey(const Key('quick-estimate')), matching: find.byType(TextField)), '250');
    await tester.pumpAndSettle();
    expect(find.text('اطلب المقدم'), findsOneWidget);

    await tester.enterText(find.descendant(of: find.byKey(const Key('quick-estimate')), matching: find.byType(TextField)), '١٥٠');
    await tester.pumpAndSettle();
    expect(find.text('ابدأ الشراء'), findsOneWidget);
    await _tap(tester, const Key('quick-start'));
    expect(backend.calls.single.key, 'start-purchase');
    expect(backend.calls.single.value['estimatedPurchasesPiastres'], 15000);
  });

  testWidgets('مستني التحويل: مفيش أي زرار شراء', (tester) async {
    await _pumpPage(tester, _FakeBackend(_doc('awaiting_advance')));
    expect(find.byKey(const Key('quick-receipt')), findsNothing);
    expect(find.text('ممنوع تشتري قبل ما التحويل يوصلك.'), findsOneWidget);
  });

  testWidgets('الشراء: إرسال الكشف مقفول من غير فواتير', (tester) async {
    await _pumpPage(tester, _FakeBackend(_doc('purchasing')));
    expect(find.byKey(const Key('quick-receipt')), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byKey(const Key('quick-delivery')), matching: find.byType(TextField)), '30');
    await tester.pumpAndSettle();
    expect(_enabled(tester, const Key('quick-submit-summary')), isFalse);
  });

  testWidgets('مستني موافقة العميل: ممنوع رمز التسليم أو التسليم', (tester) async {
    await _pumpPage(tester, _FakeBackend(_doc('summary_pending', {'totals': _totals, 'summaryRevision': 1})));
    expect(find.byKey(const Key('quick-pin')), findsNothing);
    expect(find.byKey(const Key('quick-deliver')), findsNothing);
    expect(find.text('185 ج'), findsOneWidget);
  });

  testWidgets('بعد الموافقة: التسليم بالرمز بس (4 أرقام)', (tester) async {
    final backend = _FakeBackend(_doc('summary_approved', {'totals': _totals, 'summaryRevision': 1}))
      ..next = (_, _) => _doc('delivered', {'totals': _totals});
    await _pumpPage(tester, backend);
    expect(_enabled(tester, const Key('quick-deliver')), isFalse);
    await tester.enterText(find.byKey(const Key('quick-pin')), '12');
    await tester.pumpAndSettle();
    expect(_enabled(tester, const Key('quick-deliver')), isFalse);
    await tester.enterText(find.byKey(const Key('quick-pin')), '1234');
    await tester.pumpAndSettle();
    await _tap(tester, const Key('quick-deliver'));
    expect(backend.calls.single.key, 'deliver');
    expect(backend.calls.single.value['pin'], '1234');
    expect(find.text('الطلب اتسلّم'), findsOneWidget);
  });
}
