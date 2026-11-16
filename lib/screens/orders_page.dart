import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/navigation.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/empty_state.dart';
import 'order_details_page.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  late final Stream<List<AppOrder>> _orders = OrderService.watchMyOrders();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const BrandHeader(title: 'طلباتي', subtitle: 'تابع حالة طلباتك'),
        Expanded(
          child: Container(
            color: kBg,
            child: StreamBuilder<List<AppOrder>>(
              stream: _orders,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const EmptyState(
                    icon: Icons.cloud_off,
                    title: 'تعذر تحميل الطلبات',
                    message: 'تحقق من الاتصال والصلاحيات وحاول تاني.',
                  );
                }
                if (!snapshot.hasData) {
                  return Center(
                    child: CircularProgressIndicator(color: Brand.green),
                  );
                }
                final orders = snapshot.data!;
                if (orders.isEmpty) {
                  return EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'لسه مفيش طلبات',
                    message: 'أول ما تطلب هتلاقي طلبك وحالته هنا.',
                    actionLabel: 'ابدأ الطلب',
                    onAction: () => shellTab.value = 0,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) => _OrderCard(order: orders[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

String _dateText(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// وقت بنظام 12 ساعة مع ص/م، والدقايق دايمًا رقمين (8:02 مش 8:2).
String _timeText(DateTime d) {
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final suffix = d.hour < 12 ? 'ص' : 'م';
  return '$h12:${_two(d.minute)} $suffix';
}

class _OrderCard extends StatefulWidget {
  final AppOrder order;
  const _OrderCard({required this.order});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _busy = false;

  Future<void> _hide() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إخفاء الطلب من السجل'),
        content: const Text('سيختفي الطلب من قائمة طلباتك فقط، وسيظل محفوظًا لدى وصلي لمتابعة المعاملة وحل أي مشكلة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إخفاء')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await OrderService.hideFromCustomer(widget.order.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إخفاء الطلب من سجلّك.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final status = order.status;
    final created = order.createdAt;
    final name = order.storeName.isEmpty ? 'طلب' : order.storeName;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kLine),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OrderDetailsPage(orderId: order.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                          color: Brand.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatPrice(order.payable),
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Brand.goldDeep,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (created != null)
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          _dateText(created),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: kMuted,
                          ),
                        ),
                      ),
                    if (created != null)
                      Text(
                        _timeText(created),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: kMuted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: kLine),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: status.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: status.color,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_busy)
                      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      IconButton(
                        tooltip: 'إخفاء الطلب من السجل',
                        visualDensity: VisualDensity.compact,
                        onPressed: _hide,
                        icon: const Icon(Icons.delete_outline_rounded),
                        color: kDanger,
                      ),
                    Text(
                      'التفاصيل',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kMuted,
                      ),
                    ),
                    Icon(Icons.chevron_left_rounded, color: kMuted, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
