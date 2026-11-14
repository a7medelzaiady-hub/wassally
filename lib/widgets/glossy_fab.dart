import 'package:material_ui/material_ui.dart';

import '../theme/brand.dart';

/// زر دائري ثلاثي الأبعاد لامع: تدرّج لوني، لمعة زجاجية، ظل ملوّن، وبيتضغط ويرجع بنعومة.
class GlossyFab extends StatefulWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String? tooltip;
  final double size;
  const GlossyFab({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.size = 60,
  });

  @override
  State<GlossyFab> createState() => _GlossyFabState();
}

class _GlossyFabState extends State<GlossyFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);
  bool _down = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final btn = GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final glow = 0.30 + 0.18 * _pulse.value;
          return AnimatedScale(
            scale: _down ? 0.9 : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.45),
                  radius: 1.05,
                  colors: [Brand.greenLight, Brand.green, Brand.greenDark],
                  stops: const [0.0, 0.55, 1.0],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  // توهّج ملوّن
                  BoxShadow(
                    color: Brand.green.withValues(alpha: glow),
                    blurRadius: 22,
                    spreadRadius: 1,
                    offset: const Offset(0, 8),
                  ),
                  // ظل سفلي يدّي إحساس الارتفاع
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // لمعة زجاجية في النص العلوي
                  Positioned(
                    top: s * 0.07,
                    child: Container(
                      width: s * 0.66,
                      height: s * 0.38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(s),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.65),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    widget.icon,
                    color: Colors.white,
                    size: s * 0.46,
                    shadows: const [
                      Shadow(
                        color: Colors.black38,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return widget.tooltip == null
        ? btn
        : Tooltip(message: widget.tooltip!, child: btn);
  }
}
