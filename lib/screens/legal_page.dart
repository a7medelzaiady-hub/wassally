import 'package:flutter/material.dart';

import '../legal/legal_content.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';

/// بيعرض نص قانوني (سياسة الخصوصية أو شروط الاستخدام) من legal_content.dart.
class LegalPage extends StatelessWidget {
  final String title;
  final List<LegalSection> sections;
  const LegalPage({super.key, required this.title, required this.sections});

  static void open(
    BuildContext context, {
    required String title,
    required List<LegalSection> sections,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalPage(title: title, sections: sections),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: kBg,
      body: Column(
        children: [
          InnerHeader(title: title),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                for (final s in sections) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      s.title,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: kPrimary,
                      ),
                    ),
                  ),
                  for (final line in s.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        line,
                        style: text.bodyMedium?.copyWith(height: 1.7),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
