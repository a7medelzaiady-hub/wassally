import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/order.dart';
import 'edit_order_page.dart';
import '../services/driver_service.dart';
import '../services/order_contact_service.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';

class OrderDetailsPage extends StatelessWidget {
  final String orderId;
  const OrderDetailsPage({super.key, required this.orderId});

  Future<void> _cancel(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmDialog(
      context,
      title: 'إلغاء الطلب',
      message: 'متأكد إنك عايز تلغي الطلب ده؟',
      confirmLabel: 'إلغاء الطلب',
      destructive: true,
    );
    if (!ok) return;
    try {
      await OrderService.cancel(orderId);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر إلغاء الطلب. جرّب تاني.')),
      );
    }
  }

  Future<void> _delete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await confirmDialog(
      context,
      title: 'حذف الطلب',
      message: 'الطلب هيتحذف نهائيًا ومش هيظهر في طلباتك. متأكد؟',
      confirmLabel: 'حذف الطلب',
      destructive: true,
    );
    if (!ok) return;
    try {
      await OrderService.deleteOrder(orderId);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('تم حذف الطلب.')));
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر حذف الطلب. جرّب تاني.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          InnerHeader(title: 'تفاصيل الطلب'),
          Expanded(
            child: StreamBuilder<AppOrder?>(
              stream: OrderService.watchOrder(orderId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const EmptyState(
                    icon: Icons.cloud_off,
                    title: 'تعذر تحميل الطلب',
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: kPrimary),
                  );
                }
                final order = snapshot.data;
                if (order == null) {
                  return const EmptyState(
                    icon: Icons.search_off,
                    title: 'الطلب ده مش موجود',
                  );
                }
                return _DetailsWithContact(
                  order: order,
                  onCancel: () => _cancel(context),
                  onDelete: () => _delete(context),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// بيحمّل بيانات التواصل (العنوان والموبايل) من المستند الخاص مرة واحدة ويمررها للتفاصيل.
class _DetailsWithContact extends StatefulWidget {
  final AppOrder order;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  const _DetailsWithContact({
    required this.order,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  State<_DetailsWithContact> createState() => _DetailsWithContactState();
}

class _DetailsWithContactState extends State<_DetailsWithContact> {
  OrderContact? _contact;
  bool _confirmingDelivery = false;

  Future<void> _confirmDelivery() async {
    if (_confirmingDelivery) return;
    setState(() => _confirmingDelivery = true);
    try {
      await OrderService.confirmDelivery(widget.order);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.order.deliveryMode == 'external'
              ? 'تم تأكيد الاستلام. أكد المحل استلام النقدية لإغلاق الطلب.'
              : 'تم تأكيد استلام طلبك. شكرًا لك.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is StateError ? error.message : 'تعذر تأكيد الاستلام. حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => _confirmingDelivery = false);
    }
  }

  @override
  void initState() {
    super.initState();
    OrderContactService.load(widget.order.id).then((c) {
      if (mounted) setState(() => _contact = c);
    });
    if (widget.order.customerConfirmedAt != null) {
      OrderService.cleanupConfirmedAttachments(widget.order.id).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order.withContact(_contact);
    return _Details(
      order: order,
      onCancel: widget.onCancel,
      onDelete: widget.onDelete,
      onConfirmDelivery: _confirmingDelivery ? null : _confirmDelivery,
      onEdit: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => EditOrderPage(order: order)),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  final AppOrder order;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback? onConfirmDelivery;
  const _Details({
    required this.order,
    required this.onCancel,
    required this.onDelete,
    required this.onEdit,
    required this.onConfirmDelivery,
  });

  BoxDecoration get _card => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: kLine),
  );

  // إظهار حوار التقييم عند استلام الطلب
  void _showRatingDialog(BuildContext context) {
    double rating = 5.0;
    double storeRating = 5.0;
    final commentCtrl = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'قيّم تجربتك',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (order.storeId.isNotEmpty) ...[
                Text(
                  'المحل: ${order.storeName}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: kMuted),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final v = index + 1.0;
                    return IconButton(
                      iconSize: 28,
                      onPressed: () => setDialogState(() => storeRating = v),
                      icon: Icon(
                        v <= storeRating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: kAccent,
                      ),
                    );
                  }),
                ),
                const Divider(),
              ],
              Text(
                'المندوب ${order.courierName}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: kMuted),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starVal = index + 1.0;
                  return IconButton(
                    iconSize: 32,
                    onPressed: () => setDialogState(() => rating = starVal),
                    icon: Icon(
                      starVal <= rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: kAccent,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: commentCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'اكتب كلمة للمندوب (اختياري)...',
                  contentPadding: const EdgeInsets.all(10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: TextStyle(color: kMuted)),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      setDialogState(() => submitting = true);
                      String? err;
                      try {
                        await DriverService.rateDriver(
                          orderId: order.id,
                          driverId: order.courierId,
                          rating: rating,
                          comment: commentCtrl.text.trim(),
                        );
                      } catch (e) {
                        err = e is StateError
                            ? e.message
                            : 'تعذر تقييم المندوب.';
                      }
                      if (order.storeId.isNotEmpty) {
                        try {
                          await RatingService.rateStore(
                            orderId: order.id,
                            storeId: order.storeId,
                            rating: storeRating,
                          );
                        } catch (e) {
                          err ??= e is StateError
                              ? e.message
                              : 'تعذر تقييم المحل.';
                        }
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(err ?? 'شكراً لتقييمك! ❤️')),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
              ),
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('إرسال التقييم 🌟'),
            ),
          ],
        ),
      ),
    );
  }

  // تقييم المحل مستقل عن وجود مندوب؛ بعض الطلبات قد تُسلّم دون إسناد مندوب ظاهر.
  void _showStoreRatingDialog(BuildContext context) {
    double rating = 5;
    bool submitting = false;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('قيّم المحل', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(order.storeName, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final value = i + 1.0;
                  return IconButton(
                    onPressed: () => setDialogState(() => rating = value),
                    icon: Icon(value <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: kAccent, size: 30),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('رجوع')),
            FilledButton(
              onPressed: submitting ? null : () async {
                setDialogState(() => submitting = true);
                String message;
                try {
                  await RatingService.rateStore(orderId: order.id, storeId: order.storeId, rating: rating);
                  message = 'شكراً لتقييم المحل! ❤️';
                } catch (e) {
                  message = e is StateError ? e.message : 'تعذر تسجيل تقييم المحل. حاول مرة أخرى.';
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
              },
              child: submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('إرسال التقييم'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.storeName,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (order.createdAt != null)
                Text(
                  formatDateTime(order.createdAt!),
                  style: text.bodySmall?.copyWith(color: kMuted),
                ),
              const SizedBox(height: 16),
              if (order.status == OrderStatus.cancelled)
                _CancelledBanner(status: order.status)
              else
                _Timeline(current: order.status),
            ],
          ),
        ),

        // 🛵 كارت المندوب مع التقييم
        if (order.courierName.isNotEmpty &&
            order.status != OrderStatus.cancelled) ...[
          const SizedBox(height: 12),
          _DriverCardForCustomer(
            driverName: order.courierName,
            driverPhone: order.courierPhone,
            onRateTap: () => _showRatingDialog(context),
            isDelivered: order.status == OrderStatus.delivered,
          ),
        ],

        if (order.status == OrderStatus.delivered && order.storeId.isNotEmpty && order.courierName.isEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _card,
            child: Row(
              children: [
                Icon(Icons.storefront_outlined, color: kPrimary),
                const SizedBox(width: 10),
                const Expanded(child: Text('شاركنا رأيك في المحل')),
                FilledButton.tonal(
                  onPressed: () => _showStoreRatingDialog(context),
                  child: const Text('تقييم المحل'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'المنتجات',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text('${item.qty} × ${item.name}')),
                      Text(formatPrice(item.total)),
                    ],
                  ),
                ),
              const Divider(height: 22),
              _line('المجموع', formatPrice(order.subtotal)),
              const SizedBox(height: 4),
              _line('رسوم التوصيل', formatPrice(order.courierFee)),
              const SizedBox(height: 8),
              _line('الإجمالي', formatPrice(order.payable), strong: true),
            ],
          ),
        ),
        if (order.specialRequest != null) ...[
          const SizedBox(height: 12),
          _CustomerSpecialRequestCard(request: order.specialRequest!),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'بيانات التوصيل',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (order.address.isNotEmpty)
                _info(Icons.location_on_outlined, order.address),
              if (order.phone.isNotEmpty)
                _info(Icons.phone_outlined, order.phone),
              if (order.courierName.isNotEmpty)
                _info(Icons.delivery_dining, 'المندوب: ${order.courierName}'),
              if (order.notes.isNotEmpty) _info(Icons.edit_note, order.notes),
              if (order.courierNotes.isNotEmpty)
                _info(Icons.two_wheeler_outlined, order.courierNotes),
              _info(Icons.payments_outlined, 'الدفع عند الاستلام'),
            ],
          ),
        ),
        if (order.status == OrderStatus.onTheWay &&
            order.customerDeliveryReportedAt != null &&
            order.customerConfirmedAt == null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7EF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kSuccess),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'المندوب أبلغ إنه سلّمك الطلب. من فضلك أكد الاستلام بعد مراجعة الطلب.',
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.5),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: onConfirmDelivery,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(order.deliveryMode == 'external'
                      ? 'تأكيد استلام الطلب'
                      : 'تأكيد الاستلام وإغلاق الطلب'),
                ),
              ],
            ),
          ),
        ] else if (order.customerConfirmedAt != null &&
            order.deliveryMode == 'external' &&
            order.status == OrderStatus.onTheWay) ...[
          const SizedBox(height: 12),
          const Text(
            'تم تأكيد استلامك. الطلب في انتظار تأكيد المحل استلام النقدية من المندوب.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
        if ([OrderStatus.newOrder, OrderStatus.preparing].contains(order.status) &&
            order.courierId.isEmpty) ...[
          if (order.status == OrderStatus.preparing)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'تقدر تعدّل طلبك لحد ما المندوب يستلمه.',
                style: TextStyle(color: kMuted, fontSize: 12),
              ),
            ),
          if (order.hasUnavailableItems && order.status == OrderStatus.newOrder) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E0),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE59A00)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFE59A00)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'المحل بلّغنا إن الأصناف دي مش متاحة حاليًا: '
                      '${order.unavailableItems.join('، ')}.\n'
                      'اضغط «كمّل من غير الأصناف دي» وهنحسب الإجمالي من جديد، أو ألغي الطلب. '
                      'المحل مش هيبدأ التجهيز قبل ما تختار.',
                      style: const TextStyle(fontWeight: FontWeight.w700, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(
              order.hasUnavailableItems && order.status == OrderStatus.newOrder
                  ? 'كمّل من غير الأصناف دي'
                  : 'تعديل الطلب',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(foregroundColor: kDanger),
                  child: const Text('إلغاء الطلب'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('حذف الطلب'),
                  style: OutlinedButton.styleFrom(foregroundColor: kDanger),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _info(IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: kPrimary),
          const SizedBox(width: 10),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _line(String label, String value, {bool strong = false}) {
    final style = strong
        ? const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)
        : TextStyle(color: kMuted, fontWeight: FontWeight.w600);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}

/// ودجت كارت بيانات المندوب وتقييمه للعميل
class _DriverCardForCustomer extends StatelessWidget {
  final String driverName;
  final String driverPhone;
  final VoidCallback onRateTap;
  final bool isDelivered;

  const _DriverCardForCustomer({
    required this.driverName,
    required this.driverPhone,
    required this.onRateTap,
    required this.isDelivered,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kAccent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kPrimarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.two_wheeler_rounded, color: kPrimary, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'المندوب: $driverName',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                if (driverPhone.isNotEmpty)
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      driverPhone,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: kMuted,
                      ),
                    ),
                  ),
                Text(
                  isDelivered
                      ? 'تم تسليم الطلب بنجاح ✅'
                      : 'جاري التوصيل إليك 🚀',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDelivered ? kSuccess : kMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (isDelivered)
            ElevatedButton.icon(
              onPressed: onRateTap,
              icon: Icon(Icons.star_rounded, size: 16, color: kInk),
              label: const Text('تقييم', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: kInk,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            )
          else if (driverPhone.isNotEmpty)
            IconButton(
              onPressed: () async {
                final uri = Uri.parse('tel:$driverPhone');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
              icon: const Icon(Icons.phone_in_talk_rounded, color: kSuccess),
              tooltip: 'اتصال بالمندوب',
            ),
        ],
      ),
    );
  }
}

