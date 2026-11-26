import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «وضع توفير الباقة»: لما يكون شغال، صور Cloudinary بتتطلب بعرض أصغر
/// وجودة أقل (q_auto:eco) علشان تستهلك باقة أقل.
/// الاختيار متخزّن على الموبايل بس: صفر قراءات وصفر كتابات في Firestore.
class DataSaver {
  DataSaver._();

  static const prefsKey = 'data_saver_enabled';

  /// نسبة تصغير عرض الصورة في وضع التوفير.
  static const widthFactor = 0.6;

  /// أقل عرض نطلبه حتى في وضع التوفير، علشان الصور الصغيرة ما تبوظش.
  static const minWidth = 80;

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// بتتنادى مرة واحدة قبل runApp.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(prefsKey) ?? false;
    } catch (_) {
      // لو فشلت القراءة بنكمّل بالجودة العادية.
    }
  }

  static Future<void> set(bool value) async {
    enabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, value);
    } catch (_) {}
  }

  /// العرض اللي هيتطلب فعلًا حسب الوضع الحالي.
  static int width(int requested, {bool? saver}) {
    final on = saver ?? enabled.value;
    if (!on) return requested;
    final w = (requested * widthFactor).round();
    return w < minWidth ? (requested < minWidth ? requested : minWidth) : w;
  }

  /// قيمة الجودة في رابط Cloudinary.
  static String quality({bool? saver}) =>
      (saver ?? enabled.value) ? 'q_auto:eco' : 'q_auto';
}
