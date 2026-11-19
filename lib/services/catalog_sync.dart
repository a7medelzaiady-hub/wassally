import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product_offer.dart';

/// مستند خفيف بنفس شكل QueryDocumentSnapshot (id + data()) عشان الشاشات
/// تقرأ من الفهرس أو من الاستعلام القديم بنفس الكود.
class CatalogDoc {
  const CatalogDoc(this.id, this._data);

  final String id;
  final Map<String, dynamic> _data;

  Map<String, dynamic> data() => _data;
}

/// مسارات الكتالوج المجمّع (توفير القراءات على خطة Spark):
///  • app_info/catalog_versions: { stores: n, m_<storeId>: n } — مستند صغير يتقري مرة كل جلسة.
///  • app_info/store_index:      { s_<storeId>: {بيانات المحل} } — قائمة المحلات النشطة كلها في قراءة واحدة.
///  • stores/{id}/menu/current:  { items: {<productId>: {بيانات الصنف}}, count } — أصناف المحل في قراءة واحدة.
/// أي رقم إصدار ناقص أو أقل من 1 = المسار القديم (استعلامات Firestore العادية)، فمفيش كسر.
class CatalogPaths {
  const CatalogPaths._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> get versions =>
      _db.collection('app_info').doc('catalog_versions');

  static DocumentReference<Map<String, dynamic>> get storeIndex =>
      _db.collection('app_info').doc('store_index');

  static DocumentReference<Map<String, dynamic>> menu(String storeId) =>
      _db.collection('stores').doc(storeId).collection('menu').doc('current');

  static CollectionReference<Map<String, dynamic>> products(String storeId) =>
      _db.collection('stores').doc(storeId).collection('products');

  static DocumentReference<Map<String, dynamic>> store(String storeId) =>
      _db.collection('stores').doc(storeId);
}

/// القراءة للعميل: قراءة واحدة للإصدارات كل جلسة، والفهرس/القائمة بس لما إصدارهم يتغير.
class CatalogReader {
  const CatalogReader._();

  static Future<Map<String, dynamic>?>? _versions;
  static final Set<String> _distrusted = {};

  static Future<Map<String, dynamic>?> versions() {
    return _versions ??= _loadVersions();
  }

  static Future<Map<String, dynamic>?> _loadVersions() async {
    try {
      final snap = await CatalogPaths.versions
          .get(const GetOptions(source: Source.server));
      return snap.data() ?? const {};
    } catch (e) {
      debugPrint('Catalog versions unavailable: $e');
      // نسمح بإعادة المحاولة في المرة الجاية بدل ما نفضل على المسار القديم طول الجلسة.
      _versions = null;
      return null;
    }
  }

  /// بعد أي تعديل من صاحب المحل/المدير على نفس الجهاز.
  static void invalidate() {
    _versions = null;
  }

  /// لو البوابة رفضت السعر (القائمة المخزّنة متأخرة)، نقرأ أصناف المحل من المسار القديم بقية الجلسة.
  static void distrustMenu(String storeId) {
    if (storeId.isNotEmpty) _distrusted.add(storeId);
  }

  static int? _version(Map<String, dynamic>? v, String key) {
    final value = v?[key];
    if (value is num && value >= 1) return value.toInt();
    return null;
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>?> _cachedOrServer(
    DocumentReference<Map<String, dynamic>> ref,
    String prefsKey,
    int version,
  ) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    if (prefs?.getInt(prefsKey) == version) {
      try {
        final cached = await ref.get(const GetOptions(source: Source.cache));
        if (cached.exists) return cached;
      } catch (_) {
        // مش في الكاش: نكمل للخادم.
      }
    }
    final fresh = await ref.get(const GetOptions(source: Source.server));
    if (!fresh.exists) return null;
    try {
      await prefs?.setInt(prefsKey, version);
    } catch (_) {}
    return fresh;
  }

  /// المحلات النشطة من الفهرس، أو null لو الفهرس مش جاهز (يرجع المتصل للمسار القديم).
  /// indexReady بيتكتب من بناء المدير الكامل بس، فالفهرس الجزئي (قبل أول بناء) ما يتستخدمش أبدًا.
  static Future<List<CatalogDoc>?> indexedStores() async {
    try {
      final v = await versions();
      if (v?['indexReady'] != true) return null;
      final version = _version(v, 'stores');
      if (version == null) return null;
      final snap = await _cachedOrServer(
        CatalogPaths.storeIndex,
        'catalog_index_version',
        version,
      );
      final data = snap?.data();
      if (data == null) return null;
      final out = <CatalogDoc>[];
      for (final e in data.entries) {
        final value = e.value;
        if (!e.key.startsWith('s_') || value is! Map) continue;
        final store = Map<String, dynamic>.from(value);
        if (store['active'] != true) continue;
        out.add(CatalogDoc(e.key.substring(2), store));
      }
      return out;
    } catch (e) {
      debugPrint('Store index unavailable: $e');
      return null;
    }
  }

