import 'package:flutter/material.dart';

import '../screens/info_pages.dart' show openWasallyWhatsApp;
import '../services/feedback_service.dart';
import '../theme/app_theme.dart';
import 'glossy_fab.dart';

/// زر عائم (speed dial) للشكاوى والاقتراحات. كل اختيار بيفتح واتساب الإدارة برسالة جاهزة.
/// [allowOrderIssue] = false للمندوب وصاحب المحل (مفيش "طلباتي" عندهم).
class FeedbackFab extends StatefulWidget {
  final bool allowOrderIssue;
  const FeedbackFab({super.key, this.allowOrderIssue = false});

  @override
  State<FeedbackFab> createState() => _FeedbackFabState();
}

class _FeedbackFabState extends State<FeedbackFab> {
  bool _open = false;

  IconData _icon(FeedbackKind k) => switch (k) {
    FeedbackKind.complaint => Icons.report_gmailerrorred_outlined,
    FeedbackKind.suggestion => Icons.lightbulb_outline,
    FeedbackKind.orderIssue => Icons.receipt_long_outlined,
    FeedbackKind.restrictionAppeal => Icons.gavel_outlined,
  };

  Future<void> _pick(FeedbackKind k) async {
    setState(() => _open = false);
    await openWasallyWhatsApp(k.template);
  }

  @override
  Widget build(BuildContext context) {
    final kinds = [
      for (final k in FeedbackKind.values)
        if ((k != FeedbackKind.orderIssue || widget.allowOrderIssue) &&
            (k != FeedbackKind.restrictionAppeal || widget.allowOrderIssue)) k,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.bottomRight,
          child: _open
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final k in kinds)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: FloatingActionButton.extended(
                          heroTag: 'fb_${k.key}',
                          elevation: 2,
                          backgroundColor: Colors.white,
                          foregroundColor: kPrimary,
                          onPressed: () => _pick(k),
                          icon: Icon(_icon(k)),
                          label: Text(k.label),
                        ),
                      ),
                  ],
                )
              : const SizedBox(width: 0, height: 0),
        ),
        GlossyFab(
          size: 46,
          tooltip: 'شكوى أو اقتراح',
          icon: _open ? Icons.close_rounded : Icons.headset_mic_rounded,
          onPressed: () => setState(() => _open = !_open),
        ),
      ],
    );
  }
}