class _CancelledBanner extends StatelessWidget {
  final OrderStatus status;
  const _CancelledBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.cancel, color: kDanger),
          SizedBox(width: 10),
          Text(
            'تم إلغاء الطلب',
            style: TextStyle(color: kDanger, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// مراحل الطلب: استلام ← تحضير ← في الطريق ← تم التوصيل.
class _Timeline extends StatelessWidget {
  final OrderStatus current;
  const _Timeline({required this.current});

  @override
  Widget build(BuildContext context) {
    final steps = OrderStatus.timeline;
    final currentIndex = steps.indexOf(current);

    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineStep(
            step: steps[i],
            reached: i <= currentIndex,
            active: i == currentIndex,
            isLast: i == steps.length - 1,
            lineReached: i < currentIndex,
          ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final OrderStatus step;
  final bool reached;
  final bool active;
  final bool isLast;
  final bool lineReached;

  const _TimelineStep({
    required this.step,
    required this.reached,
    required this.active,
    required this.isLast,
    required this.lineReached,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: reached ? kPrimary : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: reached ? kPrimary : kLine,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    reached ? Icons.check : step.icon,
                    size: 16,
                    color: reached ? Colors.white : kMuted,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 3,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: lineReached ? kPrimary : kLine,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: isLast ? 0 : 18),
              child: Text(
                step.label,
                style: TextStyle(
                  fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                  color: reached ? kInk : kMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _CustomerSpecialRequestCard extends StatefulWidget {
  final Map<String, dynamic> request;
  const _CustomerSpecialRequestCard({required this.request});

  @override
  State<_CustomerSpecialRequestCard> createState() => _CustomerSpecialRequestCardState();
}

class _CustomerSpecialRequestCardState extends State<_CustomerSpecialRequestCard> {
  final audio.AudioPlayer _player = audio.AudioPlayer();
  bool _playing = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleAudio(String encoded) async {
    try {
      if (_playing) {
        await _player.pause();
        if (mounted) setState(() => _playing = false);
        return;
      }
      final bytes = Uint8List.fromList(base64Decode(encoded));
      await _player.play(audio.BytesSource(bytes));
      if (mounted) setState(() => _playing = true);
      _player.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _playing = false);
      });
    } catch (_) {
      if (mounted) {
        setState(() => _playing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تشغيل الرسالة الصوتية المرفقة.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final description = (widget.request['description'] ?? '').toString();
    final imageUrl = (widget.request['imageUrl'] ?? '').toString();
    final voice = (widget.request['voiceBase64'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الطلب الخاص والمرفقات',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          if (description.isNotEmpty) Text(description),
          Text('الكمية المطلوبة: ${widget.request['quantity'] ?? 1}'),
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(imageUrl, height: 180, fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Text('تعذر عرض الصورة المرفقة.')),
            ),
          ],
          if (voice.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => _toggleAudio(voice),
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                label: Text(_playing ? 'إيقاف الرسالة الصوتية' : 'تشغيل الرسالة الصوتية'),
              ),
            ),
        ],
      ),
    );
  }
}