  /// المحلات النشطة: الفهرس (قراءة واحدة) ولو مش جاهز الاستعلام القديم بنفس الكاش القديم.
  static Future<List<CatalogDoc>> activeStores(
    Future<QuerySnapshot<Map<String, dynamic>>> Function() legacy,
  ) async {
    final indexed = await indexedStores();
    if (indexed != null) return indexed;
    final snap = await legacy();
    return [for (final d in snap.docs) CatalogDoc(d.id, d.data())];
  }

  /// كل أصناف المحل من مستند القائمة، أو null لو القائمة مش جاهزة لهذا المحل.
  static Future<List<CatalogDoc>?> menu(String storeId) async {
    if (storeId.isEmpty || _distrusted.contains(storeId)) return null;
    try {
      final version = _version(await versions(), 'm_$storeId');
      if (version == null) return null;
      final snap = await _cachedOrServer(
        CatalogPaths.menu(storeId),
        'catalog_menu_version_$storeId',
        version,
      );
      final items = snap?.data()?['items'];
      if (items is! Map) return null;
      final out = <CatalogDoc>[];
      for (final e in items.entries) {
        final key = e.key;
        final value = e.value;
        if (key is String && value is Map) {
          out.add(CatalogDoc(key, Map<String, dynamic>.from(value)));
        }
      }
      return out;
    } catch (e) {
      debugPrint('Store menu unavailable for $storeId: $e');
      return null;
    }
  }
}

/// الكتابة (صاحب المحل / المدير): بعد أي تعديل على صنف أو محل نحدّث المستندات المجمّعة.
/// كل الدوال هنا "أفضل محاولة": أي فشل بيتسجّل وما بيوقفش حفظ الصنف نفسه.
///
/// أرقام إصدار القائمة (m_<storeId>):
///   ≥ 1  القائمة كاملة وصالحة للعملاء.
///   0/-1 أو ناقص: القائمة مش موثوقة → العملاء على المسار القديم، وأول تعديل يعيد البناء كامل.
///   -2   القائمة أكبر من حد المستند → المحل على المسار القديم دايمًا (من غير إعادة بناء مع كل تعديل).
class CatalogSync {
  const CatalogSync._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// أقصى عدد عناصر في الفهرس لكل قائمة عروض (لازم يطابق indexItemsOk في firestore.rules).
  static const int indexHighlightsCap = 6;

  /// أكتر من كده يبقى إعادة بناء كاملة للقائمة بدل تحديث صنف صنف.
  static const int _targetedLimit = 25;

  /// حد آمن تحت 1MiB لمستند القائمة (تقدير بالبايت).
  static const int _maxMenuBytes = 900 * 1024;

  /// الحقول اللي الشاشات بتستخدمها من مستند المحل. لازم تطابق storeIndexKeys في firestore.rules.
  static const List<String> indexKeys = [
    'name', 'category', 'icon', 'color', 'imageUrl', 'storePhone',
    'rating', 'ratingSum', 'ratingCount', 'time', 'active', 'order',
    'products', 'minOrder', 'minimumOrder', 'offerItems', 'bestItems',
  ];

  static const _itemKeys = [
    'name', 'price', 'oldPrice', 'offerText', 'offerEndsAt', 'image',
  ];

