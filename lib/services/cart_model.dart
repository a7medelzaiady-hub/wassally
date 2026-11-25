import 'package:flutter/foundation.dart';

import '../models/product.dart';
import '../utils/format.dart';
import 'order_gateway.dart';
import 'wasally_service_fee.dart';

/// حالة السلة الحالية. الطلب الواحد بيكون من محل واحد بس (رسوم التوصيل والتحضير لكل محل).
/// السلال التانية (محل لكل سلة) بتتحفظ في «سلّاتي» (CartBook) والعميل يرجع لها في أي وقت.
class CartModel extends ChangeNotifier {
  /// رسوم التوصيل الافتراضية وقت الطلب. الأدمن يحدد الرسوم النهائية (finalDeliveryFee) لما يوافق على الطلب.
  static const double deliveryFee = 20;

  /// رسوم التوصيل الفعلية للطلب الحالي: سعر المنطقة لو العميل اختار منطقة، وإلا الافتراضي.
  double fee = deliveryFee;
  String area = '';

  /// كوبون الخصم المطبّق (نسبة من المجموع). الخصم بيتحسب من المجموع الحالي.
  String promoCode = '';
  double promoPercent = 0;

  /// رسوم التوصيل اللي العميل هيدفعها فعلًا (بعد إلغاء التوصيل المجاني = رسوم المنطقة).
  double get effectiveFee => fee;

  double get discount {
    if (promoCode.isEmpty || promoPercent <= 0) return 0;
    final d = (subtotal * promoPercent / 100 * 100).floor() / 100;
    return d >= subtotal ? 0 : d;
  }

  void setArea(String name, double newFee) {
    // Re-selecting the same area must not unlock a previously sent cart.
    if (area == name && fee == newFee) return;
    area = name;
    fee = newFee;
    _submittedOrderId = null;
    notifyListeners();
  }

  void setPromo(String code, double percent) {
    // A repeated coupon validation is not a new order.
    if (promoCode == code && promoPercent == percent) return;
    promoCode = code;
    promoPercent = percent;
    _submittedOrderId = null;
    notifyListeners();
  }

  final Map<Product, int> _items = {};
  Map<String, dynamic>? _specialRequest;
  String? _submittedOrderId;

  /// آخر طلب ناجح أُرسل بنفس محتويات السلة؛ يمنع الإرسال المكرر.
  String? get submittedOrderId => _submittedOrderId;

  void markSubmitted(String orderId) {
    _submittedOrderId = orderId;
    notifyListeners();
  }

  /// يبدأ طلبًا جديدًا بنفس الأصناف بإجراء صريح من العميل.
  void beginNewOrder() {
    _submittedOrderId = null;
    notifyListeners();
  }

  Map<String, dynamic>? get specialRequest => _specialRequest == null
      ? null
      : Map<String, dynamic>.unmodifiable(_specialRequest!);

  bool setSpecialRequest({
    required String storeId,
    required String storeName,
    required Map<String, dynamic> request,
  }) {
    if (!canAddFrom(storeId)) return false;
    _storeId = storeId;
    _storeName = storeName;
    _specialRequest = Map<String, dynamic>.from(request);
    _submittedOrderId = null;
    notifyListeners();
    return true;
  }

  void clearSpecialRequest() {
    _specialRequest = null;
    _submittedOrderId = null;
    if (_items.isEmpty) {
      _storeId = null;
      _storeName = null;
    }
    notifyListeners();
  }
  String? _storeId;
  String? _storeName;

  Map<Product, int> get items => Map.unmodifiable(_items);
  String? get storeId => _storeId;
  String? get storeName => _storeName;

  bool get isEmpty => _items.isEmpty && _specialRequest == null;
  int get count => _items.values.fold(0, (a, b) => a + b);
  double get subtotal =>
      _items.entries.fold(0.0, (sum, e) => sum + e.key.price * e.value);
  /// رسوم خدمة وصّلي (على العميل): بس في مسار الـWorker، لأنه هو اللي بيعتمدها.
  double get serviceFee => _items.isEmpty || !OrderGateway.serverOrdersEnabled
      ? 0
      : WasallyServiceFee.forItems(subtotal - discount);
  double get total =>
      _items.isEmpty ? 0 : subtotal + effectiveFee - discount + serviceFee;

  int qtyOf(Product p) => _items[p] ?? 0;

  /// هل ينفع نضيف منتج من المحل ده من غير ما نفرّغ السلة؟
  bool canAddFrom(String storeId) =>
      (_items.isEmpty && _specialRequest == null) || _storeId == storeId;

  /// بتضيف منتج. بترجع false لو السلة فيها منتجات من محل تاني.
  bool add(
    Product p, {
    required String storeId,
    required String storeName,
    int qty = 1,
  }) {
    if (!canAddFrom(storeId)) return false;
    _storeId = storeId;
    _storeName = storeName;
    _items[p] = (_items[p] ?? 0) + qty;
    _submittedOrderId = null;
    notifyListeners();
    return true;
  }

