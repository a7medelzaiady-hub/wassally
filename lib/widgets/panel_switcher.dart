import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../models/app_role.dart';
import '../screens/main_shell.dart';
import '../services/navigation.dart';
import '../services/role_service.dart';
import '../theme/app_theme.dart';

/// بيفتح قايمة بكل اللوحات اللي حسابك له صلاحية عليها (أدمن / محل / مندوب) + عرض كعميل.
Future<void> showPanelSwitcher(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final info = RoleService.cachedFor(uid);
  final held = info?.held ?? const <AppRole>{};
  final current = activePanel.value ?? info?.role;

  final items = <(AppRole, IconData, String, String)>[
    if (held.contains(AppRole.admin))
      (
        AppRole.admin,
        Icons.admin_panel_settings_outlined,
        'لوحة الأدمن',
        'إدارة الطلبات والمحلات والمناديب',
      ),
    if (held.contains(AppRole.storeOwner))
      (
        AppRole.storeOwner,
        Icons.inventory_2_outlined,
        'لوحة المحل',
        'طلبات المحل وأصنافه وعروضه',
      ),
    if (held.contains(AppRole.courier) || held.contains(AppRole.admin))
      (
        AppRole.courier,
        Icons.two_wheeler_rounded,
        'لوحة المندوب',
        'طلبات التوصيل وإحصائياتك',
      ),
  ];

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kLine,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'تبديل اللوحة',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: kInk,
              ),
            ),
            const SizedBox(height: 8),
            for (final it in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: kPrimarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(it.$2, color: kPrimary),
                ),
                title: Text(
                  it.$3,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(it.$4, style: const TextStyle(fontSize: 12)),
                trailing: current == it.$1
                    ? Icon(Icons.check_circle, color: kPrimary)
                    : null,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  // الأدمن بيفتح لوحة المندوب لأول مرة: نسجّله كمندوب الأول.
                  if (it.$1 == AppRole.courier &&
                      !held.contains(AppRole.courier)) {
                    final u = FirebaseAuth.instance.currentUser;
                    if (u == null) return;
                    try {
                      await FirebaseFirestore.instance
                          .collection('couriers')
                          .doc(u.uid)
                          .set({
                            'name': u.displayName ?? 'مدير',
                            'phone': '',
                            'active': true,
                          }, SetOptions(merge: true));
                      roleInfoOverride.value = await RoleService.load();
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تعذر تفعيل لوحة المندوب.'),
                          ),
                        );
                      }
                      return;
                    }
                  }
                  if (!context.mounted) return;
                  // نقفل أي شاشات مفتوحة فوق اللوحة ونبدّل.
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  activePanel.value = it.$1;
                },
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: kPrimarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.person_outline_rounded, color: kPrimary),
              ),
              title: Text(
                held.contains(AppRole.admin) ? 'الصفحة الرئيسية' : 'عرض كعميل',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                held.contains(AppRole.admin)
                    ? 'تصفّح المحلات وعدّل أي محل أو صنف'
                    : 'شوف التطبيق زي ما بيشوفه العميل',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const MainShell()));
              },
            ),
          ],
        ),
      ),
    ),
  );
}
