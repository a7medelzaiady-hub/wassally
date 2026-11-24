import 'dart:async';

import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order.dart';
import '../models/store.dart';
import '../models/user_profile.dart';
import 'cart_book.dart';
import 'cart_model.dart';
import 'catalog_sync.dart';
import 'order_contact_service.dart';
import 'order_gateway.dart';
import 'order_status_writer.dart';
import 'performance_monitor.dart';
import 'promo_service.dart';
import 'user_service.dart';
import 'read_meter.dart';
import 'wasally_service_fee.dart';

/// أقصى عدد أصناف مختلفة في الطلب الواحد. لازم يطابق firestore.rules (validNewOrder: items.size() <= 100).
const int kMaxOrderLines = 100;

/// أقصى كمية للصنف الواحد (حد في التطبيق بس).
const int kMaxLineQty = 50;

/// عدد طلبات العميل اللي بتتحمّل في صفحة "طلباتي".
const int kMyOrdersLimit = 50;

/// طلب مرفوض قبل الإرسال لأنه بره الحدود المسموحة. [message] جاهزة للعرض.
class OrderLimitException implements Exception {
  final String message;
  const OrderLimitException(this.message);

  @override
  String toString() => message;
}

/// الاسم الأول فقط (أقصى 30 حرف).
String _firstName(String full) {
  final t = full.trim().split(RegExp(r'\s+')).first;
  return t.length > 30 ? t.substring(0, 30) : t;
}

class OrderService {
  const OrderService._();

  static CollectionReference<Map<String, dynamic>> get _orders =>
      FirebaseFirestore.instance.collection('orders');

  static Future<String>? _activePlaceOrder;

  /// يمنع الضغط المتكرر من إنشاء أكثر من طلب أثناء تنفيذ نفس العملية.
  static Future<String> placeOrder({
    required CartModel cart,
    required String name,
    required String phone,
    required String address,
    String notes = '',
    String courierNotes = '',
    int referralPoints = 0,
    int referralDiscountMinor = 0,
  }) {
    final active = _activePlaceOrder;
    if (active != null) return active;

    final pending = PerformanceMonitor.trace<String>(
      'checkout_submit',
      () => _guardedPlaceOrder(
        cart: cart,
        name: name,
        phone: phone,
        address: address,
        notes: notes,
        courierNotes: courierNotes,
        referralPoints: referralPoints,
        referralDiscountMinor: referralDiscountMinor,
      ),
    );
    _activePlaceOrder = pending;
    return pending.whenComplete(() {
      if (identical(_activePlaceOrder, pending)) _activePlaceOrder = null;
    });
  }

  /// أقل فاصل بين طلبين من نفس العميل (حماية من الضغط المتكرر والطلبات الآلية).
  static const Duration kOrderCooldown = Duration(seconds: 30);

  static String _lastOrderKey(String uid) => 'last_order_at_$uid';

