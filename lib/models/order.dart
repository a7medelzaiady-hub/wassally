import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/material.dart';

import '../services/order_contact_service.dart';
import '../theme/app_theme.dart';

/// true = المندوب ما يبدأش التوصيل إلا بعد ما المحل يجهّز الطلب (preparing).
/// لو غيّرتها لـ false المندوب يقدر يبدأ من أول ما الطلب يتعيّنله.
/// القواعد ليها مفتاح مقابل: courierAfterPrep في app_info/security.
const bool kCourierWaitsForPrep = true;

/// true = المندوب ما يبدأش التوصيل إلا بعد ما المحل (أو الأدمن) يضغط «الطلب جاهز للاستلام».
/// القواعد ليها مفتاح مقابل: courierAfterReady في app_info/security (اختياري، افتراضيًا مقفول).
const bool kCourierWaitsForReady = true;

enum OrderStatus {
  newOrder('new', 'تم استلام الطلب', Icons.receipt_long, null),
  preparing('preparing', 'جاري التحضير', Icons.soup_kitchen, Color(0xFFE59A00)),
  onTheWay(
    'on_the_way',
    'في الطريق إليك',
    Icons.delivery_dining,
    Color(0xFF3B82F6),
  ),
  delivered('delivered', 'تم التوصيل', Icons.check_circle, kSuccess),
  cancelled('cancelled', 'ملغي', Icons.cancel, kDanger);

  final String key;
  final String label;
  final IconData icon;
  final Color? _color;
  const OrderStatus(this.key, this.label, this.icon, this._color);

  /// لون الحالة. "تم الاستلام" بيتبع لون السمة المختارة.
  Color get color => _color ?? kPrimary;

  static OrderStatus parse(String? key) {
    for (final s in OrderStatus.values) {
      if (s.key == key) return s;
    }
    return OrderStatus.newOrder;
  }

  /// الخطوة التالية اللي المندوب يقدر ينفّذها (null لو مفيش إجراء متاح).
  OrderStatus? get courierNext {
    switch (this) {
      case OrderStatus.newOrder:
      case OrderStatus.preparing:
        return OrderStatus.onTheWay;
      case OrderStatus.onTheWay:
        return OrderStatus.delivered;
      case OrderStatus.delivered:
      case OrderStatus.cancelled:
        return null;
    }
  }

  /// المندوب مستني المحل يجهّز الطلب قبل ما يبدأ التوصيل.
  bool get courierMustWait =>
      kCourierWaitsForPrep && this == OrderStatus.newOrder;

  /// مراحل التتبع بالترتيب (من غير الإلغاء).
  static const List<OrderStatus> timeline = [
    OrderStatus.newOrder,
    OrderStatus.preparing,
    OrderStatus.onTheWay,
    OrderStatus.delivered,
  ];
}

class OrderLine {
  final String name;
  final double price;
  final int qty;

  /// معرّف الصنف في الكتالوج (لو موجود). بنحافظ عليه عند تعديل الطلب.
  final String productId;
  const OrderLine(this.name, this.price, this.qty, [this.productId = '']);

  OrderLine withQty(int q) => OrderLine(name, price, q, productId);

  double get total => price * qty;
}

class AppOrder {
  final String id;
  final String storeName;
  final List<OrderLine> items;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final OrderStatus status;
  final DateTime? createdAt;
  final DateTime? editedAt;
  final String address;
  final String phone;
  final String notes;
  final String userName;

  /// الاسم الأول بس (بيظهر لصاحب المحل). الاسم الكامل والموبايل والعنوان في orders/{id}/private/contact.
  final String customerName;

  /// ملاحظات للمندوب (من المستند الخاص). المحل ما بيشوفهاش.
  final String courierNotes;
  final double discount;
  final String area;
  final String courierId;
  final String courierName;
  final String courierPhone;
  final String deliveryMode;
  final String storeId;
  final String userId;

  /// رسوم التوصيل اللي حدّدها الأدمن عند الموافقة. null = الرسوم الافتراضية في الطلب.
  final double? finalDeliveryFee;

