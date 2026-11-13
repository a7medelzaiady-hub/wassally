import 'package:cloud_firestore/cloud_firestore.dart';

/// منطقة توصيل بسعرها.
class DeliveryArea {
  final String name;
  final double fee;
  const DeliveryArea(this.name, this.fee);
}

/// مناطق التوصيل في مستند واحد app_info/delivery_areas = { areas: [{name, fee}], fees: [..] }.
/// حقل fees نسخة من الأسعار بتستخدمها قواعد الأمان للتأكد إن سعر الطلب من سعر منطقة حقيقي.
class DeliveryService {
  const DeliveryService._();

  static DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('app_info').doc('delivery_areas');

  static List<DeliveryArea>? _cache;

  static Future<List<DeliveryArea>> load({bool force = false}) async {
    if (_cache != null && !force) return _cache!;
    try {
      final snap = await _ref.get();
      final raw = snap.data()?['areas'];
      final out = <DeliveryArea>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final name = (e['name'] ?? '').toString().trim();
          final fee = (e['fee'] as num?)?.toDouble();
          if (name.isNotEmpty && fee != null && fee >= 0) {
            out.add(DeliveryArea(name, fee));
          }
        }
      }
      return _cache = out;
    } catch (_) {
      return _cache ?? const [];
    }
  }

  static Future<void> save(List<DeliveryArea> areas) async {
    await _ref.set({
      'areas': [
        for (final a in areas) {'name': a.name, 'fee': a.fee},
      ],
      'fees': [for (final a in areas) a.fee],
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _cache = List.of(areas);
  }
}