  /// ملخص العروض والأكثر مبيعًا (نفس منطق صفحة صاحب المحل) من أصناف المحل.
  static ({List<Map<String, dynamic>> offers, List<Map<String, dynamic>> best})
      highlightsFrom(Iterable<Map<String, dynamic>> products) {
    Map<String, dynamic> item(Map<String, dynamic> m) => {
          'name': (m['name'] ?? '').toString(),
          'price': (m['price'] as num?) ?? 0,
          if (m['oldPrice'] is num) 'oldPrice': m['oldPrice'],
          if ((m['offerText'] ?? '').toString().trim().isNotEmpty)
            'offerText': (m['offerText'] ?? '').toString().trim(),
          if (m['offerEndsAt'] is Timestamp) 'offerEndsAt': m['offerEndsAt'],
          'image': (m['image'] ?? '').toString(),
        };
    final sorted = products.toList()
      ..sort((a, b) => (a['name'] ?? '')
          .toString()
          .compareTo((b['name'] ?? '').toString()));
    final offers = <Map<String, dynamic>>[];
    final best = <Map<String, dynamic>>[];
    for (final m in sorted) {
      if (m['available'] == false || m['isAvailable'] == false) continue;
      final p = (m['price'] as num?) ?? 0;
      final o = m['oldPrice'];
      final e = m['offerEndsAt'];
      final expired = isOfferExpired(
        e is Timestamp ? e.toDate() : null,
        DateTime.now(),
      );
      final offerText = (m['offerText'] ?? '').toString().trim();
      final hasPriceDiscount = o is num && o > p;
      if ((hasPriceDiscount || offerText.isNotEmpty) &&
          !expired &&
          offers.length < 12) {
        offers.add(item(m));
      }
      if (m['bestSeller'] == true && best.length < 12) best.add(item(m));
    }
    return (offers: offers, best: best);
  }

