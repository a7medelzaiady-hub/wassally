import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';

/// يثبت هوية وصّلي الكحلي والبرتقالي على الأجهزة القديمة والجديدة.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _key = 'app_palette';

  AppPalette get palette => Brand.palette;

  /// بتتنادى مرة واحدة قبل runApp.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep the approved navy-and-orange Wasally identity on upgrades too.
      Brand.palette = AppPalette.wasally;
      await prefs.setString(_key, AppPalette.wasally.id);
    } catch (_) {
      // لو فشلت القراءة بنكمّل بالسمة الافتراضية.
    }
  }

  Future<void> select(AppPalette p) async {
    // Other palettes are legacy data, not a user-facing customization.
    if (p.id != AppPalette.wasally.id || Brand.palette.id == p.id) return;
    Brand.palette = p;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, p.id);
    } catch (_) {}
  }
}
