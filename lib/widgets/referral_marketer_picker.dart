import 'package:flutter/material.dart';

import '../models/referral_admin_choices.dart';

/// Bounded, on-demand directory for admin use only. The caller reads /users
/// once when the administrator explicitly opens this sheet; no listeners.
class ReferralMarketerPicker extends StatefulWidget {
  const ReferralMarketerPicker({super.key, required this.accounts});

  final Future<List<ReferralMarketerChoice>> accounts;

  @override
  State<ReferralMarketerPicker> createState() => _ReferralMarketerPickerState();
}

class _ReferralMarketerPickerState extends State<ReferralMarketerPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'اختار حساب المسوّق',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'آخر 80 حساب في القائمة المحدودة فقط. تقدر تدخل UID يدويًا لو الحساب مش ظاهر.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('marketer-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'ابحث بالاسم أو البريد أو UID',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: FutureBuilder<List<ReferralMarketerChoice>>(
                future: widget.accounts,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return const Center(
                      child: Text('تعذّر تحميل الحسابات. راجع اتصال الإنترنت وصلاحية المدير.'),
                    );
                  }
                  final shown = (snap.data ?? const <ReferralMarketerChoice>[])
                      .where((c) => c.matches(_search.text))
                      .toList();
                  if (shown.isEmpty) {
                    return const Center(
                      child: Text('مفيش حساب مطابق في القائمة. استخدم UID من بيانات الحساب.'),
                    );
                  }
                  return ListView.builder(
                    key: const Key('marketer-account-list'),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final choice = shown[i];
                      return ListTile(
                        key: Key('marketer-choice-${choice.uid}'),
                        dense: true,
                        title: Text(choice.name, maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          choice.email.isEmpty ? choice.uid : choice.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () => Navigator.of(context).pop(choice),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