  /// الوقت المتبقي قبل ما العميل يقدر يبعت طلب جديد (Duration.zero لو مفيش انتظار).
  static Future<Duration> cooldownRemaining() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Duration.zero;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_lastOrderKey(uid));
      if (ms == null) return Duration.zero;
      final since = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ms),
      );
      // ساعة الجهاز اتغيّرت للخلف: ما نحبسش العميل.
      if (since.isNegative) return Duration.zero;
      final left = kOrderCooldown - since;
      return left.isNegative ? Duration.zero : left;
    } catch (_) {
      return Duration.zero;
    }
  }

  static Future<void> _markOrderPlaced() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _lastOrderKey(uid),
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // التسجيل اختياري: فشله ما يمنعش الطلب.
    }
  }

  static Future<String> _guardedPlaceOrder({
    required CartModel cart,
    required String name,
    required String phone,
    required String address,
    String notes = '',
    String courierNotes = '',
    int referralPoints = 0,
    int referralDiscountMinor = 0,
  }) async {
    // السلة المرسلة تظل ظاهرة، لكن لا يُنشأ طلب ثانٍ بنفس المحتوى
    // إلا إذا غيّر العميل السلة أو اختار صراحة بدء طلب جديد.
    if (cart.submittedOrderId != null) {
      throw StateError('الطلب ده اتبعت بالفعل. لو عايز تطلب نفس الأصناف تاني، افتح السلة واختار «طلب جديد بنفس الأصناف».');
    }
    final wait = await cooldownRemaining();
    if (wait > Duration.zero) {
      throw OrderLimitException(
        'لسه مبعوت لك طلب من شوية. استنى ${wait.inSeconds + 1} ثانية وابعت تاني.',
      );
    }
    final id = await _placeOrder(
      cart: cart,
      name: name,
      phone: phone,
      address: address,
      notes: notes,
      courierNotes: courierNotes,
      referralPoints: referralPoints,
      referralDiscountMinor: referralDiscountMinor,
    );
    await _markOrderPlaced();
    return id;
  }

  /// بصمة ثابتة لا تحتفظ ببيانات التواصل نفسها داخل SharedPreferences.
  /// زوج من تجزئتين 32-bit يكفي لاكتشاف تغيّر محتوى محاولة الطلب محليًا.
  static String _orderFingerprint(
    Map<String, dynamic> orderData,
    Map<String, dynamic> contactData,
  ) {
    final safeOrder = Map<String, dynamic>.from(orderData)..remove('createdAt');
    final bytes = utf8.encode(jsonEncode({
      'order': safeOrder,
      'contact': contactData,
    }));
    var first = 0x811c9dc5;
    var second = 0x9e3779b9;
    for (final byte in bytes) {
      first = ((first ^ byte) * 0x01000193) & 0xffffffff;
      second = ((second ^ byte) * 0x045d9f3b) & 0xffffffff;
    }
    return '${first.toRadixString(16)}${second.toRadixString(16)}';
  }

  /// يعيد استخدام معرّف نفس المحاولة بعد انقطاع الاتصال، ولا يخزن PII محليًا.
  static Future<String> _pendingOrderId({
    required String uid,
    required Map<String, dynamic> orderData,
    required Map<String, dynamic> contactData,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final tokenKey = 'wasally_pending_order_token_$uid';
    final fingerprintKey = 'wasally_pending_order_fingerprint_$uid';
    final fingerprint = _orderFingerprint(orderData, contactData);

    var token = prefs.getString(tokenKey);
    if (token == null ||
        token.isEmpty ||
        prefs.getString(fingerprintKey) != fingerprint) {
      final random = Random.secure();
      token = List.generate(
        32,
        (_) => random.nextInt(16).toRadixString(16),
      ).join();
      await prefs.setString(tokenKey, token);
      await prefs.setString(fingerprintKey, fingerprint);
    }
    return '${uid}_$token';
  }

  static Future<void> _clearPendingOrderId(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wasally_pending_order_token_$uid');
    await prefs.remove('wasally_pending_order_fingerprint_$uid');
  }

  /// تبعت الطلب وتحتفظ بالسلة مع علامة نجاح تمنع الطلب المكرر.
  static Future<String> _placeOrder({
    required CartModel cart,
    required String name,
    required String phone,
    required String address,
    String notes = '',
    String courierNotes = '',
    int referralPoints = 0,
    int referralDiscountMinor = 0,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('لازم تسجّل دخول الأول');

    if (cart.isEmpty) throw StateError('السلة فاضية');
    if (cart.items.isEmpty) {
      throw StateError('ضيف منتجًا واحدًا على الأقل قبل إرسال الطلب الخاص.');
    }
    if (cart.items.length > kMaxOrderLines) {
      throw const OrderLimitException(
        'الطلب الواحد مينفعش يزيد عن $kMaxOrderLines أصناف مختلفة. قسّمه على طلبين.',
      );
    }
    if (cart.items.values.any((q) => q > kMaxLineQty)) {
      throw const OrderLimitException('أقصى كمية للصنف الواحد $kMaxLineQty.');
    }

    // Firestore may already enforce serverOrders while an older APK was built
    // without WASALLY_SERVER_ORDERS. Match the live security gate before writing.
    // A one-shot read avoids a permanent listener and prevents permission-denied
    // from a legacy client batch when direct writes have been disabled.
    var serverOrders = OrderGateway.serverOrdersEnabled;
    if (!serverOrders) {
      try {
        final security = await FirebaseFirestore.instance
            .collection('app_info').doc('security').get();
        serverOrders = security.data()?['serverOrders'] == true;
      } catch (_) {
        // Fail closed: never attempt a direct write when the security gate
        // cannot be verified. The Worker validates all order fields itself.
        serverOrders = true;
      }
    }
    // Do not silently charge a service fee absent from an older APK's cart.
    // The customer must see the Worker-mode total before confirming.
    if (serverOrders && !OrderGateway.serverOrdersEnabled) {
      throw StateError(
        'تم تحديث نظام تأكيد الطلبات. حدّث تطبيق وصّلي من Google Play '
        'علشان يظهر الإجمالي الصحيح قبل التأكيد.',
      );
    }
    final storeId = (cart.storeId ?? '').trim();
    if (storeId.isEmpty) {
      throw StateError('بيانات المحل غير مكتملة. ارجع للمحل وحاول تاني.');
    }

    Store? store;
    if (!serverOrders) {
      // مسار التوافق القديم فقط. في وضع Worker نتجنب تكرار قراءات
      // التقييد والمحل والكوبون؛ البوابة تنفذ التحقق الموثوق نفسه مرة واحدة.
      try {
        final restriction = await PerformanceMonitor.trace(
          'firestore_customer_check',
          () => FirebaseFirestore.instance
              .collection('customer_restrictions')
              .doc(user.uid)
              .get(),
        );
        final restrictionData = restriction.data();
        final expiresAt = restrictionData?['expiresAt'];
        if (restrictionData?['active'] == true &&
            expiresAt is Timestamp &&
            expiresAt.toDate().isAfter(DateTime.now())) {
          final until = expiresAt.toDate();
          throw StateError(
            'إنشاء الطلبات متوقف مؤقتًا على حسابك حتى '
            '${until.day}/${until.month}/${until.year}. لو شايف إن القرار محتاج مراجعة، افتح زر الشكاوى واختر «اعتراض على تقييد».',
          );
        }
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied') rethrow;
      }

      final storeDoc = await PerformanceMonitor.trace(
        'firestore_store_read',
        () => FirebaseFirestore.instance
            .collection('stores')
            .doc(storeId)
            .get(),
      );
      if (!storeDoc.exists || storeDoc.data() == null) {
        throw StateError('المحل غير موجود أو لم يعد متاحًا.');
      }
      store = Store.fromMap(storeDoc.id, storeDoc.data()!);
      if (!store.active) {
        throw StateError('المحل مغلق حاليًا ولا يمكن استقبال الطلبات.');
      }
      if (store.name.trim().isEmpty) {
        throw StateError('بيانات المحل غير مكتملة. حاول مرة تانية.');
      }

      // تحقق الكوبون محليًا مطلوب فقط لمسار Firestore القديم.
      if (cart.promoCode.isNotEmpty) {
        final p = await PromoService.check(cart.promoCode);
        if (p == null) {
          cart.setPromo('', 0);
          throw StateError('الكوبون لم يعد صالحًا واتشال من الطلب. راجع الإجمالي وحاول تاني.');
        }
        if (p.code != cart.promoCode || p.percent != cart.promoPercent) {
          cart.setPromo(p.code, p.percent);
        }
      }
    }

    final data = <String, dynamic>{
      'userId': user.uid,
      // الاسم الأول بس في مستند الطلب العام (بيشوفه صاحب المحل). الاسم الكامل والموبايل
      // والعنوان في مستند خاص (orders/{id}/private/contact) مش بيقراه إلا العميل والمدير
      // والمندوب المكلّف بالطلب.
      'customerName': _firstName(name),
      'notes': notes,
      'storeId': storeId,
      'storeName': store?.name ?? (cart.storeName ?? '').trim(),
      'items': cart.items.entries
          .map(
            (e) => {
              'name': e.key.name,
              'price': e.key.price,
              'qty': e.value,
              // معرّف الصنف من الكتالوج؛ البوابة الموثوقة تستخدمه لجلب السعر الحالي.
              if (e.key.id.isNotEmpty) 'productId': e.key.id,
              // اختيارات العميل (سكر، إضافات...) وسعرها؛ السعر أعلاه بيشملها.
              if (e.key.chosen.isNotEmpty)
                'options': e.key.chosen.map((o) => o.name).toList(),
              if (e.key.chosenTotal > 0) 'optionsTotal': e.key.chosenTotal,
            },
          )
          .toList(),
      if (cart.specialRequest != null) 'specialRequest': cart.specialRequest,
      'subtotal': cart.subtotal,
      'deliveryFee': cart.effectiveFee,
      if (cart.area.isNotEmpty) 'area': cart.area,
      if (cart.discount > 0) 'promoCode': cart.promoCode.trim().toUpperCase(),
      if (cart.discount > 0) 'discount': cart.discount,
      'total': cart.total,
      'paymentMethod': 'cash',
      'status': OrderStatus.newOrder.key,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final contactData = <String, dynamic>{
      'userName': name,
      'phone': phone,
      'address': address,
      if (courierNotes.trim().isNotEmpty) 'courierNotes': courierNotes.trim(),
    };
    final orderId = await _pendingOrderId(
      uid: user.uid,
      // A retry must keep the same ID even if the first response was lost.
      orderData: {
        ...data,
        if (referralPoints > 0) 'referralPoints': referralPoints,
        if (referralPoints > 0) 'referralDiscountMinor': referralDiscountMinor,
      },
      contactData: contactData,
    );
    if (kDebugMode) {
      debugPrint('ORDER DATA promo=[${data['promoCode']}] '
          'units=${(data['promoCode'] as String?)?.codeUnits} '
          'disc=${data['discount']} sub=${data['subtotal']} '
          'fee=${data['deliveryFee']} total=${data['total']}');
    }
    final ref = _orders.doc(orderId);
    // تجميع اختياري اختاره العميل من «سلّاتي» (بوابة الطلبات بس).
    final groupId = serverOrders ? carts.groupIdFor(storeId) : null;
    if (referralPoints > 0 && !serverOrders) {
      throw StateError('خصم النقاط يحتاج بوابة الطلبات.');
    }
    if (serverOrders) {
      if (!OrderGateway.isConfigured) {
        throw StateError('بوابة الطلبات الموثوقة غير مهيأة في هذا الإصدار.');
      }
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw StateError('تعذر تأكيد تسجيل الدخول. سجّل الدخول وحاول تاني.');
      }
      try {
        await OrderGateway.submit(
          idToken: idToken,
          payload: {
            'orderId': orderId,
            'storeId': storeId,
            'customerName': _firstName(name),
            'notes': notes,
            'area': cart.area,
            'expectedDeliveryFee': cart.effectiveFee,
            'expectedTotal': cart.total - referralDiscountMinor / 100,
            if (referralPoints > 0) 'referralPoints': referralPoints,
            if (referralPoints > 0) 'expectedReferralDiscountMinor': referralDiscountMinor,
            if (cart.discount > 0) 'promoCode': cart.promoCode,
            'items': cart.items.entries
                .map((e) => {
                      if (e.key.id.isNotEmpty) 'productId': e.key.id,
                      if (e.key.id.isEmpty) 'name': e.key.name,
                      'expectedPrice': e.key.price,
                      'qty': e.value,
                      if (e.key.chosen.isNotEmpty)
                        'options': e.key.chosen.map((option) => option.name).toList(),
                      if (e.key.chosenTotal > 0) 'optionsTotal': e.key.chosenTotal,
                    })
                .toList(),
            if (cart.specialRequest != null) 'specialRequest': cart.specialRequest,
            'contact': contactData,
            if (groupId != null) 'groupId': groupId,
          },
        );
      } on OrderGroupError catch (e) {
        // الطلب ما اتعملش. نقفل التجميع عشان الضغطة الجاية تبعته لوحده بنفس رقم الطلب.
        carts.setGrouping(false);
        throw StateError('${e.message} اضغط تأكيد تاني وهيتبعت كطلب لوحده.');
      } on CatalogMismatchError {
        // سعر أو توفر صنف اتغير والقائمة المجمّعة عند العميل متأخرة: نقرأ أصناف المحل ده مباشرة
        // (القرار محفوظ على الجهاز لحد ما القائمة تتحدث، فبيفضل بعد إعادة فتح التطبيق).
        // أي خطأ تاني (نت، محل مقفول، كوبون...) ما بيلمسش القائمة.
        await CatalogReader.distrustMenu(storeId);
        rethrow;
      }
    } else {
      // وضع التوافق القديم يظل متاحًا حتى نشر Worker وتفعيل serverOrders.
      final batch = FirebaseFirestore.instance.batch()..set(ref, data);
      batch.set(OrderContactService.ref(ref.id), contactData);
      batch.set(
        FirebaseFirestore.instance.collection('orderLimits').doc(user.uid),
        {'lastAt': FieldValue.serverTimestamp()},
      );

      try {
        await PerformanceMonitor.trace(
          'firestore_order_write',
          batch.commit,
        );
      } on FirebaseException catch (e) {
        // قد يكون السيرفر حفظ الـ Batch ثم انقطع الرد. نتحقق من نفس المستند
        // قبل إعادة المحاولة، حتى لا ننشئ طلبًا ثانيًا للشراء نفسه.
        var alreadyCreated = false;
        try {
          final existing = await ref.get();
          alreadyCreated = existing.exists &&
              existing.data()?['userId'] == user.uid &&
              existing.data()?['storeId'] == storeId &&
              existing.data()?['total'] == cart.total;
        } catch (_) {
          // عند تعذر التحقق نحتفظ بالمفتاح ليُعاد استخدامه في المحاولة التالية.
        }

        if (alreadyCreated) {
          if (kDebugMode) debugPrint('ORDER RETRY CONFIRMED [${e.code}]');
        } else {
          if (kDebugMode) debugPrint('ORDER ERROR [${e.code}]');
          if (e.code == 'permission-denied') {
            throw StateError('تعذر إرسال الطلب (${e.code}). حاول مرة تانية أو تواصل مع الدعم.');
          }
          if (e.code == 'unavailable') {
            throw StateError('مفيش اتصال بالإنترنت. حاول تاني.');
          }
          throw StateError('تعذر إرسال الطلب (${e.code}).');
        }
      }
    }

    unawaited(OrderGateway.notifyEvent(ref.id, 'created'));

    try {
      await _clearPendingOrderId(user.uid);
    } catch (_) {
      // فشل التنظيف لا يكرر الطلب؛ المفتاح لا يحتوي على بيانات شخصية.
      if (kDebugMode) debugPrint('ORDER IDEMPOTENCY CLEANUP ERROR');
    }

    // نحفظ البيانات للمرة الجاية. لو فشل الحفظ ده الطلب نفسه ما يتأثرش.
    try {
      await UserService.save(
        UserProfile(name: name, phone: phone, address: address),
      );
    } catch (_) {}

    if (groupId != null) carts.markGroupedOrder(storeId);
    cart.markSubmitted(ref.id);
    // لا تمسح المنتجات. احفظ علامة الإرسال فورًا حتى بعد إعادة تشغيل التطبيق.
    await carts.flush();
    return ref.id;
  }

  /// العميل يعدّل طلبه (الأصناف والبيانات) طالما لم يُعيّن/يستلم مندوبًا (new أو preparing).
  /// الإجمالي بيتحسب من جديد، والخصم بيتحسب بنفس نسبته القديمة.
  static Future<void> updateOrder({
    required AppOrder order,
    required List<OrderLine> items,
    required String name,
    required String phone,
    required String address,
    String notes = '',
    String courierNotes = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('لازم تسجّل دخول الأول');
    final lines = items.where((l) => l.qty > 0).toList();
    if (lines.isEmpty) {
      throw const OrderLimitException(
        'الطلب لازم يفضل فيه صنف واحد على الأقل. لو عايز تلغيه استخدم "حذف الطلب".',
      );
    }
    if (lines.length > kMaxOrderLines) {
      throw const OrderLimitException('عدد الأصناف أكبر من المسموح.');
    }
    if (lines.any((l) => l.qty > kMaxLineQty)) {
      throw const OrderLimitException('أقصى كمية للصنف الواحد $kMaxLineQty.');
    }

    final subtotal = lines.fold<double>(0, (a, l) => a + l.price * l.qty);
    var discount = 0.0;
    if (order.discount > 0 && order.subtotal > 0) {
      final ratio = order.discount / order.subtotal;
      discount = (subtotal * ratio * 100).floor() / 100;
      if (discount >= subtotal) discount = 0;
    }
    // الطلب القديم (من غير رسوم خدمة) بيفضل من غير رسوم بعد التعديل، زي الـWorker.
    final serviceFee = order.serviceFee == null
        ? 0.0
        : WasallyServiceFee.forItems(subtotal - discount);
    final referralDiscount = order.referralDiscountMinor / 100;
    if ((subtotal * 100).round() < order.referralDiscountMinor) {
      throw StateError('قيمة الأصناف بعد التعديل أقل من خصم النقاط المحجوز.');
    }
    final total = subtotal + order.deliveryFee - discount + serviceFee - referralDiscount;
    final updatedItems = lines.map((l) => l.toMap()).toList();

    // Match the live Firestore gate before editing, just like order creation.
    // An older APK must not attempt a legacy batch after serverOrders is enabled.
    var serverOrders = OrderGateway.serverOrdersEnabled;
    if (!serverOrders) {
      try {
        final security = await FirebaseFirestore.instance
            .collection('app_info').doc('security').get();
        serverOrders = security.data()?['serverOrders'] == true;
      } catch (_) {
        // Fail closed if the security setting cannot be checked.
        serverOrders = true;
      }
    }
    if (serverOrders && !OrderGateway.serverOrdersEnabled) {
      throw StateError(
        'تم تحديث نظام تعديل الطلبات. حدّث تطبيق وصّلي من Google Play '
        'علشان تعدّل طلبك بأمان.',
      );
    }
    if (serverOrders || order.serviceFee != null) {
      if (!OrderGateway.isConfigured) {
        throw StateError('بوابة الطلبات الموثوقة غير مهيأة في هذا الإصدار.');
      }
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw StateError('تعذر تأكيد تسجيل الدخول. سجّل الدخول وحاول تاني.');
      }
      await OrderGateway.update(
        idToken: idToken,
        orderId: order.id,
        payload: {
          'customerName': _firstName(name),
          'notes': notes,
          'expectedTotal': total,
          'items': lines
              .map((line) => {
                    if (line.productId.isNotEmpty) 'productId': line.productId,
                    if (line.productId.isEmpty) 'name': line.name,
                    'expectedPrice': line.price,
                    'qty': line.qty,
                    if (line.options.isNotEmpty) 'options': line.options,
                    if (line.optionsTotal > 0) 'optionsTotal': line.optionsTotal,
                  })
              .toList(),
          'contact': {
            'userName': name,
            'phone': phone,
            'address': address,
            if (courierNotes.trim().isNotEmpty)
              'courierNotes': courierNotes.trim(),
          },
        },
      );
    } else {
      final ref = _orders.doc(order.id);
      final batch = FirebaseFirestore.instance.batch();
      batch.update(ref, {
        'items': updatedItems,
        'subtotal': subtotal,
        'total': total,
        'notes': notes,
        'customerName': _firstName(name),
        if (discount > 0) 'discount': discount,
        if (discount == 0 && order.discount > 0) 'discount': FieldValue.delete(),
        if (discount == 0 && order.discount > 0) 'promoCode': FieldValue.delete(),
        'editedAt': FieldValue.serverTimestamp(),
        'verifiedTotal': FieldValue.delete(),
        'verifiedAt': FieldValue.delete(),
        if (order.unavailableItems.isNotEmpty)
          'unavailableItems': FieldValue.delete(),
      });
      batch.update(OrderContactService.ref(order.id), {
        'userName': name,
        'phone': phone,
        'address': address,
        'courierNotes': courierNotes.trim().isEmpty
            ? FieldValue.delete()
            : courierNotes.trim(),
      });

      if (order.status == OrderStatus.preparing && order.courierId.isEmpty) {
        batch.update(
          FirebaseFirestore.instance
              .collection('courier_available_orders')
              .doc(order.id),
          {
            'items': updatedItems,
            'subtotal': subtotal,
            'discount': discount,
            'total': total,
            'editedAt': FieldValue.serverTimestamp(),
          },
        );
      }

      try {
        await PerformanceMonitor.trace(
          'firestore_order_update',
          batch.commit,
        );
      } on FirebaseException catch (e) {
        if (kDebugMode) debugPrint('ORDER EDIT ERROR [${e.code}]');
        if (e.code == 'permission-denied') {
          throw StateError(
            'مبقاش ينفع تعدّل الطلب (المحل استلمه أو اتغيّرت حالته). (${e.code})',
          );
        }
        if (e.code == 'unavailable') {
          throw StateError('مفيش اتصال بالإنترنت. حاول تاني.');
        }
        throw StateError('تعذر تعديل الطلب (${e.code}).');
      }
    }

    try {
      await UserService.save(
        UserProfile(name: name, phone: phone, address: address),
      );
    } catch (_) {}
  }

  /// "حذف الطلب" عند العميل: إلغاء الطلب (وهو لسه جديد) ثم إخفاؤه من قائمته.
  /// مفيش حذف فعلي: الطلب بيكون وصل للمحل، فبيفضل عنده وعند الإدارة بحالة "ملغي".
  static Future<void> deleteOrder(String id) async {
    try {
      await cancel(id);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError(
          'مبقاش ينفع تحذف الطلب (المحل استلمه). (${e.code})',
        );
      }
      if (e.code == 'unavailable') {
        throw StateError('مفيش اتصال بالإنترنت. حاول تاني.');
      }
      throw StateError('تعذر حذف الطلب (${e.code}).');
    }
    await hideFromCustomer(id);
  }

  /// إخفاء الطلب من سجل العميل فقط مع الاحتفاظ بالسجل التجاري لدى وصلي.
  static Future<void> hideFromCustomer(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('سجّل الدخول أولاً.');
    try {
      await _orders.doc(id).update({'customerHidden': true});
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError('تعذر إخفاء الطلب. تحقق من صلاحيات Firestore.');
      }
      if (e.code == 'unavailable') {
        throw StateError('مفيش اتصال بالإنترنت. حاول تاني.');
      }
      throw StateError('تعذر إخفاء الطلب (${e.code}).');
    }
  }

  /// طلبات المستخدم الحالي، الأحدث الأول.
  static Stream<List<AppOrder>> watchMyOrders() async* {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    List<AppOrder> toList(QuerySnapshot<Map<String, dynamic>> snap) {
      final list = snap.docs
          .where((d) => d.data()['customerHidden'] != true)
          .map((d) => AppOrder.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) {
        final aMs = a.createdAt?.millisecondsSinceEpoch ?? 1 << 53;
        final bMs = b.createdAt?.millisecondsSinceEpoch ?? 1 << 53;
        return bMs.compareTo(aMs);
      });
      return list;
    }

    // لا نرجع لاستعلام غير محدود إذا كان الفهرس ناقصًا؛ ده ممكن يقرأ تاريخ العميل بالكامل.
    // الفهرس userId + createdAt موجود في firestore.indexes.json ويجب نشره مع التطبيق.
    final stream = _orders
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(kMyOrdersLimit)
        .snapshots().metered('orders:customer');
    await for (final snap in PerformanceMonitor.traceFirstEvent(
      'order_history_initial_load',
      stream,
    )) {
      yield toList(snap);
    }
  }

  /// متابعة طلب واحد لحظيًا.
  static Stream<AppOrder?> watchOrder(String id) {
    return PerformanceMonitor.traceFirstEvent(
      'order_tracking_initial_load',
      _orders.doc(id).snapshots().metered('orders:customer-one'),
    ).map((s) {
      final data = s.data();
      return data == null ? null : AppOrder.fromMap(s.id, data);
    });
  }

  /// يطلب من Worker حذف مرفقات هذا الطلب بعد ختم تأكيد الاستلام فقط.
  /// الفشل لا يلغي تأكيد الاستلام؛ تكرار فتح الطلب يسمح بإعادة المحاولة.
  static Future<void> cleanupConfirmedAttachments(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !OrderGateway.isConfigured) return;
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) return;
    await OrderGateway.cleanupAttachments(idToken: idToken, orderId: orderId);
  }

  static Future<void> cancel(String id) {
    return OrderStatusWriter.change(
      orderId: id,
      from: OrderStatus.newOrder,
      to: OrderStatus.cancelled,
      actorRole: 'customer',
    );
  }
}