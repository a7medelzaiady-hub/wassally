import 'package:flutter/foundation.dart';

import '../models/store.dart';
import 'cart_model.dart';

/// «سلّاتي»: سلة لكل محل. السلة الحالية هي [cart] (المسار القديم زي ما هو)،
/// والسلال التانية محفوظة هنا في الذاكرة لحد ما العميل يرجع لها أو يأكدها أو يمسحها.
/// كل سلة بتتطلب كطلب مستقل بنظام الطلبات الحالي (مفيش أي تغيير في الطلب أو الـWorker).
class CartBook extends ChangeNotifier {
  CartBook(this.active);

  /// السلة الحالية (نفس [cart] في التطبيق).
  final CartModel active;

  final Map<String, CartSnapshot> _parked = {};
  final Map<String, Store> _stores = {};

  /// السلال المحفوظة (غير السلة الحالية)، بترتيب الإضافة.
  List<CartSnapshot> get parked => List.unmodifiable(_parked.values);

  /// عدد كل السلال اللي فيها حاجة (الحالية + المحفوظة).
  int get cartsCount => (active.isEmpty ? 0 : 1) + _parked.length;

  bool get hasParked => _parked.isNotEmpty;

  CartSnapshot? parkedFor(String storeId) => _parked[storeId];

  /// بيافتكر بيانات المحل عشان زرار «إضافة منتجات من نفس المحل» يفتح صفحته.
  void rememberStore(Store store) => _stores[store.id] = store;

  Store? storeFor(String? storeId) => storeId == null ? null : _stores[storeId];

  /// يخلّي سلة المحل ده هي الحالية: السلة الحالية تتحفظ (لو فيها حاجة)،
  /// وسلة المحل ترجع لو كانت محفوظة، وإلا تبدأ سلة فاضية.
  void switchTo(String storeId) {
    if (active.storeId == storeId) return;
    final current = active.snapshot();
    final target = _parked.remove(storeId);
    if (!current.isEmpty && current.storeId != null) {
      _parked[current.storeId!] = current;
    }
    if (target != null) {
      active.restore(target);
    } else {
      active.clear();
    }
    notifyListeners();
  }

  /// يمسح سلة محفوظة.
  void removeParked(String storeId) {
    if (_parked.remove(storeId) != null) notifyListeners();
  }

  /// تسجيل خروج: كل السلال تتمسح.
  void clearAll() {
    _parked.clear();
    _stores.clear();
    active.clear();
    notifyListeners();
  }
}

/// «سلّاتي» المشتركة في التطبيق كله.
final CartBook carts = CartBook(cart);
