import 'package:flutter/foundation.dart';

import '../models/order.dart';
import '../models/product.dart';
import 'order_service.dart' show kMaxLineQty;

/// أصناف طلب بيتعدّل. صفحة «تعديل الطلب» وصفحة المحل (وهي مفتوحة للتعديل)
/// بيشتغلوا على نفس القائمة، فاللي العميل يضيفه من جوه المحل بيرجع معاه لصفحة
/// التعديل من غير ما يلمس السلة. السعر هنا للعرض؛ الـWorker بيحسبه من الكتالوج.
class OrderEditSession extends ChangeNotifier {
  OrderEditSession(List<OrderLine> lines, {this.maxQty = kMaxLineQty})
      : _lines = List<OrderLine>.of(lines);

  final int maxQty;
  final List<OrderLine> _lines;

  List<OrderLine> get lines => List.unmodifiable(_lines);
  int get length => _lines.length;
  OrderLine operator [](int i) => _lines[i];

  /// عدد الأصناف الفعلية (كميتها أكبر من صفر).
  int get count => _lines.where((l) => l.qty > 0).length;

  double get subtotal => _lines.fold(0.0, (a, l) => a + l.price * l.qty);

  static List<String> _optionNames(Product p) => p.chosen.map((o) => o.name).toList();

  int _indexOf(Product p) {
    if (p.id.isEmpty) return -1;
    final opts = _optionNames(p);
    return _lines.indexWhere((l) => l.productId == p.id && listEquals(l.options, opts));
  }

  int qtyOf(Product p) {
    final i = _indexOf(p);
    return i < 0 ? 0 : _lines[i].qty;
  }

  void setQty(int index, int qty) {
    if (index < 0 || index >= _lines.length || qty < 0 || qty > maxQty) return;
    _lines[index] = _lines[index].withQty(qty);
    notifyListeners();
  }

  /// صنف من المحل (بخياراته): لو موجود الكمية بتزيد، وإلا سطر جديد.
  void add(Product p, {int qty = 1}) {
    if (p.id.isEmpty || qty <= 0) return;
    final i = _indexOf(p);
    if (i >= 0) {
      final next = (_lines[i].qty + qty).clamp(0, maxQty).toInt();
      _lines[i] = _lines[i].withQty(next);
    } else {
      _lines.add(OrderLine(
        p.name,
        p.price,
        qty.clamp(1, maxQty).toInt(),
        p.id,
        _optionNames(p),
        p.chosenTotal,
      ));
    }
    notifyListeners();
  }

  void removeOne(Product p) {
    final i = _indexOf(p);
    if (i < 0 || _lines[i].qty == 0) return;
    setQty(i, _lines[i].qty - 1);
  }
}
