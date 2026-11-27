import 'package:shared_preferences/shared_preferences.dart';

import '../utils/delivery_eta.dart';

/// وقت توصيل كل محل («25-35 د») زي ما اتحمّل مع المحل، محفوظ على الموبايل،
/// عشان صفحة الدفع وتفاصيل الطلب يعرضوا الوقت المتوقع من غير أي قراءة.
class StoreEta {
  StoreEta._();

  static const _prefix = 'store_eta_';
  static final Map<String, String> _memory = {};

  /// بيتنده لما المحل يتحفظ مع السلة (CartBook.rememberStore).
  static void remember(String storeId, String time) {
    if (storeId.isEmpty) return;
    final t = time.trim();
    if (_memory[storeId] == t) return;
    _memory[storeId] = t;
    SharedPreferences.getInstance()
        .then((p) => t.isEmpty ? p.remove('$_prefix$storeId') : p.setString('$_prefix$storeId', t))
        .catchError((_) => false);
  }

  static Future<EtaRange> rangeFor(String storeId) async {
    var raw = _memory[storeId];
    if (raw == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString('$_prefix$storeId');
        if (raw != null) _memory[storeId] = raw;
      } catch (_) {}
    }
    return storeEtaOrDefault(raw);
  }

  static void clearMemoryForTests() => _memory.clear();
}
