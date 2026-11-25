import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// عنوان التوصيل المحفوظ للمستخدم، مشترك بين صفحة الترحيب والرئيسية.
/// قراءة واحدة فقط لكل حساب في الجلسة (نفس القراءة اللي كانت في الرئيسية).
class SavedAddress {
  SavedAddress._();

  static final ValueNotifier<String> value = ValueNotifier<String>('');
  static String? _loadedFor;
  static Future<void>? _pending;

  static Future<void> load() {
    String? uid;
    try {
      uid = FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return Future.value(); // Firebase not initialized (widget tests).
    }
    if (uid == null) return Future.value();
    if (_loadedFor == uid && _pending != null) return _pending!;
    _loadedFor = uid;
    value.value = '';
    return _pending = _read(uid);
  }

  static Future<void> _read(String uid) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final address = (doc.data()?['address'] ?? '').toString().trim();
      if (_loadedFor == uid && address.isNotEmpty) value.value = address;
    } catch (e) {
      debugPrint('Load address error: $e');
    }
  }

  /// بعد ما المستخدم يغيّر العنوان من الرئيسية.
  static void update(String address) => value.value = address.trim();
}
