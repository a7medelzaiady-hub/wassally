import 'package:city_store/models/quick_courier_order.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _base([Map<String, dynamic> over = const {}]) => {
      'status': 'open',
      'userId': 'cust1',
      'courierId': '',
      'customerFirstName': 'Ali',
      'area': 'وسط البلد',
      'stores': [
        {
          'name': 'الخير',
          'items': 'عيش بلدي',
          'pricedItems': [
            {'name': 'زيت لتر', 'qty': 2, 'unitPricePiastres': 7500},
          ],
        },
        {'name': '', 'items': 'كيلو لحمة', 'pricedItems': null},
      ],
      'approxTotalPiastres': 15000,
      'policy': {
        'prepaidThresholdPiastres': 20000,
        'maximumAdvancePiastres': 100000,
        'maximumDeliveryPiastres': 20000,
      },
      'advance': {'amountPiastres': null, 'reference': '', 'sentAt': null, 'confirmedAt': null},
      'receipts': <Object>[],
      'totals': null,
      'summaryRevision': 0,
      ...over,
    };

QuickCourierOrder _order([Map<String, dynamic> over = const {}]) =>
    QuickCourierOrder.fromMap('cust1_abcdefghijklmnop', _base(over));

void main() {
  test('يقرا مستند Firestore ورد الـWorker (تواريخ Timestamp أو نص)', () {
    final fromFirestore = _order({
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10)),
      'advance': {'amountPiastres': 30000, 'reference': 'VF', 'sentAt': Timestamp.fromDate(DateTime.utc(2026, 11, 22, 11))},
    });
    final fromWorker = _order({
      'createdAt': '2026-11-22T10:00:00.000Z',
      'advance': {'amountPiastres': 30000, 'reference': 'VF', 'sentAt': '2026-11-22T11:00:00.000Z'},
    });
    expect(fromFirestore.createdAt!.toUtc(), DateTime.utc(2026, 11, 22, 10));
    expect(fromWorker.createdAt!.toUtc(), DateTime.utc(2026, 11, 22, 10));
    expect(fromWorker.advanceSentAt, isNotNull);
    expect(fromWorker.stores.length, 2);
    expect(fromWorker.stores.first.pricedItems.single.subtotalPiastres, 15000);
    expect(fromWorker.stores.last.pricedItems, isEmpty);
    expect(fromWorker.approxTotalPiastres, 15000);
  });

  test('تفاصيل الطلب السريع لا تظهر فاتورة خالية بلا تنبيه', () {
    expect(_order().hasCustomerRequest, isTrue);
    expect(_order({'stores': <Object>[], 'notes': ''}).hasCustomerRequest, isFalse);
    expect(_order({
      'stores': [{'name': 'سوبرماركت', 'items': '   ', 'pricedItems': <Object>[]}],
      'notes': '   ',
    }).hasCustomerRequest, isFalse);
    expect(_order({'stores': <Object>[], 'notes': 'من غير شطة'}).hasCustomerRequest, isTrue);
    expect(_order({
      'stores': [{'name': '', 'items': '', 'pricedItems': [
        {'name': 'عيش', 'qty': 2, 'unitPricePiastres': 300},
      ]}],
      'notes': '',
    }).hasCustomerRequest, isTrue);
  });

  test('كل حالة بتودّي لخطوة واحدة واضحة', () {
    expect(_order().step, QuickCourierStep.available);
    expect(_order({'status': 'accepted'}).step, QuickCourierStep.estimate);
    // حالة قديمة من قبل المقدم الاختياري: بتتعامل كشراء.
    expect(_order({'status': 'awaiting_advance'}).step, QuickCourierStep.purchasing);
    expect(_order({'status': 'purchasing'}).step, QuickCourierStep.purchasing);
    expect(_order({'status': 'summary_pending'}).step, QuickCourierStep.waitCustomer);
    expect(_order({'status': 'summary_approved'}).step, QuickCourierStep.deliver);
    expect(_order({'status': 'delivered'}).step, QuickCourierStep.delivered);
    expect(_order({'status': 'cancelled'}).step, QuickCourierStep.cancelled);
    expect(_order({'status': 'something_new'}).step, QuickCourierStep.cancelled);
  });

  test('المقدم اختياري: بيظهر للتأكيد لما العميل يحوّل، ومن غير ما يوقف الشراء', () {
    expect(_order({'status': 'purchasing'}).hasPendingAdvance, isFalse);
    final sent = _order({'status': 'purchasing', 'advance': {'amountPiastres': 30000, 'sentAt': '2026-11-22T11:00:00Z'}});
    expect(sent.hasPendingAdvance, isTrue);
    expect(sent.step, QuickCourierStep.purchasing);
    final confirmed = _order({
      'status': 'purchasing',
      'advance': {'amountPiastres': 30000, 'sentAt': '2026-11-22T11:00:00Z', 'confirmedAt': '2026-11-22T11:05:00Z'},
    });
    expect(confirmed.hasPendingAdvance, isFalse);
  });

  test('رمز التسليم بعد موافقة العميل بس، وسيب الطلب قبل الشراء والتحويل بس', () {
    const totals = {'purchases': 15000, 'serviceFee': 500, 'delivery': 3000, 'prepaid': 0, 'due': 18500};
    expect(_order({'status': 'summary_pending', 'totals': totals}).canEnterPin, isFalse);
    expect(_order({'status': 'summary_approved', 'totals': totals}).canEnterPin, isTrue);
    expect(_order({'status': 'summary_approved'}).canEnterPin, isFalse);
    expect(_order({'status': 'accepted'}).canRelease, isTrue);
    // العميل حوّل والطلب لسه «اتقبل»: المندوب ما يسيبش الطلب والفلوس معاه.
    expect(
      _order({'status': 'accepted', 'advance': {'amountPiastres': 1, 'sentAt': '2026-11-22T11:00:00Z'}}).canRelease,
      isFalse,
    );
    expect(_order({'status': 'purchasing'}).canRelease, isFalse);
  });

  test('بيانات العميل للمندوب المعيّن من القبول لحد موافقة العميل', () {
    expect(_order().canSeeContact, isFalse);
    for (final s in ['accepted', 'awaiting_advance', 'purchasing', 'summary_pending', 'summary_approved']) {
      expect(_order({'status': s}).canSeeContact, isTrue, reason: s);
    }
    expect(_order({'status': 'delivered'}).canSeeContact, isFalse);
  });

  test('معاينة الكشف بنفس معادلة الـWorker: رسوم مرة واحدة ويطرح المقدم المؤكد بس', () {
    final withAdvance = _order({
      'status': 'purchasing',
      'advance': {'amountPiastres': 60000, 'sentAt': '2026-11-22T11:00:00Z', 'confirmedAt': '2026-11-22T11:05:00Z'},
      'receipts': [
        {'storeName': '', 'amountPiastres': 20000, 'imageUrl': 'https://res.cloudinary.com/x/a.jpg'},
        {'storeName': 'الجزار', 'amountPiastres': 40000, 'imageUrl': 'https://res.cloudinary.com/x/b.jpg'},
      ],
    });
    final t = withAdvance.previewTotals(4000);
    expect([t.purchases, t.serviceFee, t.delivery, t.prepaid, t.due], [60000, 1200, 4000, 60000, 5200]);

    final unconfirmed = _order({
      'status': 'purchasing',
      'advance': {'amountPiastres': 60000, 'sentAt': '2026-11-22T11:00:00Z'},
      'receipts': [
        {'amountPiastres': 15000, 'imageUrl': 'https://res.cloudinary.com/x/a.jpg'},
      ],
    });
    expect(unconfirmed.previewTotals(3000).prepaid, 0);
    expect(unconfirmed.previewTotals(3000).due, 18500);
  });

  test('الكشف من الخادم بيتقرا كامل أو مايتقراش', () {
    expect(
      _order({'totals': {'purchases': 1, 'serviceFee': 500, 'delivery': 0, 'prepaid': 0, 'due': 501}}).totals?.due,
      501,
    );
    expect(_order({'totals': {'purchases': 1}}).totals, isNull);
  });

  test('تحويل اللي المندوب بيكتبه بالجنيه إلى قروش (أرقام عربي وإنجليزي)', () {
    expect(parsePoundsToPiastres('150'), 15000);
    expect(parsePoundsToPiastres('١٥٠'), 15000);
    expect(parsePoundsToPiastres('12.5'), 1250);
    expect(parsePoundsToPiastres('١٢٫٧٥'), 1275);
    expect(parsePoundsToPiastres(' 30 '), 3000);
    expect(parsePoundsToPiastres(''), isNull);
    expect(parsePoundsToPiastres('abc'), isNull);
    expect(parsePoundsToPiastres('-5'), isNull);
    expect(parsePoundsToPiastres('1.234'), isNull);
  });

  test('عرض القروش بالجنيه', () {
    expect(formatPiastres(15000), '150 ج');
    expect(formatPiastres(1250), '12.50 ج');
    expect(formatPiastres(-500), '-5 ج');
  });
}
