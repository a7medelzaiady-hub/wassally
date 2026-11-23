import 'package:flutter/material.dart';

import '../theme/brand.dart';

class AppNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
  const AppNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge = 0,
  });
}

/// شريط سفلي ثابت: كل أيقونة داخل مساحتها فوق اسمها، بدون زر مركزي عائم
/// يمنع ظهور أيقونة السلة وكأنها زر ثانٍ فوق تبويب السلة.
class CurvedNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<AppNavItem> items;
  const CurvedNavBar({
    super.key,
    required this.index,
    required this.onTap,
    required this.items,
  });

  Widget _icon(AppNavItem item, IconData data, Color color) {
    final icon = Icon(data, color: color, size: 23);
    if (item.badge <= 0) return icon;
    return Badge(label: Text(item.badge > 99 ? '99+' : '${item.badge}'), child: icon);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: 68 + bottom,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Brand.palette.line)),
        boxShadow: const [
          BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, -3)),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                label: items[i].label,
                child: InkResponse(
                  onTap: () => onTap(i),
                  radius: 34,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _icon(
                          items[i],
                          i == index ? items[i].selectedIcon : items[i].icon,
                          i == index ? Brand.green : Brand.palette.muted,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          items[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.1,
                            fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                            color: i == index ? Brand.green : Brand.palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
