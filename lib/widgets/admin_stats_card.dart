import 'package:flutter/material.dart';

import '../services/staff_order_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// إحصائيات المدير: إجمالي التسليمات والمبالغ المحصّلة وعمولات كل المناديب.
/// المدير بس هو اللي يشوفها (القواعد بتسمح له بقراءة كل الطلبات).
/// الأرقام بتتحسب في السيرفر (aggregation) بقراءة رخيصة، ومن الطلبات المختومة بالتسليم بس
/// (الطلبات اللي اتسلّمت قبل ما الإحصائيات تتفعّل مش بتتحسب).
class AdminStatsCard extends StatefulWidget {
  const AdminStatsCard({super.key});

  @override
  State<AdminStatsCard> createState() => _AdminStatsCardState();
}

class _AdminStatsCardState extends State<AdminStatsCard> {
  bool _today = true;
  late Future<DeliveryStats> _future = _load();

  Future<DeliveryStats> _load() =>
      StaffOrderService.adminStats(since: _today ? startOfToday() : null);

  void _setPeriod(bool today) {
    if (_today == today) return;
    setState(() {
      _today = today;
      _future = _load();
    });
  }

  Widget _tile(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: kPrimary, size: 22),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: kMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'إحصائيات التوصيل',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: const Text('اليوم'),
                selected: _today,
                onSelected: (_) => _setPeriod(true),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: const Text('الإجمالي'),
                selected: !_today,
                onSelected: (_) => _setPeriod(false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<DeliveryStats>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) {
                return Row(
                  children: [
                    const Expanded(child: Text('تعذر تحميل الإحصائيات.')),
                    TextButton(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                );
              }
              final s = snap.data!;
              return Row(
                children: [
                  _tile(
                    Icons.check_circle_outline,
                    'طلبات مسلّمة',
                    '${s.delivered}',
                  ),
                  _tile(
                    Icons.payments_outlined,
                    'إجمالي المحصّل',
                    formatPrice(s.collected),
                  ),
                  _tile(
                    Icons.two_wheeler,
                    'عمولات المناديب',
                    formatPrice(s.earnings),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
