import 'package:flutter/material.dart';

import '../services/customer_rating_service.dart';

class CustomerRatingInput {
  final int rating;
  final String reason;
  final String comment;
  const CustomerRatingInput(this.rating, this.reason, this.comment);
}

Future<CustomerRatingInput?> showCustomerRatingDialog(
  BuildContext context, {
  String title = 'تقييم تعامل العميل',
}) async {
  final comment = TextEditingController();
  var rating = 5;
  var reason = 'positive';
  final result = await showDialog<CustomerRatingInput>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('اختار تقييمًا من 1 إلى 5'),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var star = 1; star <= 5; star++)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setDialogState(() {
                          rating = star;
                          if (star <= 3 && reason == 'positive') reason = 'other';
                          if (star >= 4 && reason == 'other') reason = 'positive';
                        }),
                        icon: Icon(
                          star <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: star <= rating ? Colors.amber : Colors.grey,
                          size: 30,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: reason,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'سبب التقييم',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final entry in CustomerRatingService.reasonLabels.entries)
                      if (rating > 3 || entry.key != 'positive')
                        DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => reason = value);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: comment,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة إضافية (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const Text(
                  'التقييم لا يفرض عقوبة تلقائية؛ الإدارة تراجع الوقائع عند الحاجة.',
                  style: TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                CustomerRatingInput(rating, reason, comment.text.trim()),
              ),
              child: const Text('إرسال التقييم'),
            ),
          ],
        ),
      ),
    ),
  );
  comment.dispose();
  return result;
}
