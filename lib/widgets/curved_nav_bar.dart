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

/// شريط سفلي منحني: التبويب المحدد بيطلع في زر دائري بارز جوه نتوء في الشريط.
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

  static const double _top = 20; // مساحة بروز الدائرة فوق الشريط
  static const double _barH = 68;
  static const double _circle = 54;

  Widget _icon(AppNavItem it, IconData data, Color color) {
    final icon = Icon(data, color: color, size: 24);
    if (it.badge <= 0) return icon;
    return Badge(label: Text('${it.badge}'), child: icon);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final n = items.length;
    final height = _top + _barH + bottom;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final itemW = w / n;
          final cx = w / 2;
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(end: cx),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (context, x, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BarPainter(
                        cx: x,
                        top: _top,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Positioned(
                    left: x - _circle / 2,
                    top: _top - 18,
                    child: IgnorePointer(
                      child: Container(
                        width: _circle,
                        height: _circle,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: Brand.softGradient,
                          boxShadow: [
                            BoxShadow(
                              color: Brand.green.withValues(alpha: 0.40),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: _icon(
                          items[n ~/ 2],
                          items[n ~/ 2].selectedIcon,
                          Colors.white,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _top,
                    height: _barH,
                    child: Row(
                      children: [
                        for (var i = 0; i < n; i++)
                          Expanded(
                            child: InkResponse(
                              onTap: () => onTap(i),
                              radius: 36,
                              child: Column(
                                children: [
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 26,
                                    child: i == index
                                        ? null
                                        : _icon(
                                            items[i],
                                            items[i].icon,
                                            Brand.palette.muted,
                                          ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    items[i].label,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: i == index
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: i == index
                                          ? Brand.green
                                          : Brand.palette.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final double cx;
  final double top;
  final Color color;
  const _BarPainter({required this.cx, required this.top, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const r = 38.0;
    const depth = 36.0;
    final path = Path()
      ..moveTo(0, top)
      ..lineTo(cx - r - 14, top)
      ..cubicTo(cx - r + 6, top, cx - r + 6, top + depth, cx, top + depth)
      ..cubicTo(cx + r - 6, top + depth, cx + r - 6, top, cx + r + 14, top)
      ..lineTo(size.width, top)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.35), 8, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.cx != cx || old.color != color;
}
