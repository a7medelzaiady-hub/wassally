import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/wasally_service_fee.dart';

/// الخطوة اللي المندوب فيها في «طلباتك على السريع». الشاشة بتعرض زرار واحد كبير لكل خطوة.
enum QuickCourierStep {
  /// طلب مفتوح: زرار «اقبل الطلب».
  available,

  /// اتقبل: اتصل بالعميل واكتب تقدير المشتريات.
  estimate,

  /// الشراء (المندوب بيدفع من جيبه): صوّر الفواتير، واكتب الأجرة، وابعت الكشف.
  /// لو العميل حوّل مقدم اختياري، المندوب يأكد استلامه هنا من غير ما يوقف الشراء.
  purchasing,

  /// الكشف اتبعت: مستني موافقة العميل (ممنوع التسليم).
  waitCustomer,

  /// العميل وافق: اكتب رمز التسليم.
  deliver,

  delivered,
  cancelled,
}

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  return null;
}

String _str(Object? value) => value is String ? value.trim() : '';

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

class QuickPricedLine {
  final String name;
  final int qty;
  final int unitPricePiastres;
  const QuickPricedLine(this.name, this.qty, this.unitPricePiastres);
  int get subtotalPiastres => qty * unitPricePiastres;
}

class QuickStoreRequest {
  final String name;
  final String items;
  final List<QuickPricedLine> pricedItems;
  const QuickStoreRequest({required this.name, required this.items, this.pricedItems = const []});
}

class QuickReceipt {
  final String storeName;
  final int amountPiastres;
  final String imageUrl;
  const QuickReceipt({required this.storeName, required this.amountPiastres, required this.imageUrl});
}

class QuickTotalsView {
  final int purchases;
  final int serviceFee;
  final int delivery;
  final int prepaid;

  /// موجب = العميل يدفع للمندوب، سالب = المندوب يرجّع للعميل.
  final int due;
  const QuickTotalsView({
    required this.purchases,
    required this.serviceFee,
    required this.delivery,
    required this.prepaid,
    required this.due,
  });

  static QuickTotalsView? fromMap(Object? raw) {
    final m = _map(raw);
    final purchases = _int(m['purchases']);
    final serviceFee = _int(m['serviceFee']);
    final delivery = _int(m['delivery']);
    final prepaid = _int(m['prepaid']);
    final due = _int(m['due']);
    if (purchases == null || serviceFee == null || delivery == null || prepaid == null || due == null) {
      return null;
    }
    return QuickTotalsView(
      purchases: purchases,
      serviceFee: serviceFee,
      delivery: delivery,
      prepaid: prepaid,
      due: due,
    );
  }
}

/// طلب سريع كما يراه المندوب. للعرض بس: كل الكتابة والحسابات الرسمية في الـWorker.
class QuickCourierOrder {
  final String id;
  final String status;
  final String kind;
  final String errandType;
  final int? errandQuotePiastres;
  final String errandQuoteStatus;
  final DateTime? errandPickupConfirmedAt;
  final String courierId;
  final String customerFirstName;
  final String area;
  final String notes;
  final List<QuickStoreRequest> stores;

  /// صور «صوّر طلبك» اللي العميل رفعها (بتتمسح بعد التسليم).
  final List<String> customerImages;
  final bool hasCustomerVoice;

  /// «كلّمني»: العميل مش كاتب حاجة، المندوب يتصل بيه وياخد الطلب في المكالمة.
  final bool callMe;

  /// اللي المندوب كتبه بعد مكالمة «كلّمني».
  final String agreedItems;
  final int? approxTotalPiastres;
  final int prepaidThresholdPiastres;
  final int maximumAdvancePiastres;
  final int maximumDeliveryPiastres;
  final int? estimatedPurchasesPiastres;
  final String paymentMode;
  final int? advanceAmountPiastres;
  final String advanceReference;
  final DateTime? advanceSentAt;
  final DateTime? advanceConfirmedAt;
  final List<QuickReceipt> receipts;
  final QuickTotalsView? totals;
  final int summaryRevision;
  final DateTime? summaryRejectedAt;
  final String summaryRejectReason;
  final DateTime? createdAt;

