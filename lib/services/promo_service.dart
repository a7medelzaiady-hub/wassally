import 'package:cloud_firestore/cloud_firestore.dart';

class PromoResult {
  final String code;
  final double percent;
  const PromoResult(this.code, this.percent);
}

/// كوبونات الخصم: promos/{CODE} = { percent, active, note }.
class PromoService {
  const PromoService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('promos');

  static String normalize(String c) =>
      c.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// بترجع الكوبون لو صالح، أو null لو غلط/موقوف.
  static Future<PromoResult?> check(String raw) async {
    final code = normalize(raw);
    if (code.isEmpty) return null;
    try {
      final snap = await _col.doc(code).get();
      final m = snap.data();
      if (m == null || m['active'] != true) return null;
      final pct = (m['percent'] as num?)?.toDouble() ?? 0;
      if (pct <= 0 || pct > 50) return null;
      return PromoResult(code, pct);
    } catch (_) {
      return null;
    }
  }
}
