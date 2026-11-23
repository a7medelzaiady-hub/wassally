import 'package:flutter/material.dart';

/// Displays the customer's approximate request to the assigned courier.
/// This is informational only: the final bill is based on receipt photos.
class QuickOrderEstimateCard extends StatelessWidget {
  final Map<String, dynamic> order;
  const QuickOrderEstimateCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final stores = order['stores'];
    final groups = stores is List ? stores : const [];
    final calculated = <Widget>[];
    var estimate = 0;
    for (final group in groups) {
      if (group is! Map) continue;
      final storeName = (group['name'] ?? '').toString().trim();
      final items = group['pricedItems'];
      if (storeName.isNotEmpty) {
        calculated.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(storeName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        ));
      }
      if (items is! List) continue;
      for (final item in items) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString();
        final qty = item['qty'];
        final unit = item['unitPricePiastres'];
        if (qty is! int || qty < 1 || unit is! int || unit < 0) continue;
        final subtotal = qty * unit;
        estimate += subtotal;
        calculated.add(ListTile(
          dense: true,
          title: Text(name),
          subtitle: Text('الكمية: $qty'),
          trailing: Text('${(subtotal / 100).toStringAsFixed(2)} ج'),
        ));
      }
    }
    // Use the server-computed estimate whenever available.
    final serverTotal = order['approxTotalPiastres'];
    final total = serverTotal is int && serverTotal >= 0
        ? serverTotal
        : estimate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('الأصناف المطلوبة والأسعار التقريبية',
              style: Theme.of(context).textTheme.titleMedium),
            if (calculated.isEmpty)
              const Text('لا توجد أصناف مسعّرة في هذا الطلب'),
            ...calculated,
            const Divider(),
            Text('الإجمالي التقريبي: ${(total / 100).toStringAsFixed(2)} جنيه',
              style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('الأسعار تقريبية وقد تزيد أو تقل حسب المحل'),
            const Text('المبلغ النهائي يُحسب من صور الفواتير، وليس من هذا التقدير.'),
          ],
        ),
      ),
    );
  }
}
