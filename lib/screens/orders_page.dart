import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/navigation.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../utils/store_wait.dart';
import '../widgets/app_header.dart';
import '../widgets/empty_state.dart';
import 'order_details_page.dart';
import 'quick_customer_orders_page.dart';
import '../widgets/app_snack.dart';

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
        // رابط خفيف بدل الزر الكبير الذي كان يستهلك مساحة من قائمة الطلبات.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Semantics(
            button: true,
            label: 'متابعة طلباتك على السريع',
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const QuickCustomerOrdersPage(),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Brand.green.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Brand.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(Icons.bolt_rounded, color: Brand.green, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'طلباتك على السريع',
                          style: TextStyle(
                            color: Brand.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        'متابعة',
                        style: TextStyle(
                          color: Brand.goldDeep,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.chevron_left_rounded, color: Brand.goldDeep, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
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
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
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

/// عرض اسم المحل صريحًا بدون تكرار كلمة «محل» إذا كانت من الاسم الأصلي.
String orderStoreTitle(String storeName) {
  final name = storeName.trim();
  if (name.isEmpty) return 'طلب من محل';
  return name.startsWith('محل ') ? name : 'محل $name';
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(appSnack('تم إخفاء الطلب من سجلّك.'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(appSnack(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final status = order.status;
    // الطلب الجديد ما يتكتبش «المحل استلم الطلب» قبل ما المحل يأكد فعلًا.
    final now = DateTime.now();
    final waitLate = storeWaitStageOf(order, now) == StoreWaitStage.late;
    final statusColor = waitLate ? kDanger : status.color;
    final statusText = customerStatusLabel(order, now);
    final created = order.createdAt;
    final name = orderStoreTitle(order.storeName);

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
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
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
                        fontWeight: FontWeight.w800,
                        color: Brand.goldDeep,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
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
                const SizedBox(height: 9),
                Divider(height: 1, color: kLine),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_busy)
                      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    else if (status.canHideFromHistory)
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
