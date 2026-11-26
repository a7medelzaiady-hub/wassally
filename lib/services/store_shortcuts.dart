import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مفضلة وآخر محلات على الجهاز فقط. لا قراءات أو كتابات Firebase.
/// تُفصل المفاتيح حسب UID لتجنب خلط تفضيلات حسابين على نفس الجهاز.
class StoreShortcuts extends ChangeNotifier {
  StoreShortcuts();

  String? _accountId;
  final Set<String> _favorites = {};
  final List<String> _recent = [];

  Set<String> get favorites => Set.unmodifiable(_favorites);
  List<String> get recent => List.unmodifiable(_recent);
  bool isFavorite(String storeId) => _favorites.contains(storeId);
  static const int maxRecent = 12;

  static String _favoritesKey(String uid) => 'store_favorites_v1_$uid';
  static String _recentKey(String uid) => 'store_recent_v1_$uid';

  Future<void>? _initialLoad;

  Future<void> load(String? userId) async {
    if (userId == null || userId.isEmpty) {
      _accountId = null;
      _initialLoad = null;
      _favorites.clear();
      _recent.clear();
      notifyListeners();
      return;
    }
    if (_accountId == userId) {
      await _initialLoad;
      return;
    }
    _accountId = userId;
    _favorites.clear();
    _recent.clear();
    notifyListeners();
    final pending = _readForAccount(userId);
    _initialLoad = pending;
    await pending;
    if (identical(_initialLoad, pending)) _initialLoad = null;
  }

  Future<void> _readForAccount(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList(_favoritesKey(userId)) ?? const <String>[];
    final recent = prefs.getStringList(_recentKey(userId)) ?? const <String>[];
    if (_accountId != userId) return; // تسجيل الدخول تغيّر أثناء التحميل.
    _favorites.addAll(favorites.where((s) => s.isNotEmpty));
    _recent.addAll(recent.where((s) => s.isNotEmpty).take(maxRecent));
    notifyListeners();
  }

  Future<void> toggleFavorite(String userId, String storeId) async {
    await load(userId);
    if (_accountId != userId || storeId.isEmpty) return;
    if (!_favorites.remove(storeId)) _favorites.add(storeId);
    notifyListeners();
    final list = _favorites.toList()..sort();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey(userId), list);
  }

  Future<void> recordVisit(String userId, String storeId) async {
    await load(userId);
    if (_accountId != userId || storeId.isEmpty) return;
    _recent.remove(storeId);
    _recent.insert(0, storeId);
    if (_recent.length > maxRecent) _recent.removeRange(maxRecent, _recent.length);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentKey(userId), _recent);
  }
}

/// نفس الحالة داخل التطبيق بدون خدمات خلفية أو استعلامات.
final storeShortcuts = StoreShortcuts();