  void remove(Product p) {
    _submittedOrderId = null;
    final current = _items[p] ?? 0;
    if (current <= 1) {
      _items.remove(p);
    } else {
      _items[p] = current - 1;
    }
    if (_items.isEmpty && _specialRequest == null) {
      _storeId = null;
      _storeName = null;
    }
    notifyListeners();
  }

  /// حذف الصنف بالكامل من السلة.
  void removeItem(Product p) {
    _submittedOrderId = null;
    _items.remove(p);
    if (_items.isEmpty && _specialRequest == null) {
      _storeId = null;
      _storeName = null;
      promoCode = '';
      promoPercent = 0;
    }
    notifyListeners();
  }

  /// بيراجع أسعار السلة الحالية على قائمة المحل اللي اتحملت (مهم للسلال الراجعة من آخر مرة).
  /// الصنف اللي سعره اتغير بيتحدث، واللي مبقاش موجود بيتشال. بيرجع رسالة لكل تغيير.
  List<String> syncWithMenu(String storeId, List<Product> menu) {
    if (_storeId != storeId || _items.isEmpty || menu.isEmpty) return const [];
    final byId = {for (final p in menu) if (p.id.isNotEmpty) p.id: p};
    final changes = <String>[];
    final next = <Product, int>{};
    for (final e in _items.entries) {
      final line = e.key;
      final current = line.id.isEmpty ? null : byId[line.id];
      if (line.id.isEmpty) {
        next[line] = (next[line] ?? 0) + e.value;
        continue;
      }
      if (current == null || !current.available) {
        changes.add('«${line.name}» مبقاش متاح واتشال من السلة');
        continue;
      }
      final newPrice = current.price + line.chosenTotal;
      if ((newPrice - line.price).abs() < 0.005) {
        next[line] = (next[line] ?? 0) + e.value;
        continue;
      }
      changes.add('سعر «${line.name}» اتغير من ${formatPrice(line.price)} لـ ${formatPrice(newPrice)}');
      final updated = Product(line.name, newPrice, line.imageUrl, line.id, true, 0, '', null,
          line.description, const [], line.chosen);
      next[updated] = (next[updated] ?? 0) + e.value;
    }
    if (changes.isEmpty) return const [];
    _submittedOrderId = null;
    _items
      ..clear()
      ..addAll(next);
    if (_items.isEmpty && _specialRequest == null) {
      _storeId = null;
      _storeName = null;
    }
    notifyListeners();
    return changes;
  }

  /// نسخة من السلة الحالية عشان تتحفظ في «سلّاتي» لما العميل يتسوق من محل تاني.
  CartSnapshot snapshot() => CartSnapshot.fromParts(
        storeId: _storeId,
        storeName: _storeName,
        items: Map<Product, int>.from(_items),
        specialRequest: _specialRequest == null ? null : Map<String, dynamic>.from(_specialRequest!),
        area: area,
        fee: fee,
        promoCode: promoCode,
        promoPercent: promoPercent,
        submittedOrderId: _submittedOrderId,
      );

  /// يرجّع سلة محفوظة كسلة حالية (بيستبدل اللي في السلة دلوقتي).
  void restore(CartSnapshot s) {
    _items
      ..clear()
      ..addAll(s.items);
    _specialRequest = s.specialRequest == null ? null : Map<String, dynamic>.from(s.specialRequest!);
    _storeId = s.storeId;
    _storeName = s.storeName;
    area = s.area;
    fee = s.fee;
    promoCode = s.promoCode;
    promoPercent = s.promoPercent;
    _submittedOrderId = s.submittedOrderId;
    notifyListeners();
  }

  void clear() {
    _submittedOrderId = null;
    promoCode = '';
    promoPercent = 0;
    _items.clear();
    _specialRequest = null;
    _storeId = null;
    _storeName = null;
    notifyListeners();
  }
}

/// سلة محفوظة (محل واحد) في «سلّاتي». بيانات بس، من غير مستمعين.
class CartSnapshot {
  final String? storeId;
  final String? storeName;
  final Map<Product, int> items;
  final Map<String, dynamic>? specialRequest;
  final String area;
  final double fee;
  final String promoCode;
  final double promoPercent;
  final String? submittedOrderId;

  const CartSnapshot.fromParts({
    required this.storeId,
    required this.storeName,
    required this.items,
    required this.specialRequest,
    required this.area,
    required this.fee,
    required this.promoCode,
    required this.promoPercent,
    this.submittedOrderId,
  });

  bool get isEmpty => items.isEmpty && specialRequest == null;
  int get count => items.values.fold(0, (a, b) => a + b);
  double get subtotal => items.entries.fold(0.0, (sum, e) => sum + e.key.price * e.value);
}

/// السلة المشتركة في التطبيق كله.
final CartModel cart = CartModel();