  const QuickCourierOrder({
    required this.id,
    required this.status,
    this.kind = 'quick',
    this.errandType = '',
    this.errandQuotePiastres,
    this.errandQuoteStatus = '',
    this.errandPickupConfirmedAt,
    this.courierId = '',
    this.customerFirstName = '',
    this.area = '',
    this.notes = '',
    this.stores = const [],
    this.customerImages = const [],
    this.hasCustomerVoice = false,
    this.callMe = false,
    this.agreedItems = '',
    this.approxTotalPiastres,
    this.prepaidThresholdPiastres = 20000,
    this.maximumAdvancePiastres = 100000,
    this.maximumDeliveryPiastres = 20000,
    this.estimatedPurchasesPiastres,
    this.paymentMode = '',
    this.advanceAmountPiastres,
    this.advanceReference = '',
    this.advanceSentAt,
    this.advanceConfirmedAt,
    this.receipts = const [],
    this.totals,
    this.summaryRevision = 0,
    this.summaryRejectedAt,
    this.summaryRejectReason = '',
    this.createdAt,
  });

  /// يقبل مستند Firestore (Timestamp) أو رد الـWorker (تواريخ نصية).
  factory QuickCourierOrder.fromMap(String id, Map<String, dynamic> m) {
    final policy = _map(m['policy']);
    final advance = _map(m['advance']);
    final rawStores = m['stores'];
    final rawImages = m['customerImages'];
    final rawReceipts = m['receipts'];
    return QuickCourierOrder(
      id: id,
      status: _str(m['status']),
      kind: _str(m['kind']),
      errandType: _str(m['errandType']),
      errandQuotePiastres: _int(m['errandQuotePiastres']),
      errandQuoteStatus: _str(m['errandQuoteStatus']),
      errandPickupConfirmedAt: _date(m['errandPickupConfirmedAt']),
      courierId: _str(m['courierId']),
      customerFirstName: _str(m['customerFirstName']),
      area: _str(m['area']),
      notes: _str(m['notes']),
      hasCustomerVoice: m['hasCustomerVoice'] == true,
      callMe: m['callMe'] == true && _str(m['kind']) != 'errand',
      agreedItems: _str(m['agreedItems']),
      customerImages: rawImages is List
          ? [for (final u in rawImages) if (u is String && u.startsWith('https://')) u]
          : const [],
      stores: [
        if (rawStores is List)
          for (final s in rawStores)
            if (s is Map)
              QuickStoreRequest(
                name: _str(s['name']),
                items: _str(s['items']),
                pricedItems: [
                  if (s['pricedItems'] is List)
                    for (final p in s['pricedItems'] as List)
                      if (p is Map && _int(p['qty']) != null && _int(p['unitPricePiastres']) != null)
                        QuickPricedLine(_str(p['name']), _int(p['qty'])!, _int(p['unitPricePiastres'])!),
                ],
              ),
      ],
      approxTotalPiastres: _int(m['approxTotalPiastres']),
      prepaidThresholdPiastres: _int(policy['prepaidThresholdPiastres']) ?? 20000,
      maximumAdvancePiastres: _int(policy['maximumAdvancePiastres']) ?? 100000,
      maximumDeliveryPiastres: _int(policy['maximumDeliveryPiastres']) ?? 20000,
      estimatedPurchasesPiastres: _int(m['estimatedPurchasesPiastres']),
      paymentMode: _str(m['paymentMode']),
      advanceAmountPiastres: _int(advance['amountPiastres']),
      advanceReference: _str(advance['reference']),
      advanceSentAt: _date(advance['sentAt']),
      advanceConfirmedAt: _date(advance['confirmedAt']),
      receipts: [
        if (rawReceipts is List)
          for (final r in rawReceipts)
            if (r is Map && _int(r['amountPiastres']) != null)
              QuickReceipt(
                storeName: _str(r['storeName']),
                amountPiastres: _int(r['amountPiastres'])!,
                imageUrl: _str(r['imageUrl']),
              ),
      ],
      totals: QuickTotalsView.fromMap(m['totals']),
      summaryRevision: _int(m['summaryRevision']) ?? 0,
      summaryRejectedAt: _date(m['summaryRejectedAt']),
      summaryRejectReason: _str(m['summaryRejectReason']),
      createdAt: _date(m['createdAt']),
    );
  }

  bool get isErrand => kind == 'errand';

  /// العميل كتب أو صوّر أو سجّل حاجة بنفسه (غير «كلّمني»).
  bool get hasOwnRequest =>
      customerImages.isNotEmpty || hasCustomerVoice ||
      stores.any((s) =>
          s.items.trim().isNotEmpty ||
          s.pricedItems.any((line) => line.name.trim().isNotEmpty));

  /// قبل الشراء في طلب «كلّمني»: لازم المندوب يكتب اللي اتفقوا عليه لو العميل ما كتبش حاجة.
  bool get needsAgreedItems => callMe && !hasOwnRequest;
  bool get quoteApproved => isErrand && errandQuoteStatus == 'accepted';

