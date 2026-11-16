import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/store.dart';
import '../services/catalog_service.dart';
import '../services/image_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_image.dart';
import '../widgets/category_tile.dart';
import '../widgets/dialogs.dart';

/// أسماء مختصرة للأنواع الطويلة.
typedef _Json = Map<String, dynamic>;
typedef _DocSnap = QueryDocumentSnapshot<_Json>;
typedef _NewProduct = ({String id, _Json data});

const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';
const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

/// تحويل الأرقام العربية والفارسية إلى إنجليزية.
String normalizeDigits(String input) {
  var result = input;

  for (var i = 0; i < 10; i++) {
    result = result.replaceAll(_arabicDigits[i], '$i');
    result = result.replaceAll(_persianDigits[i], '$i');
  }

  return result;
}

/// تحويل السعر إلى رقم مع دعم الفاصلة العربية وفاصل الآلاف.
double? parsePrice(String input) {
  var value = normalizeDigits(input.trim())
      .replaceAll('٫', '.')
      .replaceAll('٬', '')
      .replaceAll('،', ',')
      .replaceAll(' ', '');

  if (value.contains('.') && value.contains(',')) {
    // مثال: 1,250.50 → الفاصلة للآلاف.
    value = value.replaceAll(',', '');
  } else {
    // مثال: 12,5 → الفاصلة عشرية.
    value = value.replaceAll(',', '.');
  }

  return double.tryParse(value);
}

/// جدول ترميز Windows-1256 للبايتات 0x80 إلى 0xFF.
const List<int> _cp1256 = [
  0x20AC, 0x067E, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0679, 0x2039, 0x0152, 0x0686, 0x0698, 0x0688,
  0x06AF, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x06A9, 0x2122, 0x0691, 0x203A, 0x0153, 0x200C, 0x200D, 0x06BA,
  0x00A0, 0x060C, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7,
  0x00A8, 0x00A9, 0x06BE, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF,
  0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7,
  0x00B8, 0x00B9, 0x061B, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x061F,
  0x06C1, 0x0621, 0x0622, 0x0623, 0x0624, 0x0625, 0x0626, 0x0627,
  0x0628, 0x0629, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x062F,
  0x0630, 0x0631, 0x0632, 0x0633, 0x0634, 0x0635, 0x0636, 0x00D7,
  0x0637, 0x0638, 0x0639, 0x063A, 0x0640, 0x0641, 0x0642, 0x0643,
  0x00E0, 0x0644, 0x00E2, 0x0645, 0x0646, 0x0647, 0x0648, 0x00E7,
  0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x0649, 0x064A, 0x00EE, 0x00EF,
  0x064B, 0x064C, 0x064D, 0x064E, 0x00F4, 0x064F, 0x0650, 0x00F7,
  0x0651, 0x00F9, 0x0652, 0x00FB, 0x00FC, 0x200E, 0x200F, 0x06D2,
];

/// فك ترميز الملف: UTF-8 أولًا، وإذا فشل نستخدم Windows-1256.
String _decodeBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return String.fromCharCodes([
      for (final b in bytes) b < 0x80 ? b : _cp1256[b - 0x80],
    ]);
  }
}

/// معرّف ثابت للصنف من اسمه وسعره، مع رقم تسلسلي للصفوف المتطابقة.
/// نفس الصنف يعطي نفس المعرّف دائمًا، فلا يتكرر عند إعادة الرفع.
String _productId(String name, double price, int occurrence) {
  final normalized = name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  final key = '$normalized|${price.toStringAsFixed(2)}';

  var h1 = 5381;
  var h2 = 7;

  for (final unit in key.codeUnits) {
    h1 = (((h1 * 33) % 4294967296) ^ unit) % 4294967296;
    h2 = ((h2 * 131) + unit) % 4294967296;
  }

  return 'x${h1.toRadixString(16).padLeft(8, '0')}'
      '${h2.toRadixString(16).padLeft(8, '0')}-$occurrence';
}