  static List<Map<String, dynamic>> _indexItems(Object? raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final value in raw) {
      if (value is! Map) continue;
      final item = <String, dynamic>{};
      for (final k in _itemKeys) {
        if (value.containsKey(k)) item[k] = value[k];
      }
      out.add(item);
      if (out.length >= indexHighlightsCap) break;
    }
    return out;
  }

  /// خانة المحل في الفهرس: الحقول المعروفة بس (القواعد بتطابقها مع مستند المحل)،
  /// والصورة في imageUrl بس (من غير تكرار image)، وقوائم عروض مقصوصة.
  @visibleForTesting
  static Map<String, dynamic> indexEntry(Map<String, dynamic> store) {
    final entry = <String, dynamic>{};
    for (final k in indexKeys) {
      if (k == 'imageUrl' || k == 'offerItems' || k == 'bestItems') continue;
      if (store.containsKey(k)) entry[k] = store[k];
    }
    final image = store.containsKey('imageUrl') ? store['imageUrl'] : store['image'];
    if (image != null) entry['imageUrl'] = image;
    if (store.containsKey('offerItems')) {
      entry['offerItems'] = _indexItems(store['offerItems']);
    }
    if (store.containsKey('bestItems')) {
      entry['bestItems'] = _indexItems(store['bestItems']);
    }
    return entry;
  }

  /// تقدير حجم القائمة بالبايت (Timestamps وغيرها بتتحول لنص).
  @visibleForTesting
  static int estimateBytes(Map<String, Map<String, dynamic>> items) =>
      utf8.encode(items.toString()).length;

  static Map<String, Map<String, dynamic>> _itemsOf(Map<String, dynamic>? menu) {
    final out = <String, Map<String, dynamic>>{};
    final raw = menu?['items'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final key = e.key;
        final value = e.value;
        if (key is String && value is Map) {
          out[key] = Map<String, dynamic>.from(value);
        }
      }
    }
    return out;
  }

  static Future<int?> _menuVersion(String storeId) async {
    final snap = await CatalogPaths.versions
        .get(const GetOptions(source: Source.server));
    final v = snap.data()?['m_$storeId'];
    return v is num ? v.toInt() : null;
  }

  /// الإصدار الجاي: زيادة بواحد لو القائمة صالحة، أو 1 لو كانت معطلة/جديدة.
  static Object _nextVersion(int? current) =>
      (current == null || current < 1) ? 1 : FieldValue.increment(1);

  static Future<void> _setMenuVersion(String storeId, int value) async {
    try {
      await CatalogPaths.versions.set({
        'm_$storeId': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Could not mark menu $value for $storeId: $e');
    }
  }

  static bool _isTooLarge(Object e) =>
      e is FirebaseException &&
      (e.code == 'invalid-argument' || e.code == 'resource-exhausted');

  /// تحديث القائمة بعد تعديل/إضافة/حذف أصناف محددة.
  /// [syncStore]: تحديث خانة المحل في الفهرس لو ملخص العروض اتغير.
  static Future<void> productsChanged(
    String storeId,
    Iterable<String> productIds, {
    bool updateHighlights = true,
    bool syncStore = true,
  }) async {
    final ids = productIds.where((id) => id.isNotEmpty).toSet();
    if (storeId.isEmpty || ids.isEmpty) return;
    Map<String, Map<String, dynamic>>? items;
    try {
      final current = await _menuVersion(storeId);
      // -2: القائمة أكبر من الحد؛ المحل على المسار القديم ومفيش إعادة بناء مع كل تعديل.
      if (current == -2) return;
      final menuRef = CatalogPaths.menu(storeId);
      final menuSnap = current != null && current >= 1
          ? await menuRef.get(const GetOptions(source: Source.server))
          : null;
      // قائمة معطلة أو ناقصة أو جديدة: ما ندمجش فيها، نبنيها من الأول.
      if (menuSnap == null || !menuSnap.exists || ids.length > _targetedLimit) {
        await rebuildStoreMenu(
          storeId,
          updateHighlights: updateHighlights,
          syncStore: syncStore,
        );
        return;
      }
      items = _itemsOf(menuSnap.data());
      final docs = await Future.wait(ids.map((id) => CatalogPaths
          .products(storeId)
          .doc(id)
          .get(const GetOptions(source: Source.server))));
      final changedItems = <String, dynamic>{};
      final fields = <Object>[
        FieldPath(const ['count']),
        FieldPath(const ['updatedAt']),
      ];
      for (final doc in docs) {
        final data = doc.data();
        if (doc.exists && data != null) {
          items[doc.id] = data;
          changedItems[doc.id] = data;
        } else {
          items.remove(doc.id);
          changedItems[doc.id] = FieldValue.delete();
        }
        fields.add(FieldPath(['items', doc.id]));
      }
      if (estimateBytes(items) > _maxMenuBytes) {
        await _setMenuVersion(storeId, -2);
        return;
      }
      final batch = _db.batch()
        ..set(
          menuRef,
          {
            'items': changedItems,
            'count': items.length,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(mergeFields: fields),
        )
        ..set(
          CatalogPaths.versions,
          {
            'm_$storeId': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      await batch.commit();
    } catch (e) {
      debugPrint('Menu sync failed for $storeId: $e');
      await _setMenuVersion(storeId, _isTooLarge(e) ? -2 : -1);
      items = null;
    }
    if (updateHighlights && items != null) {
      final changed = await _writeHighlights(storeId, items.values);
      if (changed && syncStore) await storeChanged(storeId);
    }
  }

  /// إعادة بناء قائمة محل كاملة من أصنافه (للتعديلات الجماعية، أو أول مرة، أو بعد فشل).
  /// [syncStore]: تحديث خانة المحل في الفهرس بعدها (للتفعيل والاعتماد).
  static Future<bool> rebuildStoreMenu(
    String storeId, {
    bool updateHighlights = true,
    bool syncStore = true,
  }) async {
    if (storeId.isEmpty) return false;
    final items = <String, Map<String, dynamic>>{};
    var ok = false;
    try {
      final current = await _menuVersion(storeId);
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      while (true) {
        Query<Map<String, dynamic>> q = CatalogPaths.products(storeId)
            .orderBy(FieldPath.documentId)
            .limit(400);
        if (cursor != null) q = q.startAfterDocument(cursor);
        final page = await q.get(const GetOptions(source: Source.server));
        for (final d in page.docs) {
          items[d.id] = d.data();
        }
        if (page.docs.length < 400) break;
        cursor = page.docs.last;
      }
      if (estimateBytes(items) > _maxMenuBytes) {
        await _setMenuVersion(storeId, -2);
      } else {
        final batch = _db.batch()
          ..set(CatalogPaths.menu(storeId), {
            'items': items,
            'count': items.length,
            'updatedAt': FieldValue.serverTimestamp(),
          })
          ..set(
            CatalogPaths.versions,
            {
              'm_$storeId': _nextVersion(current),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        await batch.commit();
        ok = true;
      }
    } catch (e) {
      debugPrint('Menu rebuild failed for $storeId: $e');
      await _setMenuVersion(storeId, _isTooLarge(e) ? -2 : -1);
    }
    var highlightsChanged = false;
    if (ok && updateHighlights) {
      highlightsChanged = await _writeHighlights(storeId, items.values);
    }
    if (syncStore || highlightsChanged) await storeChanged(storeId);
    return ok;
  }

  /// بيرجّع true لو ملخص العروض اتغير واتحفظ على مستند المحل.
  static Future<bool> _writeHighlights(
    String storeId,
    Iterable<Map<String, dynamic>> products,
  ) async {
    try {
      final h = highlightsFrom(products);
      final snap = await CatalogPaths.store(storeId)
          .get(const GetOptions(source: Source.server));
      final data = snap.data();
      if (data == null) return false;
      if (data['offerItems'].toString() == h.offers.toString() &&
          data['bestItems'].toString() == h.best.toString()) {
        return false;
      }
      await CatalogPaths.store(storeId).update({
        'offerItems': h.offers,
        'bestItems': h.best,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('Highlights sync failed for $storeId: $e');
      return false;
    }
  }

  /// تحديث خانة المحل في الفهرس من مستند المحل الحالي (أو شيلها لو المحل مش نشط/اتحذف).
  /// محاولة تانية عند الفشل؛ ولو فشلت كمان والمستخدم مدير، بنوقف الفهرس (المسار القديم)
  /// بدل ما العملاء يفضلوا على فهرس قديم. (صاحب المحل ما يقدرش يوقفه للكل.)
  static Future<void> storeChanged(String storeId) async {
    if (storeId.isEmpty) return;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _writeStoreEntry(storeId);
        CatalogReader.invalidate();
        return;
      } catch (e) {
        debugPrint('Store index sync failed for $storeId (try ${attempt + 1}): $e');
      }
    }
    try {
      await CatalogPaths.versions.set({
        'indexReady': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // غير المدير: مسموح بس بخانة محله.
    }
    CatalogReader.invalidate();
  }

  static Future<void> _writeStoreEntry(String storeId) async {
    final snap = await CatalogPaths.store(storeId)
        .get(const GetOptions(source: Source.server));
    final data = snap.data();
    final key = FieldPath(['s_$storeId']);
    final Object entry = (snap.exists && data != null && data['active'] == true)
        ? indexEntry(data)
        : FieldValue.delete();
    final batch = _db.batch()
      ..set(
        CatalogPaths.storeIndex,
        {
          's_$storeId': entry,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(mergeFields: [key, FieldPath(const ['updatedAt'])]),
      )
      ..set(
        CatalogPaths.versions,
        {
          'stores': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    await batch.commit();
    if (!snap.exists) {
      // المحل اتحذف: نشيل قائمته اليتيمة (المدير بس يقدر؛ غيره بيتجاهل).
      try {
        await CatalogPaths.menu(storeId).delete();
      } catch (_) {}
    }
  }

  /// المدير: بناء الفهرس وكل القوائم من الصفر (أول تشغيل أو إصلاح).
  /// بيرجع ملخص نصي للعرض.
  static Future<String> rebuildAll({void Function(String)? onProgress}) async {
    final storesSnap = await _db
        .collection('stores')
        .get(const GetOptions(source: Source.server));
    var menusOk = 0;
    var menusFailed = 0;
    for (final doc in storesSnap.docs) {
      onProgress?.call('قائمة ${doc.data()['name'] ?? doc.id}');
      final ok = await rebuildStoreMenu(
        doc.id,
        updateHighlights: true,
        syncStore: false,
      );
      ok ? menusOk++ : menusFailed++;
    }
    // نقرأ المحلات تاني بعد تحديث العروض عشان الفهرس ياخد أحدث نسخة.
    final fresh = await _db
        .collection('stores')
        .get(const GetOptions(source: Source.server));
    final index = <String, dynamic>{};
    for (final doc in fresh.docs) {
      final data = doc.data();
      if (data['active'] == true) index['s_${doc.id}'] = indexEntry(data);
    }
    final storeCount = index.length;
    index['updatedAt'] = FieldValue.serverTimestamp();
    var indexOk = true;
    try {
      final batch = _db.batch()
        ..set(CatalogPaths.storeIndex, index)
        ..set(
          CatalogPaths.versions,
          {
            'stores': FieldValue.increment(1),
            'indexReady': true,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      await batch.commit();
    } catch (e) {
      indexOk = false;
      debugPrint('Store index rebuild failed: $e');
      try {
        await CatalogPaths.versions.set({
          'stores': -1,
          'indexReady': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
    CatalogReader.invalidate();
    return 'الفهرس: ${indexOk ? 'تم ($storeCount محل نشط)' : 'فشل (التطبيق هيستخدم الطريقة القديمة)'}'
        ' — القوائم: $menusOk تمام${menusFailed > 0 ? '، $menusFailed على الطريقة القديمة (كبيرة أو فشلت)' : ''}';
  }
}
