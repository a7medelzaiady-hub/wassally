import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/order.dart';
import '../models/product_offer.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// صنف ينفع يتقترح بديل: متاح، ومن غير خيارات/إضافات (سطر البديل بيتضاف من غير
/// اختيارات، والـWorker بيرفض صنف ناقص اختياراته الإجبارية).
/// السعر = السعر اللي العميل بيشوفه (بعد تجاهل العرض المنتهي)، نفس حساب الـWorker.
OrderSubstitute? substituteFromCatalog(String id, Map<String, dynamic> m, {DateTime? now}) {
  if (m['available'] == false || m['isAvailable'] == false) return null;
  final groups = m['optionGroups'];
  if (groups is List && groups.isNotEmpty) return null;
  final name = (m['name'] ?? '').toString().trim();
  final price = m['price'];
  if (id.isEmpty || name.isEmpty || price is! num || price <= 0) return null;
  final ends = m['offerEndsAt'];
  final offer = resolveOfferDisplay(
    price: price.toDouble(),
    oldPrice: m['oldPrice'] is num ? (m['oldPrice'] as num).toDouble() : 0,
    text: (m['offerText'] ?? '').toString(),
    endsAt: ends is Timestamp ? ends.toDate() : (ends is DateTime ? ends : null),
    now: now,
  );
  return OrderSubstitute(productId: id, name: name, price: offer.price);
}

/// أصناف المحل للاختيار: من مستند القائمة المجمّعة (الكاش الأول، وإلا قراءة واحدة)،
/// ولو المحل ما عندوش قائمة مجمّعة: أصناف المحل (الكاش الأول).
Future<List<OrderSubstitute>> _loadCatalog(String storeId) async {
  final store = FirebaseFirestore.instance.collection('stores').doc(storeId);
  final out = <OrderSubstitute>[];
  Map<String, dynamic>? menu;
  for (final source in [Source.cache, Source.server]) {
    try {
      final snap = await store.collection('menu').doc('current').get(GetOptions(source: source));
      if (snap.exists && snap.data()?['items'] is Map) {
        menu = snap.data();
        break;
      }
    } catch (_) {}
  }
  final items = menu?['items'];
  if (items is Map) {
    items.forEach((id, value) {
      if (value is Map) {
        final s = substituteFromCatalog(id.toString(), Map<String, dynamic>.from(value));
        if (s != null) out.add(s);
      }
    });
  } else {
    final query = store.collection('products').orderBy('name').limit(200);
    QuerySnapshot<Map<String, dynamic>>? snap;
    try {
      snap = await query.get(const GetOptions(source: Source.cache));
      if (snap.docs.isEmpty) snap = null;
    } catch (_) {}
    snap ??= await query.get();
    for (final d in snap.docs) {
      final s = substituteFromCatalog(d.id, d.data());
      if (s != null) out.add(s);
    }
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

/// بيفتح قايمة أصناف المحل عشان صاحب المحل يختار بديل لصنف ناقص.
Future<OrderSubstitute?> pickSubstitute(
  BuildContext context, {
  required String storeId,
  required String missingName,
  Set<String> excludeIds = const {},
}) {
  return showModalBottomSheet<OrderSubstitute>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _SubstitutePickerSheet(
        future: _loadCatalog(storeId),
        missingName: missingName,
        excludeIds: excludeIds,
      ),
    ),
  );
}

class _SubstitutePickerSheet extends StatefulWidget {
  final Future<List<OrderSubstitute>> future;
  final String missingName;
  final Set<String> excludeIds;
  const _SubstitutePickerSheet({
    required this.future,
    required this.missingName,
    required this.excludeIds,
  });

  @override
  State<_SubstitutePickerSheet> createState() => _SubstitutePickerSheetState();
}

class _SubstitutePickerSheetState extends State<_SubstitutePickerSheet> {
  String _term = '';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'بديل لـ«${widget.missingName}»',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          const Text(
            'العميل هيشوف البديل وسعره ويوافق أو يرفض.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          TextField(
            autofocus: false,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'دوّر على صنف',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _term = v.trim()),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: FutureBuilder<List<OrderSubstitute>>(
              future: widget.future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(child: Text('تعذر تحميل أصناف المحل. جرّب تاني.'));
                }
                if (!snap.hasData) {
                  return Center(child: CircularProgressIndicator(color: kPrimary));
                }
                final shown = [
                  for (final s in snap.data!)
                    if (!widget.excludeIds.contains(s.productId) &&
                        (_term.isEmpty || s.name.contains(_term)))
                      s,
                ];
                if (shown.isEmpty) {
                  return const Center(child: Text('مفيش أصناف مناسبة.'));
                }
                return ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    title: Text(shown[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: Text(formatPrice(shown[i].price)),
                    onTap: () => Navigator.of(context).pop(shown[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
