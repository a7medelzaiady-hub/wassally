import 'package:flutter/material.dart';

import '../screens/admin_tools_page.dart';
import '../screens/admin_couriers_board_page.dart';
import '../screens/admin_inbox_page.dart';
import '../screens/admin_roles_page.dart';
import '../screens/admin_store_owners_page.dart';
import '../screens/admin_stores_page.dart';
import '../screens/support_chat_page.dart';
import '../services/auth_service.dart';
import '../theme/brand.dart';
import 'app_header.dart';
import 'dialogs.dart';
import 'panel_switcher.dart';
import '../screens/main_shell.dart';

/// هيدر شاشات المدير والمندوب: العنوان + عرض كعميل + تسجيل خروج.
class StaffHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isAdmin;
  const StaffHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.isAdmin = false,
  });

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

  Widget _btn({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 22),
        color: color ?? Colors.white,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _circle(double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (isAdmin)
        _btn(
          tooltip: 'المحلات والأصناف',
          icon: Icons.store_mall_directory_outlined,
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const AdminStoresPage())),
        ),
      if (isAdmin)
        _btn(
          tooltip: 'المناديب',
          icon: Icons.admin_panel_settings_outlined,
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const AdminRolesPage())),
        ),
      if (isAdmin)
        _btn(
          tooltip: 'أصحاب المحلات',
          icon: Icons.manage_accounts_outlined,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminStoreOwnersPage()),
          ),
        ),
      if (isAdmin)
        _btn(
          tooltip: 'إعدادات التشغيل',
          icon: Icons.tune_rounded,
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const AdminToolsPage())),
        ),
      if (isAdmin)
        _btn(
          tooltip: 'ترتيب المناديب',
          icon: Icons.leaderboard_outlined,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminCouriersBoardPage()),
          ),
        ),
      if (isAdmin)
        _btn(
          tooltip: 'الطلبات والشكاوى',
          icon: Icons.inbox_outlined,
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const AdminInboxPage())),
        ),
      if (!isAdmin)
        _btn(
          tooltip: 'محادثة مع الإدارة',
          icon: Icons.support_agent_outlined,
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SupportChatPage())),
        ),
      // الأدمن: تبديل بين اللوحات. غيره: زر للرئيسية (شاشة العميل).
      if (isAdmin)
        _btn(
          tooltip: 'تبديل اللوحة',
          icon: Icons.swap_horiz_rounded,
          onPressed: () => showPanelSwitcher(context),
        )
      else
        _btn(
          tooltip: 'الصفحة الرئيسية',
          icon: Icons.home_outlined,
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const MainShell())),
        ),
      _btn(
        tooltip: 'تسجيل خروج',
        icon: Icons.logout,
        color: Colors.white,
        onPressed: () => _logout(context),
      ),
    ];
    return Stack(
      children: [
        AppHeader(
          gradient: Brand.headerGradient,
          padding: const EdgeInsets.fromLTRB(20, 14, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isAdmin) ...buttons,
                ],
              ),
              if (isAdmin) ...[
                const SizedBox(height: 12),
                Wrap(runSpacing: 6, children: buttons),
              ],
            ],
          ),
        ),
        // دوائر زخرفية زي هيدر الرئيسية (بتتقص مع الحواف المدورة)
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(28),
              ),
              child: Stack(
                children: [
                  PositionedDirectional(
                    start: -34,
                    top: -30,
                    child: _circle(120, 0.07),
                  ),
                  PositionedDirectional(
                    end: 70,
                    bottom: -46,
                    child: _circle(110, 0.06),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
