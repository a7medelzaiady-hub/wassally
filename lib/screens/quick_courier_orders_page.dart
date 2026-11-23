import 'package:flutter/material.dart';

import '../models/quick_courier_order.dart';
import '../services/quick_courier_service.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import 'quick_courier_order_page.dart';

/// زرار «الطلبات السريعة» في صفحة المندوب: بيظهر للمناديب المعتمدين (quickEnabled) بس.
/// قراءة واحدة لمستند المندوب عند فتح الصفحة.
class QuickCourierEntry extends StatefulWidget {
  final QuickCourierBackend backend;
  const QuickCourierEntry({super.key, this.backend = const FirebaseQuickCourierBackend()});

  @override
  State<QuickCourierEntry> createState() => _QuickCourierEntryState();
}

class _QuickCourierEntryState extends State<QuickCourierEntry> {
  late final Future<bool> _enabled = widget.backend.isQuickEnabled().catchError((_) => false);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _enabled,
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Brand.green,
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              icon: const Icon(Icons.flash_on, size: 26),
              label: const Text('الطلبات السريعة'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => QuickCourierOrdersPage(backend: widget.backend),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// قايمة الطلبات السريعة للمندوب المعتمد: «المتاحة» و«طلباتي». تحديث بالسحب، من غير مستمعات.
class QuickCourierOrdersPage extends StatefulWidget {
  final QuickCourierBackend backend;
  const QuickCourierOrdersPage({super.key, this.backend = const FirebaseQuickCourierBackend()});

  @override
  State<QuickCourierOrdersPage> createState() => _QuickCourierOrdersPageState();
}

class _QuickCourierOrdersPageState extends State<QuickCourierOrdersPage> {
  bool _mineTab = false;
  bool _loading = true;
  String? _error;
  List<QuickCourierOrder> _open = const [];
  List<QuickCourierOrder> _mine = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([widget.backend.loadOpen(), widget.backend.loadMine()]);
      if (!mounted) return;
      setState(() {
        _open = results[0];
        _mine = results[1];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل الطلبات السريعة. تأكد إن حسابك معتمد وحاول تاني.';
      });
    }
  }

  Future<void> _openOrder(QuickCourierOrder order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuickCourierOrderPage(orderId: order.id, initial: order, backend: widget.backend),
      ),
    );
    if (mounted) _load();
  }

  Widget _tab(String label, bool mine) {
    final selected = _mineTab == mine;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _mineTab = mine),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Brand.green : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : kMuted,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _mine.where((o) => o.isActive).toList();
    final shown = _mineTab ? active : _open;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الطلبات السريعة')),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kLine),
              ),
              child: Row(
                children: [
                  _tab('المتاحة (${_open.length})', false),
                  _tab('طلباتي (${active.length})', true),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading
                    ? ListView(children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator()),
                      ])
                    : _error != null
                        ? ListView(children: [
                            const SizedBox(height: 80),
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  Text(_error!, textAlign: TextAlign.center),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: _load,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('إعادة المحاولة'),
                                  ),
                                ],
                              ),
                            ),
                          ])
                        : shown.isEmpty
                            ? ListView(children: [
                                const SizedBox(height: 80),
                                Icon(Icons.flash_on, size: 56, color: kMuted),
                                const SizedBox(height: 12),
                                Text(
                                  _mineTab ? 'مفيش طلبات شغالة معاك' : 'مفيش طلبات سريعة دلوقتي',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text('اسحب لتحت للتحديث', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
                              ])
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                                itemCount: shown.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 12),
                                itemBuilder: (context, i) => QuickOrderSummaryCard(
                                  order: shown[i],
                                  onTap: () => _openOrder(shown[i]),
                                ),
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// كارت مختصر للطلب: عدد المحلات، المنطقة، الإجمالي التقريبي، والخطوة الحالية.
class QuickOrderSummaryCard extends StatelessWidget {
  final QuickCourierOrder order;
  final VoidCallback onTap;
  const QuickOrderSummaryCard({super.key, required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final named = order.stores.map((s) => s.name).where((n) => n.isNotEmpty).toList();
    final approx = order.approxTotalPiastres;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kLine),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Brand.green.withValues(alpha: 0.12),
                child: Text(
                  '${order.stores.length}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Brand.green),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.stores.length == 1 ? 'محل واحد' : '${order.stores.length} محلات',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    if (named.isNotEmpty)
                      Text(named.join(' • '), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (order.area.isNotEmpty)
                      Text('📍 منطقة العميل: ${order.area}',
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: kMuted)),
                    if (approx != null && approx > 0)
                      Text('تقريبًا ${formatPiastres(approx)}', style: TextStyle(color: kMuted)),
                    const SizedBox(height: 4),
                    Text(
                      quickStepLabel(order.step),
                      style: TextStyle(color: Brand.green, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

/// اسم الخطوة بكلام بسيط للمندوب.
String quickStepLabel(QuickCourierStep step) => switch (step) {
      QuickCourierStep.available => 'متاح للقبول',
      QuickCourierStep.estimate => 'اتصل بالعميل واكتب التقدير',
      QuickCourierStep.purchasing => 'اشتري وصوّر الفواتير',
      QuickCourierStep.waitCustomer => 'مستني موافقة العميل على الكشف',
      QuickCourierStep.deliver => 'سلّم واكتب الرمز',
      QuickCourierStep.delivered => 'اتسلّم',
      QuickCourierStep.cancelled => 'ملغي',
    };
