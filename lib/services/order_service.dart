import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order.dart';
import '../models/store.dart';
import '../models/user_profile.dart';
import 'cart_model.dart';
import 'order_contact_service.dart';
import 'order_status_writer.dart';
import 'promo_service.dart';
import 'user_service.dart';

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
  }) {
    final active = _activePlaceOrder;
    if (active != null) return active;

    final pending = _guardedPlaceOrder(
      cart: cart,
      name: name,
      phone: phone,
      address: address,
      notes: notes,
      courierNotes: courierNotes,
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
  }) async {
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

  /// بتبعت الطلب وتفرّغ السلة. بترجع رقم مستند الطلب.
  static Future<String> _placeOrder({
    required CartModel cart,
    required String name,
    required String phone,
    required String address,
    String notes = '',
    String courierNotes = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('لازم تسجّل دخول الأول');

    if (cart.isEmpty) throw StateError('السلة فاضية');
    if (cart.items.length > kMaxOrderLines) {
      throw const OrderLimitException(
        'الطلب الواحد مينفعش يزيد عن $kMaxOrderLines أصناف مختلفة. قسّمه على طلبين.',
      );
    }
    if (cart.items.values.any((q) => q > kMaxLineQty)) {
      throw const OrderLimitException('أقصى كمية للصنف الواحد $kMaxLineQty.');
    }

    // فحص واجهة مبكر لشرح سبب التقييد؛ قواعد Firestore تظل الحماية النهائية
    // وتمنع الطلب حتى لو استخدم العميل إصدارًا قديمًا من التطبيق.
    try {
      final restriction = await FirebaseFirestore.instance
          .collection('customer_restrictions')
          .doc(user.uid)
          .get();
      final restrictionData = restriction.data();
      final expiresAt = restrictionData?['expiresAt'];
      if (restrictionData?['active'] == true &&
          expiresAt is Timestamp &&
          expiresAt.toDate().isAfter(DateTime.now())) {
        final until = expiresAt.toDate();
        throw StateError(
          'إنشاء الطلبات متوقف مؤقتًا على حسابك حتى '
          '${until.day}/${until.month}/${until.year}. تواصل مع الإدارة لو محتاج مراجعة.',
        );
      }
    } on FirebaseException catch (error) {
      // قبل نشر القواعد الجديدة قد لا تسمح القواعد الحالية بقراءة هذا المسار.
      // نترك قرار السماح النهائي لقواعد إنشاء الطلب المنشورة.
      if (error.code != 'permission-denied') rethrow;
    }

    // نتحقق من المحل من Firestore وقت إرسال الطلب، ولا نعتمد على بيانات السلة
    // التي قد تكون قديمة أو تم تغييرها محليًا.
    final storeId = (cart.storeId ?? '').trim();
    if (storeId.isEmpty) {
      throw StateError('بيانات المحل غير مكتملة. ارجع للمحل وحاول تاني.');
    }

    final storeDoc = await FirebaseFirestore.instance
        .collection('stores')
        .doc(storeId)
        .get();

    if (!storeDoc.exists || storeDoc.data() == null) {
      throw StateError('المحل غير موجود أو لم يعد متاحًا.');
    }

    final store = Store.fromMap(storeDoc.id, storeDoc.data()!);
    if (!store.active) {
      throw StateError('المحل مغلق حاليًا ولا يمكن استقبال الطلبات.');
    }
    if (store.name.trim().isEmpty) {
      throw StateError('بيانات المحل غير مكتملة. حاول مرة تانية.');
    }

    // نعيد التحقق من الكوبون وقت الإرسال: النسبة ممكن تكون اتغيّرت بعد ما العميل طبّقه،
    // والقواعد بتقارن الخصم بالنسبة الحالية في promos/{code}.
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

    final data = <String, dynamic>{
      'userId': user.uid,
      // الاسم الأول بس في مستند الطلب العام (بيشوفه صاحب المحل). الاسم الكامل والموبايل
      // والعنوان في مستند خاص (orders/{id}/private/contact) مش بيقراه إلا العميل والمدير
      // والمندوب المكلّف بالطلب.
      'customerName': _firstName(name),
      'notes': notes,
      'storeId': store.id,
      'storeName': store.name,
      'items': cart.items.entries
          .map(
            (e) => {
              'name': e.key.name,
              'price': e.key.price,
              'qty': e.value,
              // معرّف الصنف (لو من الكتالوج الجديد). مطلوب لما enforcePrices يتفعّل.
              if (e.key.id.isNotEmpty) 'productId': e.key.id,
            },
          )
          .toList(),
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
      orderData: data,
      contactData: contactData,
    );
    if (kDebugMode) {
      debugPrint('ORDER DATA promo=[${data['promoCode']}] '
          'units=${(data['promoCode'] as String?)?.codeUnits} '
          'disc=${data['discount']} sub=${data['subtotal']} '
          'fee=${data['deliveryFee']} total=${data['total']}');
    }
    final ref = _orders.doc(orderId);
    final batch = FirebaseFirestore.instance.batch()..set(ref, data);
    batch.set(OrderContactService.ref(ref.id), contactData);
    // آخر وقت طلب للعميل: القواعد بتستخدمه للفاصل بين الطلبات (مفتاح orderRateLimit).
    batch.set(
      FirebaseFirestore.instance.collection('orderLimits').doc(user.uid),
      {'lastAt': FieldValue.serverTimestamp()},
    );

    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      // قد يكون السيرفر حفظ الـ Batch ثم انقطع الرد. نتحقق من نفس المستند
      // قبل إعادة المحاولة، حتى لا ننشئ طلبًا ثانيًا للشراء نفسه.
      var alreadyCreated = false;
      try {
        final existing = await ref.get();
        alreadyCreated = existing.exists &&
            existing.data()?['userId'] == user.uid &&
            existing.data()?['storeId'] == store.id &&
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

    cart.clear();
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
    final total = subtotal + order.deliveryFee - discount;
    final updatedItems = lines
        .map(
          (l) => {
            'name': l.name,
            'price': l.price,
            'qty': l.qty,
            if (l.productId.isNotEmpty) 'productId': l.productId,
          },
        )
        .toList();

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
      // تعديل العميل هو رده على «صنف غير متاح»: نشيل العلامة عشان المحل يقدر يبدأ التجهيز.
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

    // أثناء التحضير، قائمة المندوبين تتحدث في نفس Batch مع الطلب وبيانات التواصل.
    // نحدّث الحقول المتغيرة فقط ونحافظ على createdAt الأصلي كما هو.
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
        },
      );
    }

    try {
      await batch.commit();
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
    try {
      await UserService.save(
        UserProfile(name: name, phone: phone, address: address),
      );
    } catch (_) {}
  }

  /// العميل يحذف طلبه نهائيًا طالما حالته "new". (بعد كده الإلغاء بس.)
  static Future<void> deleteOrder(String id) async {
    final batch = FirebaseFirestore.instance.batch()
      ..delete(OrderContactService.ref(id))
      ..delete(_orders.doc(id));
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError(
          'مبقاش ينفع تحذف الطلب (المحل استلمه). تقدر تلغيه لو لسه متاح. (${e.code})',
        );
      }
      if (e.code == 'unavailable') {
        throw StateError('مفيش اتصال بالإنترنت. حاول تاني.');
      }
      throw StateError('تعذر حذف الطلب (${e.code}).');
    }
  }

  /// إخفاء الطلب من سجل العميل فقط مع الاحتفاظ بالسجل التجاري لدى وصّلي.
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

    // الأحدث [kMyOrdersLimit] طلب بس (محتاج فهرس userId + createdAt من firestore.indexes.json).
    // لو الفهرس لسه ما اتنشرش بنرجع للاستعلام القديم بدل ما الصفحة تتكسر.
    // ملاحظة: بنستخدم await for (مش yield*) عشان خطأ الاستعلام يتمسك هنا.
    try {
      await for (final snap
          in _orders
              .where('userId', isEqualTo: user.uid)
              .orderBy('createdAt', descending: true)
              .limit(kMyOrdersLimit)
              .snapshots()) {
        yield toList(snap);
      }
    } on FirebaseException catch (e) {
      if (e.code != 'failed-precondition') rethrow;
      await for (final snap
          in _orders.where('userId', isEqualTo: user.uid).snapshots()) {
        yield toList(snap);
      }
    }
  }

  /// متابعة طلب واحد لحظيًا.
  static Stream<AppOrder?> watchOrder(String id) {
    return _orders.doc(id).snapshots().map((s) {
      final data = s.data();
      return data == null ? null : AppOrder.fromMap(s.id, data);
    });
  }

  /// إلغاء الطلب (مسموح بس طالما حالته "تم استلام الطلب").
  static Future<void> cancel(String id) {
    return OrderStatusWriter.change(
      orderId: id,
      from: OrderStatus.newOrder,
      to: OrderStatus.cancelled,
      actorRole: 'customer',
    );
  }
}