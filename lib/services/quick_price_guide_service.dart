import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quick_price_guide.dart';

/// Reads the price guide once per app session and persists it between launches.
/// Call refresh() explicitly to check whether the remote version changed.
/// Firestore cannot notify about a changed version without a read or listener.
class QuickPriceGuideService {
  QuickPriceGuideService._();

  static const _cacheKey = 'quick_price_guide_cache_v1';
  static QuickPriceGuide? _memory;
  static Future<QuickPriceGuide?>? _pending;

  static Future<QuickPriceGuide?> loadCached() async {
    if (_memory != null) return _memory;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return null;
      return _memory = QuickPriceGuide.fromMap(value);
    } catch (_) {
      await prefs.remove(_cacheKey);
      return null;
    }
  }

  /// Fetches once on first use, otherwise serves cached data with no reads.
  static Future<QuickPriceGuide?> load() async {
    final cached = await loadCached();
    if (cached != null) return cached;
    return refresh();
  }

  /// One Firestore document read, only when explicitly requested.
  /// A version change replaces the local cache; unchanged data is retained.
  static Future<QuickPriceGuide?> refresh() {
    return _pending ??= _refreshOnce().whenComplete(() => _pending = null);
  }

  static Future<QuickPriceGuide?> _refreshOnce() async {
    final cached = await loadCached();
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_info')
          .doc('quick_price_guide')
          .get();
      if (!doc.exists || doc.data() == null) return cached;
      final incoming = QuickPriceGuide.fromMap(doc.data()!);
      if (cached != null && cached.version == incoming.version) return cached;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(doc.data()));
      return _memory = incoming;
    } catch (_) {
      // Offline and permission errors must not discard the saved guide.
      return cached;
    }
  }
}
