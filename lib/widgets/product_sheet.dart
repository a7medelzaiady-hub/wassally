import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../utils/img.dart';
import '../utils/product_photo.dart';
import 'cached_net_image.dart';

/// أقصى كمية بتتضاف من الشاشة دي في المرة الواحدة.
const int _kMaxSheetQty = 20;

/// شاشة الصنف (زي طلبات): الصورة والوصف ومجموعات الخيارات (سكر، إضافات...) والكمية.
/// [onAdd] بتستقبل سطر السلة (الصنف بعد دمج الاختيارات) والكمية.
Future<void> showProductSheet(
  BuildContext context, {
  required Product product,
  required String storeName,
  String storeCategory = '',
  required Future<void> Function(Product line, int qty) onAdd,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ProductSheet(
      product: product,
      storeName: storeName,
      storeCategory: storeCategory,
      onAdd: onAdd,
    ),
  );
}

class _ProductSheet extends StatefulWidget {
  final Product product;
  final String storeName;
  final String storeCategory;
  final Future<void> Function(Product line, int qty) onAdd;
  const _ProductSheet({
    required this.product,
    required this.storeName,
    required this.storeCategory,
    required this.onAdd,
  });

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  // رقم المجموعة -> أرقام الاختيارات المحددة فيها.
  final Map<int, Set<int>> _picked = {};
  int _qty = 1;
  bool _busy = false;

  List<OptionGroup> get _groups => widget.product.optionGroups;

  Set<int> _sel(int g) => _picked.putIfAbsent(g, () => <int>{});

  List<ProductOption> get _chosen => [
    for (var g = 0; g < _groups.length; g++)
      for (final i in (_picked[g] ?? const <int>{}).toList()..sort())
        _groups[g].options[i],
  ];

  bool _groupOk(int g) {
    final n = (_picked[g] ?? const <int>{}).length;
    return n >= _groups[g].min && n <= _groups[g].max;
  }

  bool get _valid => [for (var g = 0; g < _groups.length; g++) _groupOk(g)].every((v) => v);

  double get _unit =>
      widget.product.price + _chosen.fold(0.0, (a, o) => a + o.price);

  void _toggle(int g, int i) {
    final group = _groups[g];
    final sel = _sel(g);
    setState(() {
      if (group.single) {
        if (sel.contains(i)) {
          // الاختياري ينفع يتلغي؛ الإجباري بيفضل محدد.
          if (!group.required) sel.clear();
        } else {
          sel
            ..clear()
            ..add(i);
        }
      } else if (sel.contains(i)) {
        sel.remove(i);
      } else if (sel.length < group.max) {
        sel.add(i);
      }
    });
  }

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);
    final line = widget.product.withChoices(_chosen);
    final nav = Navigator.of(context);
    try {
      await widget.onAdd(line, _qty);
    } finally {
      if (nav.mounted) nav.pop();
    }
  }

  String _hint(OptionGroup g) {
    if (g.single) return g.required ? 'اختر 1' : 'اختر حتى 1';
    if (g.min > 0 && g.min != g.max) return 'اختر من ${g.min} إلى ${g.max}';
    if (g.min > 0) return 'اختر ${g.max}';
    return 'اختر حتى ${g.max}';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final photo = productPhotoFor(
      name: p.name,
      uploadedUrl: p.imageUrl,
      storeCategory: widget.storeCategory,
    );
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final fallback = Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        color: Brand.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(Icons.restaurant_rounded, color: Brand.green, size: 32),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: kLine,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Brand.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.storeName,
                              style: TextStyle(fontSize: 13, color: Brand.green),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              formatPrice(p.price),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Brand.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            CachedNetImage(
                              url: thumb(photo.url, w: 300),
                              width: 84,
                              height: 84,
                              memCacheWidth: 300,
                              errorWidget: fallback,
                            ),
                            if (p.imageUrl.trim().isEmpty)
                              PositionedDirectional(
                                top: 4,
                                start: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text('توضيحية',
                                      style: TextStyle(fontSize: 9, color: Colors.white)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (p.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'وصف',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Brand.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.description.trim(),
                      style: TextStyle(fontSize: 14, height: 1.5, color: kMuted),
                    ),
                  ],
                  for (var g = 0; g < _groups.length; g++) ...[
                    const SizedBox(height: 20),
                    _groupCard(g),
                  ],
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 12 + bottom),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: kLine)),
            ),
            child: Row(
              children: [
                _stepper(),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _valid && !_busy ? _submit : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'أضف للسلة',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          formatPrice(_unit * _qty),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepper() {
    Widget btn(IconData icon, VoidCallback? onTap) => IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: onTap == null ? kMuted : Brand.green),
      visualDensity: VisualDensity.compact,
    );
    return Row(
      children: [
        btn(Icons.add_circle, _qty < _kMaxSheetQty ? () => setState(() => _qty++) : null),
        SizedBox(
          width: 26,
          child: Text(
            '$_qty',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        btn(Icons.remove_circle_outline, _qty > 1 ? () => setState(() => _qty--) : null),
      ],
    );
  }

  Widget _groupCard(int g) {
    final group = _groups[g];
    final sel = _picked[g] ?? const <int>{};
    final full = !group.single && sel.length >= group.max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                group.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Brand.ink,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: group.required
                    ? const Color(0xFFFFE9E5)
                    : const Color(0xFFF1F2F4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                group.required ? 'إجباري' : 'اختياري',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: group.required ? const Color(0xFFD64530) : kMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(_hint(group), style: TextStyle(fontSize: 12, color: kMuted)),
        const SizedBox(height: 4),
        for (var i = 0; i < group.options.length; i++)
          _optionRow(
            group,
            g,
            i,
            selected: sel.contains(i),
            disabled: full && !sel.contains(i),
          ),
      ],
    );
  }

  Widget _optionRow(
    OptionGroup group,
    int g,
    int i, {
    required bool selected,
    required bool disabled,
  }) {
    final o = group.options[i];
    final icon = group.single
        ? (selected ? Icons.radio_button_checked : Icons.radio_button_off)
        : (selected ? Icons.check_box : Icons.check_box_outline_blank);
    return InkWell(
      onTap: disabled ? null : () => _toggle(g, i),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Opacity(
          opacity: disabled ? 0.4 : 1,
          child: Row(
            children: [
              Icon(icon, color: selected ? Brand.green : kMuted, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  o.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: Brand.ink,
                  ),
                ),
              ),
              if (o.price > 0)
                Text(
                  '+${formatPrice(o.price)}',
                  style: TextStyle(fontSize: 13, color: kMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
