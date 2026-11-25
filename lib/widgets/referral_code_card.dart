import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/referral.dart';
import 'app_snack.dart';

/// Presentation-only referral card. Parent must supply a server-issued code.
/// No reads, listeners, claims, balance changes, or reward grants are made here.
class ReferralCodeCard extends StatelessWidget {
  final String? serverIssuedCode;
  final VoidCallback? onShare;
  /// Whether the Worker is actively awarding successful referrals.
  final bool rewardsEnabled;

  const ReferralCodeCard({
    super.key,
    required this.serverIssuedCode,
    this.onShare,
    this.rewardsEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final code = normalizeReferralCode(serverIssuedCode ?? '');
    final valid = isReferralCodeFormatValid(code);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('شير بكودك واكسب هدايا',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (valid) ...[
              SelectableText(code,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          appSnack('تم نسخ كود الدعوة'),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('نسخ الكود'),
                  ),
                  if (onShare != null)
                    TextButton.icon(
                      onPressed: onShare,
                      icon: const Icon(Icons.share),
                      label: const Text('مشاركة'),
                    ),
                ],
              ),
            ] else
              const Text('كود الدعوة غير متاح حاليًا',
                  textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              rewardsEnabled
                  ? 'المكافآت بتتحسب بعد أول طلب ناجح، حسب شروط البرنامج.'
                  : 'المكافآت لسه مش مفعّلة. تقدر تنسخ الكود، لكن مش هتتحسب أي مكافأة قبل تشغيل البرنامج رسميًا.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
