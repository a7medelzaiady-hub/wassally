import 'package:flutter/material.dart';

import '../models/store.dart';
import '../services/cart_model.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'app_image.dart';

class StoreCard extends StatelessWidget {
  final Store store;
  final VoidCallback onTap;
  const StoreCard({super.key, required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F1F4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // الصورة مع شارة التقييم
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppImage(
                      url: store.imageUrl,
                      fallbackIcon: store.icon,
                      color: store.color,
                      width: 92,
                      height: 92,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    if (store.rating > 0)
                      Positioned(
                        bottom: -8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x22000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 14, color: Color(0xFFFFB400)),
                                const SizedBox(width: 2),
                                Text(
                                  store.rating.toStringAsFixed(1),
                                  style: text.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: store.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          store.category,
                          style: text.labelSmall?.copyWith(
                            color: store.color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        store.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          if (store.time.isNotEmpty)
                            _Info(
                              icon: Icons.schedule_rounded,
                              color: kMuted,
                              label: store.time,
                            ),
                          _Info(
                            icon: Icons.delivery_dining_rounded,
                            color: kPrimary,
                            label:
                                'توصيل ${formatPrice(CartModel.deliveryFee)}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_left_rounded,
                    color: kMuted, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _Info({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
        ),
      ],
    );
  }
}