  /// ختم التسليم (بيتكتب لما المندوب يسلّم): مين سلّم، إمتى، المبلغ المحصّل، وعمولته.
  /// الطلبات القديمة (قبل الإحصائيات) مفيهاش الحقول دي.
  final String deliveredBy;
  final DateTime? deliveredAt;

  /// وقت ما المندوب استلم الطلب (بيبدأ عدّاد المندوب منه).
  final DateTime? courierAt;

  /// وقت استلام المندوب الفعلي للطلب من المحل.
  final DateTime? pickedUpAt;

  /// وقت تسجيل وصول المندوب إلى عنوان العميل.
  final DateTime? courierArrivedAt;

  /// معرّف بلاغ التسليم المفتوح الذي ينتظر قرار الإدارة.
  final String activeDeliveryIssueId;

  /// آخر بلاغ إرجاع موثق، للاحتفاظ بتاريخ المندوب وتمكين تقييم العميل بعد الإلغاء.
  final String lastDeliveryIssueId;
  final double collectedAmount;
  final double courierEarning;

  /// الإجمالي اللي اعتمده المدير بعد مقارنته بأسعار الكتالوج. null = لسه ما اتعتمدش.
  final double? verifiedTotal;

  /// المحل (أو الأدمن) أكّد إن الطلب جاهز للاستلام من المندوب.
  final bool ready;
  final DateTime? readyAt;

  /// أسماء الأصناف اللي المحل علّمها «غير متاحة» وهو الطلب لسه جديد. العميل لازم يرد
  /// (يكمّل من غيرها أو يلغي) قبل ما المحل يبدأ التجهيز.
  final List<String> unavailableItems;

  const AppOrder({
    required this.id,
    required this.storeName,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.status,
    required this.createdAt,
    this.editedAt,
    required this.address,
    required this.phone,
    required this.notes,
    this.userName = '',
    this.customerName = '',
    this.courierNotes = '',
    this.discount = 0,
    this.area = '',
    this.courierId = '',
    this.courierName = '',
    this.courierPhone = '',
    this.deliveryMode = '',
    this.storeId = '',
    this.userId = '',
    this.finalDeliveryFee,
    this.deliveredBy = '',
    this.deliveredAt,
    this.courierAt,
    this.pickedUpAt,
    this.courierArrivedAt,
    this.activeDeliveryIssueId = '',
    this.lastDeliveryIssueId = '',
    this.collectedAmount = 0,
    this.courierEarning = 0,
    this.verifiedTotal,
    this.ready = false,
    this.readyAt,
    this.unavailableItems = const [],
  });

  /// الطلب متاح للمناديب: جاهز من المحل ومحدّش خده لسه.
  bool get isAvailableForCouriers =>
      status == OrderStatus.preparing && courierId.isEmpty;

  /// الاسم اللي يتعرض لصاحب المحل: الاسم الأول، أو الاسم القديم للطلبات القديمة.
  String get displayCustomer =>
      customerName.isNotEmpty ? customerName : userName;

  /// نسخة من الطلب فيها بيانات التواصل (بتتحمّل من المستند الخاص).
  AppOrder withContact(OrderContact? c) {
    if (c == null) return this;
    return AppOrder(
      id: id,
      storeName: storeName,
      items: items,
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      total: total,
      status: status,
      createdAt: createdAt,
      editedAt: editedAt,
      address: c.address.isNotEmpty ? c.address : address,
      phone: c.phone.isNotEmpty ? c.phone : phone,
      notes: notes,
      userName: c.name.isNotEmpty ? c.name : userName,
      customerName: customerName,
      courierNotes: c.courierNotes.isNotEmpty ? c.courierNotes : courierNotes,
      discount: discount,
      area: area,
      courierId: courierId,
      courierName: courierName,
      courierPhone: courierPhone,
      deliveryMode: deliveryMode,
      storeId: storeId,
      userId: userId,
      finalDeliveryFee: finalDeliveryFee,
      deliveredBy: deliveredBy,
      deliveredAt: deliveredAt,
      courierAt: courierAt,
      pickedUpAt: pickedUpAt,
      courierArrivedAt: courierArrivedAt,
      activeDeliveryIssueId: activeDeliveryIssueId,
      lastDeliveryIssueId: lastDeliveryIssueId,
      collectedAmount: collectedAmount,
      courierEarning: courierEarning,
      verifiedTotal: verifiedTotal,
      ready: ready,
      readyAt: readyAt,
      unavailableItems: unavailableItems,
    );
  }

