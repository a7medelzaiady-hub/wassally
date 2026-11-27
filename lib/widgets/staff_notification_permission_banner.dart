import 'package:flutter/material.dart';

import '../services/notification_service.dart';

/// Small, staff-only callout. Queries Android permission status, never Firestore.
class StaffNotificationPermissionBanner extends StatefulWidget {
  const StaffNotificationPermissionBanner({
    super.key,
    this.checkPermission,
    this.enablePermission,
  });

  final Future<bool> Function()? checkPermission;
  final Future<bool> Function()? enablePermission;

  @override
  State<StaffNotificationPermissionBanner> createState() =>
      _StaffNotificationPermissionBannerState();
}

class _StaffNotificationPermissionBannerState
    extends State<StaffNotificationPermissionBanner> with WidgetsBindingObserver {
  bool? _granted;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final permitted = await (widget.checkPermission ?? NotificationService.hasPermission)();
    if (mounted) setState(() => _granted = permitted);
  }

  Future<void> _enable() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await (widget.enablePermission ?? NotificationService.enableForVerifiedStaff)();
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_granted != false) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsetsDirectional.only(start: 10, end: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_off_outlined, size: 18, color: Color(0xFF8F4E00)),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'الإشعارات مقفولة — مش هيوصلك الطلبات الجديدة',
              maxLines: 2,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _enable,
            style: TextButton.styleFrom(
              minimumSize: const Size(58, 36),
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            child: Text(_busy ? '...' : 'فعّل'),
          ),
        ],
      ),
    );
  }
}
