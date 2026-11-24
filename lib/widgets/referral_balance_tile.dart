import 'package:flutter/material.dart';

/// رصيد قابل للقراءة بوضوح، من غير خلط النقاط والنقد وخصم العمولة.
class ReferralBalanceTile extends StatelessWidget {
  const ReferralBalanceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.explanation,
  });

  final IconData icon;
  final String title;
  final String value;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(value,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900,
                          color: theme.colorScheme.primary)),
                  const SizedBox(height: 3),
                  Text(explanation, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