final CollectionReference<_Json> _stores = FirebaseFirestore.instance
    .collection('stores');

void _toast(BuildContext context, String message) {
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _errorText(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'ليس لديك صلاحية لتنفيذ العملية. تأكد أنك مدير.';
      case 'unavailable':
        return 'تعذر الاتصال بالخادم. تحقق من الإنترنت.';
      case 'not-found':
        return 'البيانات المطلوبة غير موجودة.';
      case 'resource-exhausted':
        return 'تم تجاوز الحد المسموح للعمليات. حاول مرة أخرى.';
    }
  }

  return 'تعذر تنفيذ العملية. حاول مرة أخرى.';
}

/// قراءة رابط صورة المحل من الحقل الجديد أو القديم.
String _storeImage(_Json data) {
  return (data['imageUrl'] ?? data['image'] ?? '').toString();
}

/// قائمة المحلات.
class AdminStoresPage extends StatefulWidget {
  const AdminStoresPage({super.key});

  @override
  State<AdminStoresPage> createState() => _AdminStoresPageState();
}

class _AdminStoresPageState extends State<AdminStoresPage> {
  late final Stream<QuerySnapshot<_Json>> _stream = _stores.snapshots();

  void _say(String message) {
    if (mounted) {
      _toast(context, message);
    }
  }

