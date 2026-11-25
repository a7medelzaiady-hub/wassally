import 'package:flutter/material.dart';

import '../models/quick_price_guide.dart';
import '../services/quick_price_guide_service.dart';

/// Reusable quick-order item selector. Unlisted products remain free text
/// and are never assigned an invented approximate price.
class QuickPricePicker extends StatefulWidget {
  final ValueChanged<List<QuickPriceSelection>> onChanged;
  final ValueChanged<String>? onUnlistedChanged;
  /// خانة «اكتب طلبك» المدمجة (الصفحة الجديدة بتعرض خانتها هي).
  final bool showFreeText;

  /// خانة البحث في الدليل.
  final bool showSearch;
  const QuickPricePicker({
    super.key,
    required this.onChanged,
    this.onUnlistedChanged,
    this.showFreeText = true,
    this.showSearch = true,
  });

  @override
  State<QuickPricePicker> createState() => _QuickPricePickerState();
}

class _QuickPricePickerState extends State<QuickPricePicker>
    with AutomaticKeepAliveClientMixin<QuickPricePicker> {
  @override
  bool get wantKeepAlive => true;

  final _search = TextEditingController();
  final _unlisted = TextEditingController();
  final _orderTextFocus = FocusNode();
  final Map<String, int> _quantities = {};
  late Future<QuickPriceGuide?> _guide = QuickPriceGuideService.load();

  void _refreshGuide() => setState(() {
    _guide = QuickPriceGuideService.refresh();
  });

  @override
  void dispose() {
    _search.dispose();
    _unlisted.dispose();
    _orderTextFocus.dispose();
    super.dispose();
  }

  void _change(QuickPriceGuide guide, QuickPriceItem item, int delta) {
    if (delta > 0 && !_quantities.containsKey(item.id) && _quantities.length >= 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الحد الأقصى 30 صنفًا لكل محل')),
      );
      return;
    }
    final next = ((_quantities[item.id] ?? 0) + delta).clamp(0, 99);
    setState(() {
      if (next == 0) {
        _quantities.remove(item.id);
      } else {
        _quantities[item.id] = next;
      }
    });
    widget.onChanged([
      for (final entry in guide.items)
        if ((_quantities[entry.id] ?? 0) > 0)
          QuickPriceSelection(item: entry, quantity: _quantities[entry.id]!),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<QuickPriceGuide?>(
      future: _guide,
      builder: (context, snapshot) {
        final guide = snapshot.data;
        final hasItems = guide != null && guide.items.isNotEmpty;
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final query = _search.text.trim().toLowerCase();
        final matches = guide?.items.where((item) =>
          item.matchesSearch(query)).toList() ?? [];
        final selected = [
          if (guide != null)
            for (final item in guide.items)
              if ((_quantities[item.id] ?? 0) > 0)
                QuickPriceSelection(item: item, quantity: _quantities[item.id]!),
        ];
        final total = QuickPriceEstimate.totalPiastres(selected);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showFreeText) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('اكتب طلبك أو امليه بصوتك',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _unlisted,
                    focusNode: _orderTextFocus,
                    minLines: 3,
                    maxLines: 5,
                    onChanged: widget.onUnlistedChanged,
                    decoration: const InputDecoration(
                      labelText: 'الأصناف والكميات',
                      hintText: 'مثال: ٢ كيلو رز وكيس سكر',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _orderTextFocus.requestFocus,
                    icon: const Icon(Icons.mic_none),
                    label: const Text('افتح الكيبورد للإملاء'),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'اضغط علامة الميكروفون في الكيبورد، قول الصنف والكمية، وراجع الكلام قبل الإرسال.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ],
            if (hasItems && widget.showSearch)
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'ابحث عن صنف',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            if (loading)
              const LinearProgressIndicator(),
            if (!loading && !hasItems)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('دليل الأسعار مش متاح دلوقتي. تقدر تكتب طلبك عادي.'),
                    TextButton.icon(
                      onPressed: _refreshGuide,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة تحميل دليل الأسعار'),
                    ),
                  ],
                ),
              ),
            if (hasItems && matches.isEmpty && query.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('الصنف مش موجود في الدليل؛ اكتبه في خانة الأصناف والكميات.'),
              ),
            ...matches.take(30).map((item) {
              final count = _quantities[item.id] ?? 0;
              return ListTile(
                title: Text(item.name),
                subtitle: Text('${(item.pricePiastres / 100).toStringAsFixed(2)} ج / ${item.unit}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'تقليل ${item.name}',
                      onPressed: count == 0 ? null : () => _change(guide!, item, -1),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$count', style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      tooltip: 'زيادة ${item.name}',
                      onPressed: count >= 99 ? null : () => _change(guide!, item, 1),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              );
            }),
            if (selected.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'تقدير أصناف الدليل: ${(total / 100).toStringAsFixed(2)} جنيه',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(QuickPriceEstimate.disclaimer),
            ],
          ],
        );
      },
    );
  }
}
