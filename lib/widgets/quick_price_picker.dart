import 'package:flutter/material.dart';

import '../models/quick_price_guide.dart';
import '../services/quick_price_guide_service.dart';

/// Reusable quick-order item selector. Unlisted products remain free text
/// and are never assigned an invented approximate price.
class QuickPricePicker extends StatefulWidget {
  final ValueChanged<List<QuickPriceSelection>> onChanged;
  final ValueChanged<String>? onUnlistedChanged;
  const QuickPricePicker({
    super.key,
    required this.onChanged,
    this.onUnlistedChanged,
  });

  @override
  State<QuickPricePicker> createState() => _QuickPricePickerState();
}

class _QuickPricePickerState extends State<QuickPricePicker> {
  final _search = TextEditingController();
  final _unlisted = TextEditingController();
  final Map<String, int> _quantities = {};
  late final Future<QuickPriceGuide?> _guide = QuickPriceGuideService.load();

  @override
  void dispose() {
    _search.dispose();
    _unlisted.dispose();
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
    return FutureBuilder<QuickPriceGuide?>(
      future: _guide,
      builder: (context, snapshot) {
        final guide = snapshot.data;
        final query = _search.text.trim().toLowerCase();
        final matches = guide?.items.where((item) =>
          item.name.toLowerCase().contains(query)).toList() ?? [];
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
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'ابحث عن صنف',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(),
            if (guide == null && snapshot.connectionState != ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('قائمة الأسعار غير متاحة حاليًا، اكتب طلبك بالأسفل.'),
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
            const SizedBox(height: 8),
            TextField(
              controller: _unlisted,
              maxLines: 3,
              onChanged: widget.onUnlistedChanged,
              decoration: const InputDecoration(
                labelText: 'أصناف أخرى مش موجودة في القائمة',
                hintText: 'اكتب الأصناف والكميات المطلوبة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('الإجمالي التقريبي: ${(total / 100).toStringAsFixed(2)} جنيه',
              style: Theme.of(context).textTheme.titleMedium),
            const Text(QuickPriceEstimate.disclaimer),
          ],
        );
      },
    );
  }
}
