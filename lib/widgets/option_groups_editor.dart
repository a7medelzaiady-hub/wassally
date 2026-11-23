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
  final price = double.tryParse(v.replaceAll(' ', ''));
  return price != null && price.isFinite ? price : null;
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

/// محرر مجموعات الخيارات للصنف. كل المتحكمات مملوكة لحالة Dialog مستقلة،
/// وبتتحرر بعد إزالة عناصر TextField من الشجرة.
Future<List<OptionGroup>?> showOptionGroupsEditor(
  BuildContext context,
  List<OptionGroup> initial,
) {
  return showDialog<List<OptionGroup>>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _OptionGroupsEditorDialog(initial: initial),
  );
}

class _OptionGroupsEditorDialog extends StatefulWidget {
  final List<OptionGroup> initial;

  const _OptionGroupsEditorDialog({required this.initial});

  @override
  State<_OptionGroupsEditorDialog> createState() =>
      _OptionGroupsEditorDialogState();
}

class _OptionGroupsEditorDialogState extends State<_OptionGroupsEditorDialog> {
  late final List<_Draft> _drafts = widget.initial.map(_Draft.from).toList();

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _removeDraft(int index) {
    final removed = _drafts.removeAt(index);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  void _save() {
    FocusManager.instance.primaryFocus?.unfocus();
    final built = <OptionGroup>[
      for (final draft in _drafts)
        if (draft.build() case final group?) group,
    ];
    Navigator.of(context, rootNavigator: true).pop(built);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
              for (var i = 0; i < _drafts.length; i++) ...[
                const SizedBox(height: 14),
                _groupEditor(context, _drafts, i, _removeDraft, () {
                  setState(() {});
                }),
              ],
              const SizedBox(height: 12),
              if (_drafts.length < kMaxOptionGroups)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _drafts.add(_Draft())),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة مجموعة خيارات'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.of(context, rootNavigator: true).pop();
          },
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('تم'),
        ),
      ],
    );
  }
}

Widget _groupEditor(
  BuildContext ctx,
  List<_Draft> drafts,
  int i,
  void Function(int) removeDraft,
  VoidCallback refresh,
) {
  final d = drafts[i];
  return Container(
    key: ObjectKey(d),
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
              onPressed: () => removeDraft(i),
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
          onChanged: (v) {
            d.required = v;
            refresh();
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('اختيار متعدد'),
          value: d.multi,
          onChanged: (v) {
            d.multi = v;
            refresh();
          },
        ),
        if (d.multi)
          Row(
            children: [
              const Text('أقصى عدد اختيارات'),
              const Spacer(),
              IconButton(
                onPressed: d.max > 2
                    ? () {
                        d.max--;
                        refresh();
                      }
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('${d.max}', style: const TextStyle(fontWeight: FontWeight.w800)),
              IconButton(
                onPressed: d.max < kMaxOptionsPerGroup
                    ? () {
                        d.max++;
                        refresh();
                      }
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
      ],
    ),
  );
}
