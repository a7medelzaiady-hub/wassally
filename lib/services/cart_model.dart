import 'package:flutter/foundation.dart';

import '../models/product.dart';

/// حالة السلة. الطلب الواحد بيكون من محل واحد بس (زي تطبيقات التوصيل المعروفة)
/// عشان رسوم التوصيل والتحضير بتتحسب لكل محل.
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
    area = name;
    fee = newFee;
    notifyListeners();
  }

  void setPromo(String code, double percent) {
    promoCode = code;
    promoPercent = percent;
    notifyListeners();
  }

  final Map<Product, int> _items = {};
  Map<String, dynamic>? _specialRequest;

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
    notifyListeners();
    return true;
  }

  void clearSpecialRequest() {
    _specialRequest = null;
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
  double get total => _items.isEmpty ? 0 : subtotal + effectiveFee - discount;

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
    notifyListeners();
    return true;
  }

  void remove(Product p) {
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
    _items.remove(p);
    if (_items.isEmpty && _specialRequest == null) {
      _storeId = null;
      _storeName = null;
      promoCode = '';
      promoPercent = 0;
    }
    notifyListeners();
  }

  void clear() {
    promoCode = '';
    promoPercent = 0;
    _items.clear();
    _specialRequest = null;
    _storeId = null;
    _storeName = null;
    notifyListeners();
  }
}

/// السلة المشتركة في التطبيق كله.
final CartModel cart = CartModel();
