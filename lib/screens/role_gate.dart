import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../services/live_alerts_service.dart';
import '../services/auth_service.dart';
import '../services/order_gateway.dart';
import '../widgets/referral_registration_card.dart';
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
  bool _inviteDialogOpen = false;

  void _offerNewAccountInvite() {
    final uid = AuthService.newAccountInvitation.value;
    if (!mounted || _inviteDialogOpen || !OrderGateway.referralCampaignEnabled ||
        uid == null || uid != FirebaseAuth.instance.currentUser?.uid) {
      return;
    }
    _inviteDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || uid != FirebaseAuth.instance.currentUser?.uid) {
        _inviteDialogOpen = false;
        return;
      }
      try {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('أهلًا بيك في وصّلي!'),
            content: SingleChildScrollView(
              child: ReferralRegistrationCard(
                onSubmit: (code) async {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user?.uid != uid) throw StateError('سجّل الدخول من جديد.');
                  final token = await user!.getIdToken();
                  if (token == null || token.isEmpty) {
                    throw StateError('سجّل الدخول من جديد.');
                  }
                  await OrderGateway.claimRegistrationReferral(
                    idToken: token,
                    code: code,
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('متابعة / تخطي الكود'),
              ),
            ],
          ),
        );
      } finally {
        AuthService.dismissNewAccountInvitation(uid);
        _inviteDialogOpen = false;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // بعد تسجيل الدخول: نفعّل إشعارات الجهاز (على أندرويد).
    NotificationService.init();
    roleInfoOverride.addListener(_onOverride);
    AuthService.newAccountInvitation.addListener(_offerNewAccountInvite);
    _offerNewAccountInvite();
    // Existing Firebase sessions also reserve their device, without waiting
    // for another Google sign-in or adding a Firestore listener.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && OrderGateway.referralCampaignEnabled) {
        unawaited(OrderGateway.registerReferralDevice().then((_) {}).catchError((Object error) {
          debugPrint('Referral device binding skipped (normal app use unaffected).');
        }));
      }
    });
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
    AuthService.newAccountInvitation.removeListener(_offerNewAccountInvite);
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
          isQuickCourier: fresh.quickCourier,
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
    // The same branded entry appears after sign-in for every role.
    // Role-specific dashboards stay isolated; this is presentation/navigation only.
    switch (role) {
      case AppRole.admin:
        return CustomerEntry(
          key: const ValueKey('welcome-admin'),
          dashboard: AdminOrdersPage(name: name),
          dashboardLabel: 'لوحة الإدارة',
        );
      case AppRole.courier:
        return CustomerEntry(
          key: const ValueKey('welcome-courier'),
          dashboard: CourierOrdersPage(name: name),
          dashboardLabel: 'لوحة المندوب',
        );
      case AppRole.storeOwner:
        return CustomerEntry(
          key: const ValueKey('welcome-store'),
          dashboard: StoreOwnerPage(
            storeId: info.storeId,
            name: name,
            pendingApproval: info.pendingStoreOwner,
          ),
          dashboardLabel: 'لوحة المحل',
        );
      case AppRole.supervisor:
        return CustomerEntry(
          key: const ValueKey('welcome-supervisor'),
          dashboard: SupervisorPage(name: name),
          dashboardLabel: 'لوحة المشرف',
        );
      case AppRole.customer:
        return const CustomerEntry(key: ValueKey('welcome-customer'));
    }
  }
}
