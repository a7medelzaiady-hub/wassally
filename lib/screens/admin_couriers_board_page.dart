import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/empty_state.dart';

class _Row {
  final String id;
  final String name;
  final double rating;
  final int ratingCount;
  int delivered = 0;
  double collected = 0;
  double earning = 0;
  double owedAll = 0;
  double settled = 0;

  _Row(this.id, this.name, this.rating, this.ratingCount);
}

enum _Period { today, month, all }
enum _Sort { collected, earning, rating, delivered }

/// ترتيب المناديب. الأرقام تُحسب بتجميعات Firestore ولا تعتمد على أول 1000 طلب.
class AdminCouriersBoardPage extends StatefulWidget {
  const AdminCouriersBoardPage({super.key});

  @override
  State<AdminCouriersBoardPage> createState() => _AdminCouriersBoardPageState();
}

class _AdminCouriersBoardPageState extends State<AdminCouriersBoardPage> {
  _Period _period = _Period.today;
  _Sort _sort = _Sort.collected;
  late Future<List<_Row>> _data = _load();

  DateTime? get _periodStart {
    if (_period == _Period.all) return null;
    final now = DateTime.now();
    return _period == _Period.today
        ? DateTime(now.year, now.month, now.day)
        : DateTime(now.year, now.month, 1);
  }

  double _sum(dynamic value) =>
      value is num ? value.toDouble() : 0.0;

  Future<List<_Row>> _load() async {
    final db = FirebaseFirestore.instance;
    // الحد يمنع تحميل مجموعة المناديب بلا سقف؛ يمكن إضافة pagination عند نموها.
    final courierSnap = await db.collection('couriers').limit(100).get();

    final rows = await Future.wait(courierSnap.docs.map((courier) async {
      final data = courier.data();
      final ratingCount = (data['ratingCount'] as num?)?.toInt() ?? 0;
      final ratingSum = _sum(data['ratingSum']);
      final row = _Row(
        courier.id,
        (data['name'] ?? 'مندوب').toString(),
        ratingCount == 0 ? 0 : ratingSum / ratingCount,
        ratingCount,
      );

      Query<Map<String, dynamic>> delivered = db
          .collection('orders')
          .where('deliveredBy', isEqualTo: courier.id)
          .where('status', isEqualTo: 'delivered');

      final allFuture = delivered
          .aggregate(count(), sum('collectedAmount'), sum('courierEarning'))
          .get();

      Query<Map<String, dynamic>> periodQuery = delivered;
      final start = _periodStart;
      if (start != null) {
        periodQuery = periodQuery.where(
          'deliveredAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
        );
      }
      final periodFuture = periodQuery
          .aggregate(count(), sum('collectedAmount'), sum('courierEarning'))
          .get();

      final settlementFuture = db
          .collection('courier_settlements')
          .where('courierId', isEqualTo: courier.id)
          .aggregate(sum('amount'))
          .get();

      final results = await Future.wait([
        allFuture,
        periodFuture,
        settlementFuture,
      ]);
      final all = results[0];
      final period = results[1];
      final settlements = results[2];

      row.owedAll =
          _sum(all.getSum('collectedAmount')) -
          _sum(all.getSum('courierEarning'));
      row.settled = _sum(settlements.getSum('amount'));
      row.delivered = period.count ?? 0;
      row.collected = _sum(period.getSum('collectedAmount'));
      row.earning = _sum(period.getSum('courierEarning'));
      return row;
    }));

    return rows;
  }

