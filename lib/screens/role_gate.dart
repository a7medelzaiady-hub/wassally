import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../services/live_alerts_service.dart';
import '../services/navigation.dart';
import '../services/notification_service.dart';
import '../services/role_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import 'admin_orders_page.dart';
import 'courier_orders_page.dart';
import 'categories_landing_page.dart';
import 'store_owner_page.dart';
import 'supervisor_page.dart';

/// بعد تسجيل الدخول: بتفتح الشاشة المناسبة لدور المستخدم.
class RoleGate extends StatefulWidget {
  const RoleGate({super.key});

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  String _uid = '';
  RoleInfo? _info;

  @override
  void initState() {
    super.initState();
    // بعد تسجيل الدخول: نفعّل إشعارات الجهاز (على أندرويد).
    NotificationService.init();
    roleInfoOverride.addListener(_onOverride);
    // تذكير التحديث لكل الأدوار (مش العملاء بس). الفحص مرة واحدة في الجلسة.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.checkForUpdates(context);
    });
  }

  void _onOverride() {
    final i = roleInfoOverride.value;
    if (i != null && mounted) {
      setState(() => _info = i);
      _startAlerts(i);
    }
  }

  /// تنبيهات الدردشة والشكاوى اللحظية (المدير بياخد تنبيهات زيادة).
  void _startAlerts(RoleInfo info) {
    if (info.pendingStoreOwner && info.held.length == 1) {
      LiveAlerts.stop();
      return;
    }
    LiveAlerts.start(
      isAdmin: info.held.contains(AppRole.admin),
      storeId: info.held.contains(AppRole.storeOwner) ? info.storeId : '',
      isCourier: info.held.contains(AppRole.courier),
    );
  }

  @override
  void dispose() {
    roleInfoOverride.removeListener(_onOverride);
    super.dispose();
  }

  /// بنفتح بآخر دور محفوظ فورًا (من غير انتظار الشبكة)، وبعدها نتحقق من السيرفر
  /// ونبدّل الشاشة لو الدور اتغيّر. الصلاحيات الفعلية دايمًا بتتحمي بقواعد Firestore.
  void _start(String uid) {
    _uid = uid;
    activePanel.value = null;
    _info = RoleService.cachedFor(uid);
    final cached = _info;
    if (cached != null) _startAlerts(cached);
    if (_info == null) {
      RoleService.loadSaved(uid).then((saved) {
        if (mounted && _uid == uid && _info == null && saved != null) {
          setState(() => _info = saved);
          _startAlerts(saved);
        }
      });
    }
    RoleService.load().then((fresh) {
      if (mounted && _uid == uid) {
        setState(() => _info = fresh);
        _startAlerts(fresh);
        // Only the freshly verified role controls FCM courier subscriptions.
        unawaited(NotificationService.syncCourierTopic(
          isCourier: fresh.held.contains(AppRole.courier),
        ));
        unawaited(NotificationService.syncAdminTopic(
          isAdmin: fresh.held.contains(AppRole.admin),
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('رجاء تسجيل الدخول أولاً')),
      );
    }

    if (_uid != user.uid) _start(user.uid);

    final info = _info;
    if (info == null) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }
    return ValueListenableBuilder<AppRole?>(
      valueListenable: activePanel,
      builder: (context, panel, _) {
        final role = (panel != null && info.held.contains(panel))
            ? panel
            : info.role;
        return _panelFor(role, info, user);
      },
    );
  }

  Widget _panelFor(AppRole role, RoleInfo info, User user) {
    final name = info.name.isNotEmpty ? info.name : (user.displayName ?? '');
    switch (role) {
      case AppRole.admin:
        return AdminOrdersPage(name: name);
      case AppRole.courier:
        return CourierOrdersPage(name: name);
      case AppRole.storeOwner:
        return StoreOwnerPage(
          storeId: info.storeId,
          name: name,
          pendingApproval: info.pendingStoreOwner,
        );
      case AppRole.supervisor:
        return SupervisorPage(name: name);
      case AppRole.customer:
        return const CustomerEntry();
    }
  }
}
