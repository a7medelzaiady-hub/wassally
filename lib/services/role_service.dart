import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_role.dart';

class RoleInfo {
  final AppRole role;
  final String name;

  /// المحل اللي صاحبه بيديره.
  final String storeId;

  /// كل الأدوار التي يمتلكها الحساب.
  final Set<AppRole> roles;

  const RoleInfo(
    this.role, [
    this.name = '',
    this.storeId = '',
    this.roles = const {},
  ]);

  Set<AppRole> get held => roles.isEmpty ? {role} : roles;
}

class RoleService {
  const RoleService._();

  static String? _cachedUid;
  static RoleInfo? _cached;

  static RoleInfo? cachedFor(String uid) {
    return _cachedUid == uid ? _cached : null;
  }

  static RoleInfo _remember(String uid, RoleInfo info) {
    _cachedUid = uid;
    _cached = info;
    _save(uid, info);
    return info;
  }

  static Future<void> _save(String uid, RoleInfo info) async {
    try {
      final p = await SharedPreferences.getInstance();

      await p.setString(
        'role_$uid',
        jsonEncode({
          'r': info.role.name,
          'n': info.name,
          's': info.storeId,
          'ro': [for (final r in info.held) r.name],
        }),
      );
    } catch (_) {}
  }

  /// تحميل آخر دور محفوظ على الجهاز.
  /// هذه البيانات للعرض السريع فقط وليست مصدرًا للصلاحيات.
  static Future<RoleInfo?> loadSaved(String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('role_$uid');

      if (raw == null) return null;

      final m = jsonDecode(raw) as Map<String, dynamic>;

      final role = AppRole.values.byName((m['r'] ?? 'customer').toString());

      final roles = <AppRole>{
        for (final x in (m['ro'] as List? ?? const []))
          AppRole.values.byName(x.toString()),
      };

      return RoleInfo(
        role,
        (m['n'] ?? '').toString(),
        (m['s'] ?? '').toString(),
        roles,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>?> _safeGet(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      return await ref.get();
    } catch (_) {
      return null;
    }
  }

  /// تحديد دور المستخدم الحالي من Firestore وFirebase Auth.
  static Future<RoleInfo> load() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const RoleInfo(AppRole.customer);
    }

    final db = FirebaseFirestore.instance;

    // قراءة الأدوار بالتوازي.
    final courierF = _safeGet(db.collection('couriers').doc(user.uid));

    final ownerF = _safeGet(db.collection('storeOwners').doc(user.uid));

    final supF = _safeGet(db.collection('supervisors').doc(user.uid));

    // فحص الأدمن.
    var adminChecked = false;
    var isAdmin = false;
    var adminName = '';

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (attempt > 0) {
          await user.getIdToken(true);

          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }

        final claims = (await user.getIdTokenResult()).claims;

        final admin = await db.collection('admins').doc(user.uid).get();

        adminChecked = true;

        isAdmin = admin.exists || claims?['admin'] == true;

        adminName = (admin.data()?['name'] ?? '').toString();

        break;
      } catch (_) {}
    }

    // بيانات المندوب.
    final courier = await courierF;
    final cData = courier?.data();

    final isCourier =
        courier != null &&
        courier.exists &&
        ((cData?['active'] as bool?) ?? true);

    // بيانات صاحب المحل.
    final owner = await ownerF;
    final oData = owner?.data();

    final storeId = (oData?['storeId'] ?? '').toString();

    final isOwner =
        owner != null &&
        owner.exists &&
        ((oData?['active'] as bool?) ?? true) &&
        storeId.isNotEmpty;

    // بيانات المشرف.
    final sup = await supF;
    final sData = sup?.data();

    final isSup =
        sup != null && sup.exists && ((sData?['active'] as bool?) ?? true);

    // جميع الأدوار التي يمتلكها المستخدم.
    final roles = <AppRole>{
      if (isAdmin) AppRole.admin,
      if (isSup) AppRole.supervisor,
      if (isCourier) AppRole.courier,
      if (isOwner) AppRole.storeOwner,
    };

    // تحديد الدور الأساسي.
    final AppRole primary = isAdmin
        ? AppRole.admin
        : isSup
        ? AppRole.supervisor
        : isCourier
        ? AppRole.courier
        : isOwner
        ? AppRole.storeOwner
        : AppRole.customer;

    // تحديد الاسم حسب الدور الأساسي.
    final name = switch (primary) {
      AppRole.admin => adminName,
      AppRole.supervisor => (sData?['name'] ?? '').toString(),
      AppRole.courier => (cData?['name'] ?? '').toString(),
      AppRole.storeOwner => (oData?['name'] ?? '').toString(),
      AppRole.customer => '',
    };

    final info = RoleInfo(primary, name, isOwner ? storeId : '', roles);

    // لا نحفظ العميل إذا لم ينجح التحقق من الأدمن.
    return (adminChecked || primary != AppRole.customer)
        ? _remember(user.uid, info)
        : info;
  }
}
