import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../theme/theme_controller.dart';

/// كارت اختيار لون التطبيق (في صفحة حسابي). الاختيار بيتطبّق فورًا وبيتحفظ على الموبايل.
class ThemePickerCard extends StatelessWidget {
  const ThemePickerCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final current = Brand.palette.id;
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'لون التطبيق',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'اختار اللون اللي يريّحك، وهيتغيّر التطبيق كله.',
                style: TextStyle(fontSize: 12.5, color: kMuted),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final p in AppPalette.all)
                    GestureDetector(
                      onTap: () => ThemeController.instance.select(p),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 48,
                            height: 48,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: p.id == current
                                    ? p.primary
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [p.primaryLight, p.primary],
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                ),
                              ),
                              child: p.id == current
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            p.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: p.id == current
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: p.id == current ? kInk : kMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
