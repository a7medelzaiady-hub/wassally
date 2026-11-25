import 'package:city_store/models/quick_courier_order.dart';
import 'package:city_store/screens/quick_courier_order_page.dart';
import 'package:city_store/screens/quick_courier_orders_page.dart';
import 'package:city_store/services/quick_courier_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  // شاشة موبايل طويلة عشان الأزرار تبقى ظاهرة.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: QuickCourierOrderPage(orderId: _id, backend: backend),
  ));
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await _show(tester, find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, Key key) {
  final button = tester.widget<ButtonStyleButton>(find.byKey(key));
  return button.onPressed != null;
}

void main() {
  testWidgets('زرار الطلبات السريعة بيظهر للمندوب المعتمد بس', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: QuickCourierEntry(
      key: const Key('off'),
      backend: _FakeBackend(_doc('open'), enabled: false),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('الطلبات السريعة'), findsNothing);

    // مفتاح مختلف = State جديدة بتقرا الاعتماد من جديد.
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: QuickCourierEntry(
      key: const Key('on'),
      backend: _FakeBackend(_doc('open')),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('الطلبات السريعة'), findsOneWidget);
  });

  testWidgets('قايمة المتاحة بتعرض الطلب المفتوح', (tester) async {
    await tester.pumpWidget(MaterialApp(home: QuickCourierOrdersPage(backend: _FakeBackend(_doc('open')))));
    await tester.pumpAndSettle();
    expect(find.text('المتاحة (1)'), findsOneWidget);
    expect(find.text('متاح للقبول'), findsOneWidget);
  });

  testWidgets('قائمة السريع تعرض طلبات العميل قبل القبول بدون بيانات التواصل',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: QuickCourierOrdersPage(
        backend: _FakeBackend(_doc('open')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('المطلوب: عيش بلدي'), findsOneWidget);
    expect(find.byKey(const Key('quick-order-item-preview')), findsOneWidget);
    expect(find.textContaining('وسط البلد'), findsOneWidget);
    expect(find.textContaining('01012345678'), findsNothing);
    expect(find.textContaining('شارع التحرير 10'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('تفاصيل الطلب السريع بها فاتورة واضحة عند انتظار المندوب',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: QuickCourierOrderPage(
        orderId: _id,
        backend: _FakeBackend(_doc('open')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('فاتورة مشتريات العميل'), findsOneWidget);
    expect(find.text('الخير'), findsOneWidget);
    expect(find.text('عيش بلدي'), findsOneWidget);
    expect(find.textContaining('وسط البلد'), findsOneWidget);
    expect(find.text('متاح للقبول'), findsOneWidget);
    expect(find.textContaining('01012345678'), findsNothing);
    expect(find.textContaining('شارع التحرير 10'), findsNothing);
    expect(find.byKey(const Key('quick-call')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('القبول بيروح للـWorker، وبعده يظهر الاتصال بالعميل', (tester) async {
    final backend = _FakeBackend(_doc('open'))..next = (_, _) => _doc('accepted');
    await _pumpPage(tester, backend);
    expect(find.byKey(const Key('quick-call')), findsNothing);
    expect(find.text('افتح الخريطة'), findsNothing);
    expect(find.text('شارع التحرير 10'), findsNothing);
    await _tap(tester, const Key('quick-accept'));
    expect(backend.calls.single.key, 'accept');
    expect(find.byKey(const Key('quick-call')), findsOneWidget);
    expect(find.text('شارع التحرير 10'), findsOneWidget);
    expect(find.text('افتح الخريطة'), findsOneWidget);

    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = tester.binding.defaultBinaryMessenger;
    final launches = <MethodCall>[];
    var canOpenMap = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      launches.add(call);
      return canOpenMap;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final mapButton = find.text('افتح الخريطة');
    ScaffoldMessenger.of(tester.element(mapButton)).removeCurrentSnackBar();
    await tester.ensureVisible(mapButton);
    await tester.pumpAndSettle();
    await tester.tap(mapButton);
    await tester.pumpAndSettle();

    final launch = launches.single;
    expect(launch.method, 'launch');
    final uri = Uri.parse(launch.arguments['url'] as String);
    expect(uri.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/search/');
    expect(uri.queryParameters['query'], 'شارع التحرير 10');
    expect(find.text('تعذر فتح الخريطة.'), findsNothing);

    canOpenMap = false;
    await tester.tap(mapButton);
    await tester.pumpAndSettle();
    expect(launches, hasLength(2));
    expect(find.text('تعذر فتح الخريطة.'), findsOneWidget);
  });

  testWidgets('التقدير: المندوب يبدأ الشراء على طول مهما كان المبلغ (مفيش حد 200)', (tester) async {
    final backend = _FakeBackend(_doc('accepted'))..next = (_, _) => _doc('purchasing');
    await _pumpPage(tester, backend);
    await _show(tester, find.byKey(const Key('quick-start')));
    expect(_enabled(tester, const Key('quick-start')), isFalse);

    final field = find.descendant(of: find.byKey(const Key('quick-estimate')), matching: find.byType(TextField));
    await _show(tester, field);
    await tester.enterText(field, '٢٥٠٠');
    await tester.pumpAndSettle();
    expect(find.text('اطلب المقدم'), findsNothing);
    await _show(tester, find.byKey(const Key('quick-start')));
    expect(find.text('ابدأ الشراء'), findsOneWidget);
    await _tap(tester, const Key('quick-start'));
    expect(backend.calls.single.key, 'start-purchase');
    expect(backend.calls.single.value['estimatedPurchasesPiastres'], 250000);
    await _show(tester, find.byKey(const Key('quick-receipt')));
    expect(find.byKey(const Key('quick-receipt')), findsOneWidget);
  });

  testWidgets('مقدم اختياري: تأكيده متاح مع تصوير الفواتير من غير ما يوقف الشراء', (tester) async {
    final backend = _FakeBackend(_doc('purchasing', {
      'advance': {'amountPiastres': 30000, 'reference': 'VF-1', 'sentAt': '2026-11-22T11:00:00Z', 'confirmedAt': null},
    }));
    await _pumpPage(tester, backend);
    expect(find.byKey(const Key('quick-advance-received')), findsOneWidget);
    await _show(tester, find.byKey(const Key('quick-receipt')));
    expect(find.byKey(const Key('quick-receipt')), findsOneWidget);
    expect(_enabled(tester, const Key('quick-receipt')), isTrue);
  });

  testWidgets('من غير مقدم: مفيش زرار تأكيد تحويل خالص', (tester) async {
    await _pumpPage(tester, _FakeBackend(_doc('purchasing')));
    expect(find.byKey(const Key('quick-advance-received')), findsNothing);
  });

  testWidgets('الشراء: إرسال الكشف مقفول من غير فواتير', (tester) async {
    await _pumpPage(tester, _FakeBackend(_doc('purchasing')));
    await _show(tester, find.byKey(const Key('quick-receipt')));
    expect(find.byKey(const Key('quick-receipt')), findsOneWidget);
    final deliveryField = find.descendant(
      of: find.byKey(const Key('quick-delivery')),
      matching: find.byType(TextField),
    );
    await _show(tester, deliveryField);
    await tester.enterText(deliveryField, '30');
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(const Key('quick-submit-summary')));
    expect(_enabled(tester, const Key('quick-submit-summary')), isFalse);
  });

  testWidgets('مستني موافقة العميل: ممنوع رمز التسليم أو التسليم', (tester) async {
    await _pumpPage(tester, _FakeBackend(_doc('summary_pending', {'totals': _totals, 'summaryRevision': 1})));
    expect(find.byKey(const Key('quick-pin')), findsNothing);
    expect(find.byKey(const Key('quick-deliver')), findsNothing);
    expect(find.text('185 ج'), findsOneWidget);
  });

  testWidgets('بعد الموافقة: التسليم برمز من 4 أرقام عربية أو إنجليزية', (tester) async {
    final backend = _FakeBackend(_doc('summary_approved', {'totals': _totals, 'summaryRevision': 1}))
      ..next = (_, _) => _doc('delivered', {'totals': _totals});
    await _pumpPage(tester, backend);
    final deliveryButton = find.byKey(const Key('quick-deliver'));
    final pinField = find.byKey(const Key('quick-pin'));
    await _show(tester, deliveryButton);
    expect(_enabled(tester, const Key('quick-deliver')), isFalse);
    await _show(tester, pinField);
    await tester.enterText(pinField, '١2');
    await tester.pumpAndSettle();
    await _show(tester, deliveryButton);
    expect(_enabled(tester, const Key('quick-deliver')), isFalse);
    await _show(tester, pinField);
    await tester.enterText(pinField, '١2٣4');
    await tester.pumpAndSettle();
    await _tap(tester, const Key('quick-deliver'));
    expect(backend.calls.single.key, 'deliver');
    expect(backend.calls.single.value['pin'], '1234');
    await _show(tester, find.text('الطلب اتسلّم'));
    expect(find.text('الطلب اتسلّم'), findsOneWidget);
  });
}
