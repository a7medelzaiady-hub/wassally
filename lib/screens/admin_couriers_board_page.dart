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
  // على مدار كل الفترات (للتسوية): المطلوب توريده = التحصيل − عمولة المندوب، والمسلَّم فعلًا.
  double owedAll = 0;
  double settled = 0;
  _Row(this.id, this.name, this.rating, this.ratingCount);
}

enum _Period { today, month, all }

enum _Sort { collected, earning, rating, delivered }

/// ترتيب المناديب من الأكبر للأقل: التحصيل، العمولة، التقييم، وعدد الطلبات.
/// بيتحسب من آخر 1000 طلب مسلَّم (الإحصائية دي للأدمن بس).
class AdminCouriersBoardPage extends StatefulWidget {
  const AdminCouriersBoardPage({super.key});

  @override
  State<AdminCouriersBoardPage> createState() => _AdminCouriersBoardPageState();
}

class _AdminCouriersBoardPageState extends State<AdminCouriersBoardPage> {
  _Period _period = _Period.today;
  _Sort _sort = _Sort.collected;
  late Future<(List<_Row>, List<Map<String, dynamic>>, Map<String, double>)>
  _data = _load();

  Future<(List<_Row>, List<Map<String, dynamic>>, Map<String, double>)>
  _load() async {
    final db = FirebaseFirestore.instance;
    final couriers = await db.collection('couriers').get();
    final orders = await db
        .collection('orders')
        .where('status', isEqualTo: 'delivered')
        .limit(1000)
        .get();
    final rows = <_Row>[];
    for (final c in couriers.docs) {
      final m = c.data();
      final n = (m['ratingCount'] as num?)?.toInt() ?? 0;
      final sum = (m['ratingSum'] as num?)?.toDouble() ?? 0;
      rows.add(
        _Row(c.id, (m['name'] ?? 'مندوب').toString(), n == 0 ? 0 : sum / n, n),
      );
    }
    final settled = <String, double>{};
    try {
      final st = await db.collection('courier_settlements').limit(1000).get();
      for (final d in st.docs) {
        final id = (d.data()['courierId'] ?? '').toString();
        settled[id] =
            (settled[id] ?? 0) +
            ((d.data()['amount'] as num?)?.toDouble() ?? 0);
      }
    } catch (_) {}
    return (rows, [for (final o in orders.docs) o.data()], settled);
  }

  bool _inPeriod(DateTime? t) {
    if (_period == _Period.all) return true;
    if (t == null) return false;
    final now = DateTime.now();
    final start = _period == _Period.today
        ? DateTime(now.year, now.month, now.day)
        : DateTime(now.year, now.month, 1);
    return !t.isBefore(start);
  }

  List<_Row> _compute(
    List<_Row> base,
    List<Map<String, dynamic>> orders,
    Map<String, double> settled,
  ) {
    final byId = {
      for (final r in base) r.id: _Row(r.id, r.name, r.rating, r.ratingCount),
    };
    for (final o in orders) {
      final id = (o['deliveredBy'] ?? '').toString();
      final r = byId[id];
      if (r == null) continue;
      r.owedAll +=
          ((o['collectedAmount'] as num?)?.toDouble() ?? 0) -
          ((o['courierEarning'] as num?)?.toDouble() ?? 0);
      final at = o['deliveredAt'];
      if (!_inPeriod(at is Timestamp ? at.toDate() : null)) continue;
      r.delivered += 1;
      r.collected += (o['collectedAmount'] as num?)?.toDouble() ?? 0;
      r.earning += (o['courierEarning'] as num?)?.toDouble() ?? 0;
    }
    for (final r in byId.values) {
      r.settled = settled[r.id] ?? 0;
    }
    final list = byId.values.toList();
    num key(_Row r) => switch (_sort) {
      _Sort.collected => r.collected,
      _Sort.earning => r.earning,
      _Sort.rating => r.rating,
      _Sort.delivered => r.delivered,
    };
    list.sort((a, b) => key(b).compareTo(key(a)));
    return list;
  }

  Widget _chip<T>(String label, T value, T current, ValueChanged<T> on) {
    final sel = value == current;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      selected: sel,
      onSelected: (_) => on(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
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
                    _chip(
                      'اليوم',
                      _Period.today,
                      _period,
                      (v) => setState(() => _period = v),
                    ),
                    _chip(
                      'الشهر',
                      _Period.month,
                      _period,
                      (v) => setState(() => _period = v),
                    ),
                    _chip(
                      'الإجمالي',
                      _Period.all,
                      _period,
                      (v) => setState(() => _period = v),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    _chip(
                      'بالتحصيل',
                      _Sort.collected,
                      _sort,
                      (v) => setState(() => _sort = v),
                    ),
                    _chip(
                      'بالعمولة',
                      _Sort.earning,
                      _sort,
                      (v) => setState(() => _sort = v),
                    ),
                    _chip(
                      'بالتقييم',
                      _Sort.rating,
                      _sort,
                      (v) => setState(() => _sort = v),
                    ),
                    _chip(
                      'بعدد الطلبات',
                      _Sort.delivered,
                      _sort,
                      (v) => setState(() => _sort = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child:
                FutureBuilder<
                  (List<_Row>, List<Map<String, dynamic>>, Map<String, double>)
                >(
                  future: _data,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return EmptyState(
                        icon: Icons.lock_outline,
                        title: 'تعذر تحميل الترتيب',
                        message: 'تأكد إن قواعد Firebase الجديدة منشورة.',
                      );
                    }
                    if (!snap.hasData) {
                      return Center(
                        child: CircularProgressIndicator(color: kPrimary),
                      );
                    }
                    final rows = _compute(
                      snap.data!.$1,
                      snap.data!.$2,
                      snap.data!.$3,
                    );
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
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                ),
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
    if (ok != true) return;
    final a = double.tryParse(amount.text.trim().replaceAll(',', '.'));
    if (a == null || a <= 0) {
      messenger.showSnackBar(const SnackBar(content: Text('اكتب مبلغ صحيح.')));
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
      if (!mounted) return;
      setState(() => _data = _load());
      messenger.showSnackBar(
        const SnackBar(content: Text('تم تسجيل التسليم.')),
      );
    } catch (e) {
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
              _stat(
                'التحصيل',
                formatPrice(r.collected),
                bold: _sort == _Sort.collected,
              ),
              _stat(
                'العمولة',
                formatPrice(r.earning),
                bold: _sort == _Sort.earning,
              ),
              _stat(
                'الطلبات',
                '${r.delivered}',
                bold: _sort == _Sort.delivered,
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              _stat('مطلوب توريده', formatPrice(r.owedAll)),
              _stat('تم تسليمه', formatPrice(r.settled)),
              _stat('المتبقي', formatPrice(r.owedAll - r.settled), bold: true),
              TextButton(
                onPressed: () => _settle(r),
                child: const Text('تسجيل تسليم'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
