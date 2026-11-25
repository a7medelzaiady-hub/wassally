import 'package:flutter/material.dart';


import '../screens/info_pages.dart' show openWasallyWhatsApp;
import '../screens/main_shell.dart';
import '../theme/brand.dart';
import 'app_header.dart';
import 'panel_switcher.dart';

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
        color: color ?? Brand.greenDark,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
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
      if (!isAdmin)
        _btn(
          tooltip: 'تواصل مع الإدارة',
          icon: Icons.support_agent_outlined,
          onPressed: () => openWasallyWhatsApp('السلام عليكم، عايز أتواصل مع إدارة وصّلي'),
        ),
      _btn(
        tooltip: 'الصفحة الرئيسية',
        icon: Icons.home_filled,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const MainShell()),
        ),
      ),
      if (isAdmin)
        _btn(
          tooltip: 'تبديل الأدوار',
          icon: Icons.swap_horiz_rounded,
          onPressed: () => showPanelSwitcher(context),
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
                            fontSize: 19,
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
