import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';

/// حدود لازم تطابق firestore.rules (validOwnerProduct).
const int kMaxOptionGroups = 10;
const int kMaxOptionsPerGroup = 20;

double? _price(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  var v = input.trim();
  for (var i = 0; i < 10; i++) {
    v = v.replaceAll(arabic[i], '$i');
  }
  v = v.replaceAll('٫', '.').replaceAll('،', '.').replaceAll(',', '.');
  return double.tryParse(v.replaceAll(' ', ''));
}

class _Draft {
  final TextEditingController title;
  final TextEditingController options;
  bool required;
  bool multi;
  int max;

  _Draft({
    String title = '',
    String options = '',
    this.required = false,
    this.multi = false,
    this.max = 2,
  }) : title = TextEditingController(text: title),
       options = TextEditingController(text: options);

  factory _Draft.from(OptionGroup g) => _Draft(
    title: g.title,
    options: g.options
        .map((o) => o.price > 0 ? '${o.name} = ${_fmt(o.price)}' : o.name)
        .join('\n'),
    required: g.required,
    multi: !g.single,
    max: g.single ? 2 : g.max,
  );

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void dispose() {
    title.dispose();
    options.dispose();
  }

  /// null = المجموعة فاضية/ناقصة (بتتجاهل).
  OptionGroup? build() {
    final name = title.text.trim();
    final opts = <ProductOption>[];
    for (final raw in options.text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final i = line.lastIndexOf('=');
      if (i > 0) {
        final n = line.substring(0, i).trim();
        final p = _price(line.substring(i + 1)) ?? 0;
        if (n.isNotEmpty) opts.add(ProductOption(n, p < 0 ? 0 : p));
      } else {
        opts.add(ProductOption(line));
      }
    }
    if (name.isEmpty || opts.isEmpty) return null;
    final list = opts.take(kMaxOptionsPerGroup).toList();
    final isMulti = multi && list.length >= 2;
    return OptionGroup(
      name,
      list,
      min: required ? 1 : 0,
      max: isMulti ? max.clamp(2, list.length) : 1,
    );
  }
}

/// محرر مجموعات الخيارات للصنف (للمدير/صاحب المحل). بيرجع القائمة الجديدة أو null لو اتلغى.
Future<List<OptionGroup>?> showOptionGroupsEditor(
  BuildContext context,
  List<OptionGroup> initial,
) {
  final drafts = initial.map(_Draft.from).toList();
  return showDialog<List<OptionGroup>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('خيارات الصنف'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مثال: مجموعة «السكر» (اختيار واحد): سادة / مظبوط / زيادة. '
                  'ومجموعة «إضافات» (اختياري، متعدد): كوكيز = 90',
                  style: TextStyle(fontSize: 12, color: kMuted, height: 1.4),
                ),
                for (var i = 0; i < drafts.length; i++) ...[
                  const SizedBox(height: 14),
                  _groupEditor(ctx, setLocal, drafts, i),
                ],
                const SizedBox(height: 12),
                if (drafts.length < kMaxOptionGroups)
                  OutlinedButton.icon(
                    onPressed: () => setLocal(() => drafts.add(_Draft())),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة مجموعة خيارات'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final built = [
                for (final d in drafts)
                  if (d.build() case final g?) g,
              ];
              Navigator.pop(ctx, built);
            },
            child: const Text('تم'),
          ),
        ],
      ),
    ),
  ).whenComplete(() {
    for (final d in drafts) {
      d.dispose();
    }
  });
}

Widget _groupEditor(
  BuildContext ctx,
  StateSetter setLocal,
  List<_Draft> drafts,
  int i,
) {
  final d = drafts[i];
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: kLine),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: d.title,
                decoration: const InputDecoration(
                  labelText: 'اسم المجموعة (مثلاً: السكر)',
                ),
              ),
            ),
            IconButton(
              tooltip: 'حذف المجموعة',
              onPressed: () => setLocal(() => drafts.removeAt(i).dispose()),
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: d.options,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'الاختيارات (كل اختيار في سطر)',
            hintText: 'سادة\nمظبوط\nكوكيز = 90',
            alignLabelWithHint: true,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('إجباري (لازم العميل يختار)'),
          value: d.required,
          onChanged: (v) => setLocal(() => d.required = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('اختيار متعدد'),
          value: d.multi,
          onChanged: (v) => setLocal(() => d.multi = v),
        ),
        if (d.multi)
          Row(
            children: [
              const Text('أقصى عدد اختيارات'),
              const Spacer(),
              IconButton(
                onPressed: d.max > 2 ? () => setLocal(() => d.max--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('${d.max}', style: const TextStyle(fontWeight: FontWeight.w800)),
              IconButton(
                onPressed: d.max < kMaxOptionsPerGroup
                    ? () => setLocal(() => d.max++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
      ],
    ),
  );
}