  String get errandTypeLabel => switch (errandType) {
    'parcel' => 'توصيل غرض',
    'documents' => 'استلام أوراق',
    'ready_order' => 'استلام طلب جاهز',
    _ => 'مشوار آخر',
  };

  QuickCourierStep get step => switch (status) {
        'open' => QuickCourierStep.available,
        'accepted' => QuickCourierStep.estimate,
        // awaiting_advance حالة قديمة (قبل المقدم الاختياري)؛ بنعاملها كشراء.
        'purchasing' || 'awaiting_advance' => QuickCourierStep.purchasing,
        'summary_pending' => QuickCourierStep.deliver, // old summaries: no customer bill approval needed
        'summary_approved' => QuickCourierStep.deliver,
        'delivered' => QuickCourierStep.delivered,
        _ => QuickCourierStep.cancelled,
      };

  bool get isActive =>
      step != QuickCourierStep.delivered && step != QuickCourierStep.cancelled;

  /// رقم العميل وعنوانه بيظهروا للمندوب المعيّن من القبول لحد موافقة العميل (زي القواعد).
  bool get canSeeContact => const {
        'accepted', 'awaiting_advance', 'purchasing', 'summary_pending', 'summary_approved',
      }.contains(status);

  /// المندوب يقدر يسيب الطلب قبل الشراء وقبل أي تحويل من العميل بس (نفس شرط الـWorker).
  bool get canRelease => status == 'accepted' && advanceSentAt == null;

  /// Explains an empty quick-order receipt instead of presenting an empty
  /// details screen. Items can be written freely or priced in a store group.
  bool get hasCustomerRequest =>
      callMe || customerImages.isNotEmpty || hasCustomerVoice || notes.trim().isNotEmpty ||
      stores.any((s) =>
          s.items.trim().isNotEmpty ||
          s.pricedItems.any((line) => line.name.trim().isNotEmpty));

  /// العميل قال إنه حوّل مقدم (اختياري) ولسه المندوب ما أكدش استلامه.
  bool get hasPendingAdvance => advanceSentAt != null && advanceConfirmedAt == null;

  /// رمز التسليم متاح بعد تجهيز الحساب النهائي، بلا موافقة مسبقة على الفاتورة.
  bool get canEnterPin => (status == 'summary_approved' || status == 'summary_pending') && totals != null;

  int get receiptsTotalPiastres => receipts.fold(0, (sum, r) => sum + r.amountPiastres);

  /// معاينة الكشف قبل الإرسال (للعرض بس؛ الـWorker بيحسب الرسمي بنفس المعادلة).
  QuickTotalsView previewTotals(int deliveryPiastres) {
    final purchases = receiptsTotalPiastres;
    final fee = isErrand
        ? 0
        : WasallyServiceFee.calculate(itemsAfterDiscountPiastres: purchases);
    final prepaid = advanceConfirmedAt != null ? (advanceAmountPiastres ?? 0) : 0;
    return QuickTotalsView(
      purchases: purchases,
      serviceFee: fee,
      delivery: deliveryPiastres,
      prepaid: prepaid,
      due: purchases + fee + deliveryPiastres - prepaid,
    );
  }
}

/// تحويل اللي المندوب بيكتبه بالجنيه (أرقام عربي أو إنجليزي، وكسر لحد قرشين) إلى قروش.
/// بيرجع null لو الرقم مش صالح.
int? parsePoundsToPiastres(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final buffer = StringBuffer();
  for (final ch in input.trim().split('')) {
    final a = arabic.indexOf(ch);
    final p = persian.indexOf(ch);
    if (a >= 0) {
      buffer.write(a);
    } else if (p >= 0) {
      buffer.write(p);
    } else if (ch == '٫' || ch == ',' || ch == '.') {
      buffer.write('.');
    } else if (ch != ' ' && ch != '٬') {
      buffer.write(ch);
    }
  }
  final text = buffer.toString();
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  final pounds = int.parse(parts[0]);
  final fraction = parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0;
  return pounds * 100 + fraction;
}

/// عرض القروش بالجنيه: 15000 → «150 ج»، 1250 → «12.50 ج».
String formatPiastres(int piastres) {
  final negative = piastres < 0;
  final abs = piastres.abs();
  final pounds = abs ~/ 100;
  final rest = abs % 100;
  final text = rest == 0 ? '$pounds' : '$pounds.${rest.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}$text ج';
}