  Widget _chip<T>(String label, T value, T current, ValueChanged<T> on) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      selected: value == current,
      onSelected: (_) => on(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const InnerHeader(title: 'ترتيب المناديب'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      _chip('اليوم', _Period.today, _period, (v) {
                        setState(() {
                          _period = v;
                          _data = _load();
                        });
                      }),
                      _chip('الشهر', _Period.month, _period, (v) {
                        setState(() {
                          _period = v;
                          _data = _load();
                        });
                      }),
                      _chip('الإجمالي', _Period.all, _period, (v) {
                        setState(() {
                          _period = v;
                          _data = _load();
                        });
                      }),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      _chip('بالتحصيل', _Sort.collected, _sort,
                          (v) => setState(() => _sort = v)),
                      _chip('بالعمولة', _Sort.earning, _sort,
                          (v) => setState(() => _sort = v)),
                      _chip('بالتقييم', _Sort.rating, _sort,
                          (v) => setState(() => _sort = v)),
                      _chip('بعدد الطلبات', _Sort.delivered, _sort,
                          (v) => setState(() => _sort = v)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<_Row>>(
                future: _data,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return EmptyState(
                      icon: Icons.error_outline,
                      title: 'تعذر تحميل الترتيب',
                      message:
                          snap.error is FirebaseException &&
                              (snap.error as FirebaseException).code ==
                                  'failed-precondition'
                          ? 'الصفحة تحتاج فهارس Firestore جديدة. انشر firestore.indexes.json '
                                'أو افتح الرابط الظاهر في رسالة الخطأ لإنشاء الفهرس، وانتظر دقائق حتى '
                                'يكتمل بناؤه ثم أعد المحاولة.\n\n${snap.error}'
                          : 'فشل تجميع بيانات المناديب: ${snap.error}',
                    );
                  }
                  if (!snap.hasData) {
                    return Center(
                      child: CircularProgressIndicator(color: kPrimary),
                    );
                  }
                  final rows = [...snap.data!];
                  num key(_Row r) => switch (_sort) {
                        _Sort.collected => r.collected,
                        _Sort.earning => r.earning,
                        _Sort.rating => r.rating,
                        _Sort.delivered => r.delivered,
                      };
                  rows.sort((a, b) => key(b).compareTo(key(a)));
                  if (rows.isEmpty) {
                    return const EmptyState(
                      icon: Icons.two_wheeler,
                      title: 'مفيش مناديب',
                      message: 'ضيف مناديب من صفحة المناديب.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(() => _data = _load());
                      await _data;
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _tile(i, rows[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _settle(_Row r) async {
    final amount = TextEditingController(
      text: (r.owedAll - r.settled) > 0
          ? (r.owedAll - r.settled).toStringAsFixed(0)
          : '',
    );
    final note = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تسليم من ${r.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ المستلم'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تسجيل'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) {
      amount.dispose();
      note.dispose();
      return;
    }
    final a = double.tryParse(amount.text.trim().replaceAll(',', '.'));
    amount.dispose();
    if (a == null || !a.isFinite || a <= 0 || a > 1000000) {
      note.dispose();
      messenger.showSnackBar(
        const SnackBar(content: Text('اكتب مبلغ صحيح (حتى مليون جنيه).')),
      );
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('courier_settlements').add({
        'courierId': r.id,
        'courierName': r.name,
        'amount': a,
        'note': note.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      note.dispose();
      if (!mounted) return;
      setState(() => _data = _load());
      messenger.showSnackBar(
        const SnackBar(content: Text('تم تسجيل التسليم.')),
      );
    } catch (e) {
      note.dispose();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('تعذر التسجيل: $e')));
    }
  }

  Widget _stat(String label, String value, {bool bold = false}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: kMuted)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                  color: Brand.ink,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _tile(int i, _Row r) {
    final medal = switch (i) {
      0 => const Color(0xFFE5A100),
      1 => const Color(0xFF8E98A4),
      2 => const Color(0xFFB4713B),
      _ => kMuted,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kLine),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: medal.withValues(alpha: 0.14),
                ),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(fontWeight: FontWeight.w900, color: medal),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Brand.ink,
                  ),
                ),
              ),
              Text(
                r.ratingCount == 0
                    ? 'بدون تقييم'
                    : 'تقييم ${r.rating.toStringAsFixed(1)} (${r.ratingCount})',
                style: TextStyle(fontSize: 12, color: kMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat('التحصيل', formatPrice(r.collected),
                  bold: _sort == _Sort.collected),
              _stat('العمولة', formatPrice(r.earning),
                  bold: _sort == _Sort.earning),
              _stat('الطلبات', '${r.delivered}',
                  bold: _sort == _Sort.delivered),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              _stat('مطلوب توريده', formatPrice(r.owedAll)),
              _stat('تم تسليمه', formatPrice(r.settled)),
              _stat('المتبقي', formatPrice(r.owedAll - r.settled), bold: true),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonal(
              onPressed: () => _settle(r),
              child: const Text('تسجيل تسليم'),
            ),
          ),
        ],
      ),
    );
  }
}
