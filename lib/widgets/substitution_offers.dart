import 'package:flutter/material.dart';

import '../models/order.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// العميل بيشوف البدائل اللي المحل اقترحها للأصناف الناقصة ويختار يوافق على أنهي
/// واحد، وبعدين «كمّل» بيفتح تعديل الطلب بالبدائل دي. السعر النهائي بيتحسب من
/// الكتالوج عند الحفظ (الـWorker)، فلو اتغير العميل بيتبلّغ يراجع.
class SubstitutionOffers extends StatefulWidget {
  final AppOrder order;
  final void Function(Map<String, OrderSubstitute> accepted) onContinue;

  const SubstitutionOffers({super.key, required this.order, required this.onContinue});

  /// البدائل المعروضة: لأصناف ناقصة فعلًا وموجودة في الطلب.
  static Map<String, OrderSubstitute> offersFor(AppOrder order) => {
        for (final e in order.substitutions.entries)
          if (order.unavailableItems.contains(e.key)) e.key: e.value,
      };

  @override
  State<SubstitutionOffers> createState() => _SubstitutionOffersState();
}

class _SubstitutionOffersState extends State<SubstitutionOffers> {
  final Set<String> _accepted = {};

  @override
  Widget build(BuildContext context) {
    final offers = SubstitutionOffers.offersFor(widget.order);
    final qtyOf = {for (final l in widget.order.items) l.name: l.qty};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in offers.entries)
          Container(
            key: Key('substitute-${e.key}'),
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _accepted.contains(e.key) ? AppColors.success : kLine,
              ),
            ),
            child: CheckboxListTile(
              value: _accepted.contains(e.key),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _accepted.add(e.key);
                } else {
                  _accepted.remove(e.key);
                }
              }),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(
                'بدل «${e.key}»: ${e.value.name}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${formatPrice(e.value.price)} للواحدة × ${qtyOf[e.key] ?? 1}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('substitute-continue'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
          onPressed: () => widget.onContinue({
            for (final k in _accepted)
              if (offers[k] != null) k: offers[k]!,
          }),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(
            _accepted.isEmpty ? 'كمّل من غير الأصناف دي' : 'كمّل بالبديل وراجع الحساب',
          ),
        ),
      ],
    );
  }
}