  bool get hasUnavailableItems => unavailableItems.isNotEmpty;

  bool get isVerified => verifiedTotal != null;

  /// رسوم التوصيل الفعلية (وعمولة المندوب): اللي حدّدها الأدمن، وإلا الافتراضية.
  double get courierFee => finalDeliveryFee ?? deliveryFee;

  /// المبلغ المطلوب تحصيله فعليًا: الإجمالي المعتمد لو موجود، وإلا إجمالي الطلب.
  double get payable => verifiedTotal ?? total;

  factory AppOrder.fromMap(String id, Map<String, dynamic> m) {
    final rawItems = (m['items'] as List?) ?? const [];
    final items = <OrderLine>[];
    for (final i in rawItems) {
      if (i is Map) {
        items.add(
          OrderLine(
            (i['name'] ?? '').toString(),
            (i['price'] as num?)?.toDouble() ?? 0,
            (i['qty'] as num?)?.toInt() ?? 1,
            (i['productId'] ?? '').toString(),
          ),
        );
      }
    }
    final created = m['createdAt'];
    final edited = m['editedAt'];
    return AppOrder(
      id: id,
      storeName: (m['storeName'] ?? '').toString(),
      items: items,
      subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
      deliveryFee: (m['deliveryFee'] as num?)?.toDouble() ?? 0,
      total: (m['total'] as num?)?.toDouble() ?? 0,
      status: OrderStatus.parse(m['status']?.toString()),
      createdAt: created is Timestamp ? created.toDate() : null,
      editedAt: edited is Timestamp ? edited.toDate() : null,
      address: (m['address'] ?? '').toString(),
      phone: (m['phone'] ?? '').toString(),
      notes: (m['notes'] ?? '').toString(),
      userName: (m['userName'] ?? '').toString(),
      customerName: (m['customerName'] ?? '').toString(),
      discount: (m['discount'] as num?)?.toDouble() ?? 0,
      area: (m['area'] ?? '').toString(),
      courierId: (m['courierId'] ?? '').toString(),
      courierName: (m['courierName'] ?? '').toString(),
      courierPhone: (m['courierPhone'] ?? '').toString(),
      deliveryMode: (m['deliveryMode'] ?? '').toString(),
      storeId: (m['storeId'] ?? '').toString(),
      userId: (m['userId'] ?? '').toString(),
      finalDeliveryFee: (m['finalDeliveryFee'] as num?)?.toDouble(),
      deliveredBy: (m['deliveredBy'] ?? '').toString(),
      deliveredAt: m['deliveredAt'] is Timestamp
          ? (m['deliveredAt'] as Timestamp).toDate()
          : null,
      courierAt: m['courierAt'] is Timestamp
          ? (m['courierAt'] as Timestamp).toDate()
          : null,
      pickedUpAt: m['pickedUpAt'] is Timestamp
          ? (m['pickedUpAt'] as Timestamp).toDate()
          : null,
      courierArrivedAt: m['courierArrivedAt'] is Timestamp
          ? (m['courierArrivedAt'] as Timestamp).toDate()
          : null,
      activeDeliveryIssueId: (m['activeDeliveryIssueId'] ?? '').toString(),
      lastDeliveryIssueId: (m['lastDeliveryIssueId'] ?? '').toString(),
      collectedAmount: (m['collectedAmount'] as num?)?.toDouble() ?? 0,
      courierEarning: (m['courierEarning'] as num?)?.toDouble() ?? 0,
      verifiedTotal: (m['verifiedTotal'] as num?)?.toDouble(),
      ready: m['ready'] == true,
      readyAt: m['readyAt'] is Timestamp
          ? (m['readyAt'] as Timestamp).toDate()
          : null,
      unavailableItems: [
        for (final n in (m['unavailableItems'] as List?) ?? const [])
          if (n != null && n.toString().isNotEmpty) n.toString(),
      ],
    );
  }
}
