import 'package:flutter/material.dart';

import '../widgets/app_header.dart';
import '../widgets/dialogs.dart';
import '../services/auth_service.dart';
import '../services/order_gateway.dart';
import 'referral_campaign_page.dart';
import 'admin_stores_page.dart';
import 'admin_roles_page.dart';
import 'admin_store_owners_page.dart';
import 'admin_tools_page.dart';
import 'admin_couriers_board_page.dart';
import 'admin_operations_report_page.dart';
import 'admin_inbox_page.dart';

/// أدوات الإدارة في صفحة مستقلة، مع عناوين واضحة لكل وظيفة.
class AdminNavigationPage extends StatelessWidget {
  const AdminNavigationPage({super.key});

  Future<void> _logout(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'تسجيل خروج',
      message: 'متأكد إنك عايز تسجّل خروج؟',
      confirmLabel: 'خروج',
      destructive: true,
    );
    if (ok && context.mounted) await AuthService.signOut(context);
  }

  @override
  Widget build(BuildContext context) {
    final items = <({String title, String subtitle, IconData icon, Widget page})>[
      (title: 'المحلات والأصناف', subtitle: 'إدارة المحلات والمنتجات', icon: Icons.store_mall_directory_outlined, page: const AdminStoresPage()),
      (title: 'إدارة المناديب', subtitle: 'الحسابات والصلاحيات', icon: Icons.delivery_dining_outlined, page: const AdminRolesPage()),
      (title: 'أصحاب المحلات', subtitle: 'الربط وإدارة الحسابات', icon: Icons.manage_accounts_outlined, page: const AdminStoreOwnersPage()),
      if (OrderGateway.referralCampaignEnabled)
        (title: 'إدارة الإحالات', subtitle: 'أكواد المسوقين والمكافآت', icon: Icons.card_giftcard, page: const AdminReferralCampaignPage()),
      (title: 'إعدادات التشغيل', subtitle: 'إعدادات التطبيق والخدمة', icon: Icons.tune_rounded, page: const AdminToolsPage()),
      (title: 'ترتيب المناديب', subtitle: 'متابعة أداء المناديب', icon: Icons.leaderboard_outlined, page: const AdminCouriersBoardPage()),
      (title: 'تقرير التشغيل', subtitle: 'إحصائيات وتقارير', icon: Icons.assessment_outlined, page: const AdminOperationsReportPage()),
      (title: 'طلبات الانضمام والمراجعات', subtitle: 'الطلبات التي تحتاج مراجعة', icon: Icons.inbox_outlined, page: const AdminInboxPage()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('أدوات الإدارة'), actions: const [HomeActionButton()]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded, color: Colors.red),
            label: const Text('تسجيل الخروج', style: TextStyle(color: Colors.red)),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 650 ? 3 : 2;
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 155,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => item.page),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(item.icon, size: 34, color: const Color(0xFF087653)),
                        const SizedBox(height: 10),
                        Text(item.title, textAlign: TextAlign.center, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(item.subtitle, textAlign: TextAlign.center, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