  Future<void> _toggle(String id, bool active) async {
    try {
      final storeRef = _stores.doc(id);
      if (active) {
        final store = await storeRef.get();
        final data = store.data() ?? {};
        if (data['approved'] == false) {
          _say('لازم تعتمد طلب المحل الأول من طلبات الانضمام.');
          return;
        }
        final image = (data['imageUrl'] ?? data['image'] ?? '').toString();
        final count = await storeRef.collection('products').count().get();
        if (image.isEmpty || (count.count ?? 0) < 5) {
          _say('لازم صورة واضحة و5 أصناف على الأقل قبل تفعيل المحل.');
          return;
        }
      }
      await storeRef.update({
        'active': active,
        if (active) 'approved': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await CatalogService.bump();
    } catch (e) {
      _say(_errorText(e));
    }
  }

  final Set<String> _deleting = {};

  /// حذف محل من القائمة: بعد تأكيد واضح، بيمسح الأصناف على دفعات (400) ثم المحل نفسه.
  Future<void> _deleteStore(String id, String name) async {
    if (_deleting.contains(id)) return;

    final ok = await confirmDialog(
      context,
      title: 'حذف المحل',
      message:
          'سيتم حذف المحل «$name» وكل أصنافه نهائيًا، ولا يمكن التراجع. '
          'لو عايز تخفيه مؤقتًا اقفله بالمفتاح بدل الحذف. متأكد؟',
      confirmLabel: 'حذف المحل',
      destructive: true,
    );

    if (!ok || !mounted) return;

    setState(() => _deleting.add(id));

    try {
      final products = _stores.doc(id).collection('products');

      while (true) {
        final snap = await products.limit(400).get();

        if (snap.docs.isEmpty) break;

        final batch = FirebaseFirestore.instance.batch();

        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
      }

      await _stores.doc(id).delete();

      await CatalogService.bump();

      _say('تم حذف المحل.');
    } catch (e) {
      _say(_errorText(e));
    } finally {
      if (mounted) {
        setState(() => _deleting.remove(id));
      }
    }
  }

  void _open(String? id, _Json? data, int nextOrder) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AdminStoreEditPage(storeId: id, data: data, nextOrder: nextOrder),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<_Json>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('المحلات والأصناف')),
            body: const Center(
              child: Text('تعذر تحميل المحلات. تحقق من الاتصال والصلاحيات.'),
            ),
          );
        }

        if (!snap.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('المحلات والأصناف')),
            body: Center(child: CircularProgressIndicator(color: kPrimary)),
          );
        }

        final docs = List<_DocSnap>.from(snap.data!.docs);

        docs.sort((a, b) {
          final orderA = (a.data()['order'] as num?)?.toInt() ?? 0;
          final orderB = (b.data()['order'] as num?)?.toInt() ?? 0;

          return orderA.compareTo(orderB);
        });

        final nextOrder = docs.isEmpty
            ? 0
            : docs
                      .map((d) => (d.data()['order'] as num?)?.toInt() ?? 0)
                      .reduce((a, b) => a > b ? a : b) +
                  1;

        return Scaffold(
          appBar: AppBar(title: const Text('المحلات والأصناف')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _open(null, null, nextOrder),
            icon: const Icon(Icons.add),
            label: const Text('إضافة محل'),
          ),
          body: docs.isEmpty
              ? const Center(
                  child: Text('لا توجد محلات حاليًا. اضغط إضافة محل.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();

                    final legacyCount = data['products'] is List
                        ? (data['products'] as List).length
                        : 0;

                    final count =
                        (data['productCount'] as num?)?.toInt() ?? legacyCount;

                    return Card(
                      child: ListTile(
                        onTap: () => _open(doc.id, data, nextOrder),
                        title: Text((data['name'] ?? '').toString()),
                        subtitle: Text(
                          '${data['category'] ?? ''} • $count صنف',
                        ),
                        leading: AppImage(
                          url: _storeImage(data),
                          fallbackIcon: Icons.store,
                          color: kPrimary,
                          width: 48,
                          height: 48,
                          iconSize: 24,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'حذف المحل',
                              color: kDanger,
                              icon: _deleting.contains(doc.id)
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.delete_outline_rounded),
                              onPressed: _deleting.contains(doc.id)
                                  ? null
                                  : () => _deleteStore(
                                      doc.id,
                                      (data['name'] ?? '').toString(),
                                    ),
                            ),
                            Switch(
                              value: (data['active'] as bool?) ?? true,
                              onChanged: (value) => _toggle(doc.id, value),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// إضافة محل أو تعديل محل.
class AdminStoreEditPage extends StatefulWidget {
  final String? storeId;
  final Map<String, dynamic>? data;
  final int nextOrder;

  const AdminStoreEditPage({
    super.key,
    this.storeId,
    this.data,
    this.nextOrder = 0,
  });

  @override
  State<AdminStoreEditPage> createState() => _AdminStoreEditPageState();
}

class _AdminStoreEditPageState extends State<AdminStoreEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _time;

  late String _category;
  late String _icon;

  /// الأصناف القديمة (قائمة داخل مستند المحل) للعرض والترحيل فقط.
  late final List<_Json> _products;

  String? _id;

  bool _busy = false;
  bool _uploading = false;

  String _image = '';

  void _say(String message) {
    if (mounted) {
      _toast(context, message);
    }
  }

  @override
  void initState() {
    super.initState();

    final _Json data = widget.data ?? {};

    _id = widget.storeId;

    _name = TextEditingController(text: (data['name'] ?? '').toString());

    final storedCategory = (data['category'] ?? '').toString();
    _category = isPharmacyCategory(storedCategory)
        ? 'صيدليات'
        : storedCategory;

    _time = TextEditingController(text: (data['time'] ?? '').toString());

    _image = _storeImage(data);

    final icon = (data['icon'] ?? 'store').toString();

    _icon = iconOptions.containsKey(icon) ? icon : 'store';

    _products = [];

    final rawProducts = data['products'];

    if (rawProducts is List) {
      for (final product in rawProducts) {
        if (product is Map) {
          _products.add(_Json.from(product));
        }
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _time.dispose();
    super.dispose();
  }

  Future<void> _pickStoreImage() async {
    if (_uploading || _busy) return;

    setState(() => _uploading = true);

    try {
      final url = await ImageService.pickAndUpload('stores');

      if (url != null && mounted) {
        setState(() => _image = url);
        _say('تم رفع صورة المحل. اضغط حفظ لتثبيتها.');
      }
    } catch (e) {
      debugPrint('Store image upload error: $e');
      _say('تعذر رفع الصورة. حاول مرة أخرى.');
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _saveStore() async {
    if (_busy) return;

    final name = _name.text.trim();
    final category = _category.trim();

    if (name.isEmpty || category.isEmpty) {
      _say('اكتب اسم المحل والتصنيف.');
      return;
    }

    setState(() => _busy = true);

    try {
      final _Json fields = {
        'name': name,
        'category': category,
        'icon': _icon,
        'time': _time.text.trim(),
        'imageUrl': _image,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_id == null) {
        final ref = await _stores.add({
          ...fields,
          'color': kPrimary.toARGB32(),
          'rating': 0,
          'active': true,
          'order': widget.nextOrder,
          'productCount': 0,
        });

        _id = ref.id;
      } else {
        await _stores.doc(_id).update(fields);
      }

      await CatalogService.bump();

      if (!mounted) return;

      setState(() {});
      _say('تم حفظ المحل بنجاح.');
    } catch (e) {
      _say(_errorText(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _migrate() async {
    final id = _id;

    if (id == null || _busy || _products.isEmpty) return;

    final ok = await confirmDialog(
      context,
      title: 'ترحيل الأصناف',
      message:
          'سيتم نقل ${_products.length} صنف إلى النظام الجديد. '
          'لن يتم حذف القائمة القديمة إلا بعد نجاح جميع الدفعات.',
      confirmLabel: 'ترحيل',
    );

    if (!ok || !mounted) return;

    setState(() => _busy = true);

    try {
      final col = _stores.doc(id).collection('products');

      final total = _products.length;

      // معرفات ثابتة من الاسم والسعر: لا تتعارض مع الأصناف الموجودة،
      // وإعادة الترحيل بعد فشل جزئي تكتب فوق نفس المستندات فقط.
      final seen = <String, int>{};
      final ids = <String>[];

      for (final product in _products) {
        final name = (product['name'] ?? '').toString();
        final price = (product['price'] as num?)?.toDouble() ?? 0;

        final base = _productId(name, price, 0);
        final n = seen[base] = (seen[base] ?? -1) + 1;

        ids.add(_productId(name, price, n));
      }

      for (var start = 0; start < total; start += 400) {
        final end = start + 400 > total ? total : start + 400;

        final batch = FirebaseFirestore.instance.batch();

        for (var i = start; i < end; i++) {
          final product = _products[i];

          final image = (product['image'] ?? '').toString();

          batch.set(col.doc(ids[i]), {
            'name': (product['name'] ?? '').toString(),
            'price': (product['price'] as num?)?.toDouble() ?? 0,
            if (image.isNotEmpty) 'image': image,
            'isAvailable': true,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();
      }

      // العدد الفعلي بعد الترحيل.
      final countSnap = await col.count().get();

      await _stores.doc(id).update({
        'products': FieldValue.delete(),
        'productCount': countSnap.count ?? total,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await CatalogService.bump();

      if (!mounted) return;

      setState(() {
        _products.clear();
      });

      _say('تم ترحيل $total صنف بنجاح.');
    } catch (e) {
      _say('تعذر إكمال الترحيل. لم يتم حذف القائمة القديمة. ${_errorText(e)}');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// عرض الأصناف القديمة (للقراءة) مع زر الترحيل.
  List<Widget> _legacyProducts() {
    return [
      Text(
        'الأصناف (${_products.length})',
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          'هذا المحل يستخدم النظام القديم للأصناف. '
          'رحّل الأصناف أولًا لتتمكن من إضافتها وتعديلها وحذفها.',
        ),
      ),
      if (_id != null)
        Card(
          color: kPrimary.withValues(alpha: 0.06),
          child: ListTile(
            leading: Icon(Icons.upgrade_rounded, color: kPrimary),
            title: const Text('ترحيل الأصناف للنظام الجديد'),
            subtitle: const Text(
              'يساعد على تحسين الأداء عند وجود أصناف كثيرة.',
            ),
            onTap: _busy ? null : _migrate,
          ),
        ),
      for (final product in _products)
        Card(
          child: ListTile(
            leading: AppImage(
              url: (product['image'] ?? '').toString(),
              fallbackIcon: Icons.fastfood,
              color: kPrimary,
              width: 48,
              height: 48,
              iconSize: 24,
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text((product['name'] ?? '').toString()),
            subtitle: Text(formatPrice((product['price'] as num?) ?? 0)),
          ),
        ),
    ];
  }

  Future<void> _deleteStore() async {
    if (_id == null || _busy) return;

    final ok = await confirmDialog(
      context,
      title: 'حذف المحل',
      message: 'حذف المحل وكل أصنافه نهائيًا؟ هذا الإجراء لا يمكن التراجع عنه.',
      confirmLabel: 'حذف',
      destructive: true,
    );

    if (!ok || !mounted) return;

    setState(() => _busy = true);

    try {
      final products = _stores.doc(_id).collection('products');

      while (true) {
        final snap = await products.limit(400).get();

        if (snap.docs.isEmpty) break;

        final batch = FirebaseFirestore.instance.batch();

        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
      }

      await _stores.doc(_id).delete();

      await CatalogService.bump();

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _say(_errorText(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _id == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'محل جديد' : 'تعديل المحل'),
        actions: [
          if (!isNew)
            IconButton(
              tooltip: 'حذف المحل',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _deleteStore,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: _ImagePickerBox(
              url: _image,
              uploading: _uploading,
              size: 140,
              onTap: _pickStoreImage,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'اسم المحل'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category.isEmpty ? null : _category,
            decoration: const InputDecoration(labelText: 'التصنيف'),
            items: [
              for (final category in {
                for (final item in kCategories)
                  if (item.category != 'الكل') item.category,
                if (_category.isNotEmpty) _category,
              })
                DropdownMenuItem(value: category, child: Text(category)),
            ],
            onChanged: (value) {
              setState(() {
                _category = value ?? _category;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _time,
            decoration: const InputDecoration(
              labelText: 'مدة التوصيل',
              helperText: 'مثال: 25-35 د',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _icon,
            decoration: const InputDecoration(labelText: 'الأيقونة'),
            items: [
              for (final entry in iconOptions.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Row(
                    children: [
                      Icon(entry.value, size: 20),
                      const SizedBox(width: 8),
                      Text(entry.key),
                    ],
                  ),
                ),
            ],
            onChanged: (value) {
              setState(() {
                _icon = value ?? _icon;
              });
            },
          ),
          const SizedBox(height: 16),
          _busy
              ? Center(child: CircularProgressIndicator(color: kPrimary))
              : FilledButton(
                  onPressed: _saveStore,
                  child: Text(isNew ? 'حفظ المحل' : 'حفظ التعديلات'),
                ),
          const SizedBox(height: 24),
          if (_products.isNotEmpty)
            ..._legacyProducts()
          else if (_id != null)
            _ProductsAdmin(storeId: _id!)
          else
            const Text('احفظ المحل أولًا ثم أضف الأصناف.'),
        ],
      ),
    );
  }
}

/// مربع اختيار الصورة.
class _ImagePickerBox extends StatelessWidget {
  final String url;
  final bool uploading;
  final double size;
  final VoidCallback onTap;

  const _ImagePickerBox({
    required this.url,
    required this.uploading,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'اختيار صورة',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: uploading ? null : onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AppImage(
              url: url,
              fallbackIcon: Icons.add_a_photo_outlined,
              color: kPrimary,
              width: size,
              height: size,
              iconSize: size * 0.35,
              borderRadius: BorderRadius.circular(18),
            ),
            if (uploading)
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            else if (url.isNotEmpty)
              Positioned(
                bottom: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.edit, size: 16, color: kPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

typedef _ProductInput = ({String name, double price, String image});

/// نافذة إضافة/تعديل صنف. ترجع null عند الإلغاء.
Future<_ProductInput?> _productDialog(BuildContext context, {_Json? existing}) {
  return showDialog<_ProductInput>(
    context: context,
    builder: (_) => _ProductDialog(existing: existing),
  );
}

/// نافذة الصنف كـ StatefulWidget حتى تُحذف الـ controllers بأمان
/// بعد انتهاء حركة إغلاق النافذة، ويتم التحقق من الحقول دون إغلاقها.
class _ProductDialog extends StatefulWidget {
  final _Json? existing;

  const _ProductDialog({this.existing});

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final TextEditingController _name;
  late final TextEditingController _price;

  late String _image;

  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    _name = TextEditingController(text: (existing?['name'] ?? '').toString());

    final rawPrice = existing?['price'];

    String priceText = '';

    if (rawPrice is num) {
      priceText = rawPrice == rawPrice.roundToDouble()
          ? rawPrice.toInt().toString()
          : rawPrice.toString();
    }

    _price = TextEditingController(text: priceText);

    _image = (existing?['image'] ?? '').toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_uploading) return;

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final url = await ImageService.pickAndUpload('products');

      if (url != null && mounted) {
        setState(() => _image = url);
      }
    } catch (e) {
      debugPrint('Product image upload error: $e');

      if (mounted) {
        setState(() => _error = 'تعذر رفع صورة الصنف. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  void _submit() {
    final name = _name.text.trim();
    final price = parsePrice(_price.text);

    if (name.isEmpty || price == null || price <= 0) {
      setState(() {
        _error = 'اكتب اسم الصنف وسعر صحيح أكبر من صفر.';
      });
      return;
    }

    final _ProductInput input = (name: name, price: price, image: _image);

    Navigator.pop(context, input);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'إضافة صنف' : 'تعديل صنف'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ImagePickerBox(
              url: _image,
              uploading: _uploading,
              size: 120,
              onTap: _pickImage,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'اسم الصنف'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'السعر (ج.م)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: _uploading ? null : _submit,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

/// إدارة أصناف المحل الجديد.
class _ProductsAdmin extends StatefulWidget {
  final String storeId;

  const _ProductsAdmin({required this.storeId});

  @override
  State<_ProductsAdmin> createState() => _ProductsAdminState();
}

class _ProductsAdminState extends State<_ProductsAdmin> {
  static const int _pageSize = 30;
  static const int _batchSize = 400;

  final TextEditingController _search = TextEditingController();

  final List<_DocSnap> _docs = [];

  Timer? _debounce;

  bool _loading = false;
  bool _hasMore = true;
  bool _error = false;
  bool _uploadingFile = false;

  String _term = '';

  int _gen = 0;

  DocumentReference<_Json> get _storeRef => _stores.doc(widget.storeId);

  CollectionReference<_Json> get _col => _storeRef.collection('products');

  void _say(String message) {
    if (mounted) {
      _toast(context, message);
    }
  }

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// يضبط productCount على العدد الفعلي للأصناف في Firestore.
  Future<void> _syncCount() async {
    final snap = await _col.count().get();

    await _storeRef.update({
      'productCount': snap.count ?? 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _gen++;
      _docs.clear();
      _hasMore = true;
      _error = false;
    } else if (_loading || !_hasMore) {
      return;
    }

    final generation = _gen;

    setState(() {
      _loading = true;
    });

    try {
      Query<_Json> query = _col.orderBy('name');

      if (_term.isNotEmpty) {
        query = query
            .where('name', isGreaterThanOrEqualTo: _term)
            .where('name', isLessThan: '$_term\uf8ff');
      }

      if (_docs.isNotEmpty) {
        query = query.startAfterDocument(_docs.last);
      }

      final snapshot = await query
          .limit(_pageSize)
          .get(const GetOptions(source: Source.server));

      if (!mounted || generation != _gen) return;

      setState(() {
        _docs.addAll(snapshot.docs);
        _hasMore = snapshot.docs.length == _pageSize;
        _loading = false;
        _error = false;
      });
    } catch (e) {
      if (!mounted || generation != _gen) return;

      setState(() {
        _error = true;
        _loading = false;
      });

      debugPrint('Products loading error: $e');
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;

      final term = value.trim();

      if (term == _term) return;

      _term = term;
      _load(reset: true);
    });
  }

  /// تحليل CSV مع دعم علامات الاقتباس.
  List<List<String>> _parseCsv(String content) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();

    var inQuotes = false;

    for (var i = 0; i < content.length; i++) {
      final char = content[i];

      if (char == '"') {
        if (inQuotes && i + 1 < content.length && content[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        row.add(field.toString());
        field.clear();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < content.length && content[i + 1] == '\n') {
          i++;
        }

        row.add(field.toString());

        if (row.any((value) => value.trim().isNotEmpty)) {
          rows.add(row);
        }

        row = [];
        field.clear();
      } else {
        field.write(char);
      }
    }

    row.add(field.toString());

    if (row.any((value) => value.trim().isNotEmpty)) {
      rows.add(row);
    }

    return rows;
  }

  Future<void> _uploadBatchProducts() async {
    if (_loading || _uploadingFile) {
      _say('انتظر انتهاء العملية الحالية أولًا.');
      return;
    }

    var uploaded = 0;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.single.bytes;

      if (bytes == null) {
        _say('تعذر قراءة الملف. حاول اختيار الملف مرة أخرى.');
        return;
      }

      var content = _decodeBytes(bytes);

      if (content.startsWith('\uFEFF')) {
        content = content.substring(1);
      }

      final rows = _parseCsv(content);

      if (rows.isEmpty) {
        _say('الملف فارغ.');
        return;
      }

      final validProducts = <_NewProduct>[];
      final seen = <String, int>{};

      for (final row in rows) {
        if (row.length < 2) continue;

        final name = row[0].trim();
        final priceText = row[1].trim();

        // تجاهل عنوان الأعمدة.
        final normalizedName = name.toLowerCase();

        if (normalizedName == 'name' ||
            name == 'اسم الصنف' ||
            name == 'الاسم') {
          continue;
        }

        final price = parsePrice(priceText);

        if (name.isEmpty || price == null || price <= 0) {
          continue;
        }

        final image = row.length > 2 ? row[2].trim() : '';

        // نفس الاسم والسعر = نفس المعرّف، والصفوف المتطابقة داخل الملف
        // تأخذ رقمًا تسلسليًا حتى لا يضيع أي منها.
        final base = _productId(name, price, 0);
        final n = seen[base] = (seen[base] ?? -1) + 1;

        final _Json data = {
          'name': name,
          'price': price,
          if (image.isNotEmpty) 'image': image,
          'isAvailable': true,
          'createdAt': FieldValue.serverTimestamp(),
        };

        validProducts.add((id: _productId(name, price, n), data: data));
      }

      if (validProducts.isEmpty) {
        _say('لم يتم العثور على أصناف صالحة داخل الملف.');
        return;
      }

      if (!mounted) return;
      final ok = await confirmDialog(
        context,
        title: 'رفع الأصناف',
        message: 'سيتم رفع ${validProducts.length} صنف من الملف. متابعة؟',
        confirmLabel: 'رفع',
      );

      if (!ok || !mounted) return;

      setState(() => _uploadingFile = true);

      for (var start = 0; start < validProducts.length; start += _batchSize) {
        final end = start + _batchSize > validProducts.length
            ? validProducts.length
            : start + _batchSize;

        final batch = FirebaseFirestore.instance.batch();

        for (var i = start; i < end; i++) {
          final item = validProducts[i];

          // merge: إعادة رفع نفس الملف تكتب فوق نفس المستندات ولا تكررها.
          batch.set(_col.doc(item.id), item.data, SetOptions(merge: true));
        }

        await batch.commit();

        uploaded += end - start;
      }

      await _syncCount();
      await CatalogService.bump();

      if (!mounted) return;

      _say('تم رفع $uploaded صنف بنجاح.');

      _load(reset: true);
    } catch (e) {
      debugPrint('CSV upload error: $e');

      if (uploaded > 0) {
        try {
          await _syncCount();
          await CatalogService.bump();
        } catch (_) {}

        if (mounted) _load(reset: true);

        _say(
          'تم رفع $uploaded صنف قبل حدوث خطأ: ${_errorText(e)} '
          'يمكنك إعادة رفع نفس الملف بأمان دون تكرار.',
        );
      } else {
        _say('حدث خطأ أثناء رفع الملف: ${_errorText(e)}');
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingFile = false);
      }
    }
  }

  Future<void> _edit(_DocSnap? doc) async {
    final result = await _productDialog(context, existing: doc?.data());

    if (result == null || !mounted) return;

    final _Json data = {
      'name': result.name,
      'price': result.price,
      'image': result.image,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (doc == null) {
        await _col.doc().set({
          ...data,
          'isAvailable': true,
          'createdAt': FieldValue.serverTimestamp(),
        });

        await _syncCount();
      } else {
        await doc.reference.update(data);
      }

      await CatalogService.bump();

      await _load(reset: true);

      _say('تم حفظ الصنف.');
    } catch (e) {
      _say(_errorText(e));
    }
  }

  Future<void> _delete(_DocSnap doc) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف صنف',
      message: 'حذف "${doc.data()['name'] ?? ''}"؟',
      confirmLabel: 'حذف',
      destructive: true,
    );

    if (!ok || !mounted) return;

    try {
      await doc.reference.delete();

      await _syncCount();

      await CatalogService.bump();

      if (!mounted) return;

      setState(() {
        _docs.removeWhere((item) => item.id == doc.id);
      });

      _say('تم حذف الصنف.');
    } catch (e) {
      _say(_errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'الأصناف',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: _uploadingFile ? null : _uploadBatchProducts,
              icon: _uploadingFile
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file, color: Colors.green),
              label: const Text('رفع ملف'),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('إضافة صنف'),
            ),
          ],
        ),
        TextField(
          controller: _search,
          onChanged: _onSearch,
          decoration: const InputDecoration(
            labelText: 'بحث من أول اسم الصنف',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        if (_error)
          Row(
            children: [
              const Expanded(child: Text('تعذر تحميل الأصناف.')),
              TextButton(
                onPressed: () => _load(reset: true),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        if (!_error && !_loading && _docs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _term.isEmpty ? 'لا توجد أصناف حاليًا.' : 'لا توجد نتائج للبحث.',
            ),
          ),
        for (final doc in _docs)
          Card(
            child: ListTile(
              leading: AppImage(
                url: (doc.data()['image'] ?? '').toString(),
                fallbackIcon: Icons.fastfood,
                color: kPrimary,
                width: 48,
                height: 48,
                iconSize: 24,
                borderRadius: BorderRadius.circular(12),
              ),
              title: Text((doc.data()['name'] ?? '').toString()),
              subtitle: Text(formatPrice((doc.data()['price'] as num?) ?? 0)),
              onTap: () => _edit(doc),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(doc),
              ),
            ),
          ),
        if (_loading)
          Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(color: kPrimary)),
          ),
        if (_hasMore && !_loading && _docs.isNotEmpty)
          Center(
            child: TextButton(
              onPressed: _load,
              child: const Text('عرض المزيد'),
            ),
          ),
      ],
    );
  }
}
