import 'package:flutter/material.dart';


import '../theme/brand.dart';
import '../services/navigation.dart';

/// هيدر بحواف سفلية مدورة وظل خفيف. بيمتد تحت شريط الحالة.
class AppHeader extends StatelessWidget {
  final Widget child;
  final Color color;
  final Gradient? gradient;
  final EdgeInsets padding;

  const AppHeader({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.gradient,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 22),
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      padding: padding.copyWith(top: padding.top + top),
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class HomeActionButton extends StatelessWidget {
  const HomeActionButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'الرئيسية',
    onPressed: () {
      shellTab.value = 0;
      Navigator.of(context).popUntil((route) => route.isFirst);
    },
    icon: const Icon(Icons.home_rounded),
  );
}

/// هيدر لصفحة داخلية: زر رجوع + عنوان (أخضر زي الصفحة الرئيسية).
class InnerHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final bool showHome;
  const InnerHeader({super.key, required this.title, this.trailing, this.showHome = true});

  @override
  Widget build(BuildContext context) {
    return AppHeader(
      gradient: Brand.headerGradient,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            tooltip: 'رجوع',
          ),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          if (showHome) const HomeActionButton(),
          ?trailing,
        ],
      ),
    );
  }
}

/// هيدر رئيسي بلون السمة المختارة مع دوائر زخرفية ناعمة (نفس روح الصفحة الرئيسية).
class BrandHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const BrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  Widget _blob(double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AppHeader(
          gradient: Brand.headerGradient,
          padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(28),
              ),
              child: Stack(
                children: [
                  PositionedDirectional(
                    end: -30,
                    top: -34,
                    child: _blob(120, 0.08),
                  ),
                  PositionedDirectional(
                    start: 60,
                    bottom: -50,
                    child: _blob(110, 0.06),
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
