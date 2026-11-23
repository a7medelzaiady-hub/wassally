import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';
import 'read_meter.dart';

/// بيانات المستخدم (الاسم، الموبايل، العنوان) المحفوظة في users/{uid}.
class UserService {
  const UserService._();

  static DocumentReference? _doc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  static Stream<UserProfile> watch() {
    final doc = _doc();
    if (doc == null) return Stream<UserProfile>.empty();
    return doc.snapshots().metered('user:doc').map(
      (s) => UserProfile.fromMap(s.data() as Map<String, dynamic>?),
    );
  }

  static Future<UserProfile> load() async {
    final doc = _doc();
    if (doc == null) return const UserProfile();
    try {
      final snap = await doc.get();
      return UserProfile.fromMap(snap.data() as Map<String, dynamic>?);
    } catch (_) {
      return const UserProfile();
    }
  }

  static Future<void> save(UserProfile profile) async {
    final doc = _doc();
    if (doc == null) return;
    await doc.set(profile.toMap(), SetOptions(merge: true));
  }

  /// هل المستخدم الحالي أدمن؟
  static Future<bool> isAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('admins')
          .doc(user.uid)
          .get();
      return snap.exists;
    } catch (_) {
      return false;
    }
  }
}
