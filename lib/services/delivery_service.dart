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
  static bool _ordersPaused = false;

  /// مفتاح الطوارئ من الإدارة (آخر قيمة اتقرت).
  static bool get ordersPaused => _ordersPaused;

  /// `ordersPaused` لازم تكون true صريحة؛ أي قيمة تانية = الطلبات شغالة.
  static bool parseOrdersPaused(Map<String, dynamic>? data) =>
      data?['ordersPaused'] == true;

  /// قراءة جديدة للمستند وقت إرسال الطلب (قراءة واحدة) عشان الإيقاف يظهر فورًا.
  /// لو القراءة فشلت (مثلًا من غير نت) بنرجع آخر قيمة معروفة، ومنعش العميل.
  static Future<bool> checkOrdersPaused() async {
    await load(force: true);
    return _ordersPaused;
  }

  static Future<List<DeliveryArea>> load({bool force = false}) async {
    if (_cache != null && !force) return _cache!;
    try {
      final snap = await _ref.get();
      _ordersPaused = parseOrdersPaused(snap.data());
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
      // merge: من غير ما نمسح باقي الحقول (maxOrdersPerDay وordersPaused).
    }, SetOptions(merge: true));
    _cache = List.of(areas);
  }

  /// تشغيل/إيقاف استقبال الطلبات الجديدة (الإدارة بس، حسب قواعد app_info).
  static Future<void> setOrdersPaused(bool paused) async {
    await _ref.set({
      'ordersPaused': paused,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _ordersPaused = paused;
  }
}
