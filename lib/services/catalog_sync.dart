import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_menu_sync.dart';
import 'catalog_service.dart';
import 'read_meter.dart';
import 'store_highlights.dart';

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
      ReadMeter.document('catalog:versions', snap);
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

  static String _distrustKey(String storeId) => 'catalog_distrust_$storeId';

  /// لو البوابة رفضت السعر (القائمة متأخرة عن الأصناف)، نقرأ أصناف المحل من المسار القديم.
  /// القرار بيتحفظ على الجهاز مربوط برقم إصدار القائمة، فبيفضل بعد إعادة فتح التطبيق،
  /// وبيتلغي تلقائيًا أول ما القائمة تتحدث (رقم إصدار جديد).
  static Future<void> distrustMenu(String storeId) async {
    if (storeId.isEmpty) return;
    _distrusted.add(storeId);
    try {
      final version = _version(await versions(), 'm_$storeId');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_distrustKey(storeId), version ?? 0);
    } catch (_) {}
  }

  /// [distrustedAt]: رقم الإصدار اللي اترفض عنده (محفوظ)، [current]: الإصدار الحالي.
  @visibleForTesting
  static bool menuUsable({required int? current, int? distrustedAt}) =>
      current != null && current >= 1 && distrustedAt != current;

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
    ReadMeter.document('catalog:${prefsKey.startsWith('catalog_menu') ? 'menu' : 'index'}', fresh);
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
    if (storeId.isEmpty) return null;
    try {
      final version = _version(await versions(), 'm_$storeId');
      int? distrustedAt;
      try {
        final prefs = await SharedPreferences.getInstance();
        distrustedAt = prefs.getInt(_distrustKey(storeId));
      } catch (_) {}
      // في نفس الجلسة: لو اترفضت ولسه مفيش إصدار أحدث من اللي اتحفظ.
      if (_distrusted.contains(storeId) && distrustedAt == null) return null;
      if (version == null ||
          !menuUsable(current: version, distrustedAt: distrustedAt)) {
        return null;
      }
      _distrusted.remove(storeId);
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
/// أرقام إصدار القائمة (m_<storeId>) ما تتكررش أبدًا، عشان العميل بيستخدم الكاش لما الرقم يطابق:
///   ≥ 1  القائمة كاملة وصالحة للعملاء.
///   ≤ 0 أو ناقص: القائمة معطلة (سالب آخر إصدار صالح) → العملاء على المسار القديم،
///         وأول تعديل يعيد البناء كامل ويكتب |السابق| + 1.
/// big_<storeId> = true: القائمة أكبر من حد المستند → المسار القديم من غير إعادة بناء مع كل تعديل.
class CatalogSync {
  const CatalogSync._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static MenuSync menuSync = MenuSync(FirestoreCatalogBackend());

  /// أقصى عدد عناصر في الفهرس لكل قائمة عروض (لازم يطابق indexItemsOk في firestore.rules).
  static const int indexHighlightsCap = 6;

  /// حد حجم خانة المحل في الفهرس، وأقصى عدد محلات (لازم يطابق storeIndexWriteOk في القواعد).
  /// 250 × 3.5KB ≈ 875KB تحت حد المستند (1MiB) بهامش.
  static const int maxIndexEntryBytes = 3500;
  static const int maxIndexStores = 250;
  static const int maxIndexBytes = 900 * 1024;

  /// الحقول اللي الشاشات بتستخدمها من مستند المحل. لازم تطابق storeIndexKeys في firestore.rules.
  static const List<String> indexKeys = [
    'name', 'category', 'icon', 'color', 'imageUrl', 'storePhone',
    'rating', 'ratingSum', 'ratingCount', 'time', 'active', 'order',
    'products', 'minOrder', 'minimumOrder', 'offerItems', 'bestItems',
  ];

  static const _itemKeys = [
    'name', 'price', 'oldPrice', 'offerText', 'offerEndsAt', 'image',
  ];

  @visibleForTesting
  static int estimateBytes(Object? value) => utf8.encode(value.toString()).length;

  /// ملخص العروض والأكثر مبيعًا من أصناف المحل (نفس منطق StoreHighlights، مرتب بالاسم).
  static ({List<Map<String, dynamic>> offers, List<Map<String, dynamic>> best})
      highlightsFrom(Iterable<Map<String, dynamic>> products) {
    final sorted = products.toList()
      ..sort((a, b) => (a['name'] ?? '')
          .toString()
          .compareTo((b['name'] ?? '').toString()));
    return StoreHighlights.compute(sorted);
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
  /// والصورة في imageUrl بس، وقوائم عروض مقصوصة لحد ما الخانة تبقى تحت [maxIndexEntryBytes]
  /// (القواعد بتقبل أي عدد من 0 لـ 6، فالقص ما بيكسرش المطابقة).
  @visibleForTesting
  static Map<String, dynamic> indexEntry(Map<String, dynamic> store) {
    final entry = <String, dynamic>{};
    for (final k in indexKeys) {
      if (k == 'imageUrl' || k == 'offerItems' || k == 'bestItems') continue;
      if (store.containsKey(k)) entry[k] = store[k];
    }
    final image = store.containsKey('imageUrl') ? store['imageUrl'] : store['image'];
    if (image != null) entry['imageUrl'] = image;
    final offers = store.containsKey('offerItems')
        ? [..._indexItems(store['offerItems'])]
        : null;
    final best = store.containsKey('bestItems')
        ? [..._indexItems(store['bestItems'])]
        : null;
    void put() {
      if (offers != null) entry['offerItems'] = offers;
      if (best != null) entry['bestItems'] = best;
    }

    put();
    // الأكثر مبيعًا الأول، بعدين العروض، من الآخر.
    while (estimateBytes(entry) > maxIndexEntryBytes) {
      if (best != null && best.isNotEmpty) {
        best.removeLast();
      } else if (offers != null && offers.isNotEmpty) {
        offers.removeLast();
      } else {
        break;
      }
      put();
    }
    return entry;
  }

  /// خانة لسه أكبر من الحد بعد القص (غالبًا قائمة أصناف قديمة "products" على مستند المحل):
  /// ما تتكتبش، والمحل محتاج ترحيل أصنافه من لوحة المدير.
  @visibleForTesting
  static bool indexEntryTooBig(Map<String, dynamic> entry) =>
      estimateBytes(entry) > maxIndexEntryBytes;

  /// فحص الفهرس الكامل قبل الحفظ (للمدير): null لو تمام، أو سبب الرفض.
  @visibleForTesting
  static String? indexProblem(Map<String, Map<String, dynamic>> entries) {
    final tooBig = [
      for (final e in entries.entries)
        if (indexEntryTooBig(e.value)) (e.value['name'] ?? e.key).toString(),
    ];
    if (tooBig.isNotEmpty) {
      return 'محلات بيانات خانتها كبيرة (رحّل أصنافها القديمة): ${tooBig.join('، ')}';
    }
    if (entries.length > maxIndexStores) {
      return 'عدد المحلات النشطة (${entries.length}) أكبر من حد الفهرس ($maxIndexStores)';
    }
    final total = estimateBytes(entries);
    if (total > maxIndexBytes) {
      return 'حجم الفهرس (${total ~/ 1024}KB) أكبر من الحد الآمن';
    }
    return null;
  }

  // ───────────────────────── بعد تعديل الأصناف ─────────────────────────

  /// قبل كتابة الصنف: علامة على الجهاز إن قائمة المحل محتاجة مزامنة (بتتشال بعد النجاح).
  static Future<void> markPending(String storeId, [Iterable<String>? productIds]) =>
      CatalogPending.mark(storeId, productIds);

  /// بعد أي إضافة/تعديل/حذف أصناف. الترتيب:
  ///  1) القائمة المجمّعة (معاملة؛ فشلها = تعطيل على الخادم)،
  ///  2) ملخص العروض على مستند المحل (من القائمة نفسها من غير قراءات، أو من الخادم لو القائمة مش شغالة)،
  ///  3) خانة المحل في الفهرس لو الملخص اتغير،
  ///  4) رقم إصدار الكتالوج القديم (للمسار القديم) في الآخر،
  /// عشان العميل اللي يشوف أي رقم جديد ياخد بيانات جديدة.
  /// [productIds] = null → إعادة بناء كاملة (CSV/ترحيل). بيرجع true لو ملخص العروض اتحدث.
  static Future<bool> afterProductsChanged(
    String storeId, {
    Iterable<String>? productIds,
  }) async {
    if (storeId.isEmpty) return false;
    final ids = productIds?.where((id) => id.isNotEmpty).toSet();
    final menu = await menuSync.sync(storeId, productIds: ids);

    var highlightsOk = false;
    var highlightsChanged = false;
    final items = menu.items;
    if (items != null) {
      final r = await _writeHighlights(storeId, items.values);
      highlightsOk = r.ok;
      highlightsChanged = r.changed;
    } else {
      highlightsOk = await StoreHighlights.refresh(storeId);
      highlightsChanged = highlightsOk;
    }
    if (highlightsChanged) await storeChanged(storeId);
    await CatalogService.bump();

    if (menu.settled) {
      await CatalogPending.clear(
        storeId,
        ids == null ? {CatalogPending.all} : ids,
      );
    }
    return highlightsOk;
  }

  /// كمّل أي مزامنة اتقطعت (التطبيق اتقفل أو النت قطع) — من صفحة صاحب المحل/المدير.
  static Future<void> resumePending([String? onlyStoreId]) async {
    final pending = await CatalogPending.load();
    for (final e in pending.entries) {
      if (onlyStoreId != null && e.key != onlyStoreId) continue;
      await afterProductsChanged(e.key, productIds: CatalogPending.idsFor(e.value));
    }
  }

  /// إعادة بناء قائمة محل كاملة (التفعيل/الاعتماد/الترحيل). بيرجع true لو القائمة شغالة بعدها.
  static Future<bool> rebuildStoreMenu(
    String storeId, {
    bool updateHighlights = true,
    bool syncStore = true,
  }) async {
    if (storeId.isEmpty) return false;
    final menu = await menuSync.sync(storeId);
    var highlightsChanged = false;
    final items = menu.items;
    if (items != null && updateHighlights) {
      highlightsChanged = (await _writeHighlights(storeId, items.values)).changed;
    }
    if (syncStore || highlightsChanged) await storeChanged(storeId);
    return menu.status == MenuSyncStatus.updated;
  }

  /// ok: الملخص على مستند المحل صحيح (اتكتب أو كان مطابق). changed: اتكتب فعلًا.
  static Future<({bool ok, bool changed})> _writeHighlights(
    String storeId,
    Iterable<Map<String, dynamic>> products,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final h = highlightsFrom(products);
        final snap = await CatalogPaths.store(storeId)
            .get(const GetOptions(source: Source.server));
        final data = snap.data();
        if (data == null) return (ok: false, changed: false);
        if (data['offerItems'].toString() == h.offers.toString() &&
            data['bestItems'].toString() == h.best.toString()) {
          return (ok: true, changed: false);
        }
        await CatalogPaths.store(storeId).update({
          'offerItems': h.offers,
          'bestItems': h.best,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return (ok: true, changed: true);
      } catch (e) {
        debugPrint('Highlights sync failed for $storeId: $e');
      }
    }
    return (ok: false, changed: false);
  }

  // ───────────────────────── الفهرس ─────────────────────────

  static final Set<String> _ratingRefreshing = {};

  /// صاحب المحل: لو تقييم المحل اتغير من آخر مزامنة على الجهاز ده، نحدّث خانته في الفهرس.
  static Future<void> refreshIfRatingChanged(
    String storeId,
    Map<String, dynamic> store,
  ) async {
    if (storeId.isEmpty || store['active'] != true) return;
    if (!_ratingRefreshing.add(storeId)) return;
    try {
      final signature =
          '${store['rating']}|${store['ratingSum']}|${store['ratingCount']}';
      final prefs = await SharedPreferences.getInstance();
      final key = 'catalog_index_rating_$storeId';
      if (prefs.getString(key) == signature) return;
      await storeChanged(storeId);
      await prefs.setString(key, signature);
    } catch (e) {
      debugPrint('Rating index refresh skipped for $storeId: $e');
    } finally {
      _ratingRefreshing.remove(storeId);
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

  /// معاملة بتقرا مستند المحل: لو اتعدّل من جهاز تاني قبل الحفظ، بتتعاد بالبيانات الجديدة.
  static Future<void> _writeStoreEntry(String storeId) async {
    final existed = await _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(CatalogPaths.store(storeId));
      final data = snap.data();
      final key = FieldPath(['s_$storeId']);
      Object entry;
      if (snap.exists && data != null && data['active'] == true) {
        final e = indexEntry(data);
        if (indexEntryTooBig(e)) {
          throw StateError('index entry for $storeId is too large');
        }
        entry = e;
      } else {
        entry = FieldValue.delete();
      }
      tx.set(
        CatalogPaths.storeIndex,
        {'s_$storeId': entry, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(mergeFields: [key, FieldPath(const ['updatedAt'])]),
      );
      tx.set(
        CatalogPaths.versions,
        {'stores': FieldValue.increment(1), 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      return snap.exists;
    });
    if (!existed) {
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
    final entries = <String, Map<String, dynamic>>{};
    for (final doc in fresh.docs) {
      final data = doc.data();
      if (data['active'] == true) entries['s_${doc.id}'] = indexEntry(data);
    }
    final problem = indexProblem(entries);
    var indexOk = problem == null;
    if (indexOk) {
      try {
        final batch = _db.batch()
          ..set(CatalogPaths.storeIndex, {
            ...entries,
            'updatedAt': FieldValue.serverTimestamp(),
          })
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
      }
    }
    if (!indexOk) {
      try {
        // ما نرجّعش رقم الفهرس لورا (العملاء بيستخدموا الكاش لما الرقم يطابق)؛ نوقف الفهرس بس.
        await CatalogPaths.versions.set({
          'indexReady': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
    CatalogReader.invalidate();
    final indexText = indexOk
        ? 'تم (${entries.length} محل نشط، ${estimateBytes(entries) ~/ 1024}KB)'
        : 'ما اتبناش (التطبيق هيستخدم الطريقة القديمة)${problem == null ? '' : ': $problem'}';
    return 'الفهرس: $indexText'
        ' — القوائم: $menusOk تمام${menusFailed > 0 ? '، $menusFailed على الطريقة القديمة (كبيرة أو فشلت)' : ''}';
  }
}
