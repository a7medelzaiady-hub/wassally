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
        final store = CatalogSync.decodeIndexEntry(Map<String, dynamic>.from(value));
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

  /// عروض الفهرس لكل محل (الرئيسية بتعرض صف واحد من كل المحلات، فكام عنصر من كل محل كفاية).
  /// القائمة الكاملة (12) فاضلة على مستند المحل.
  static const int indexOffersCap = 4;
  static const int indexBestCap = 3;

  /// حدود الفهرس (لازم تطابق storeIndexWriteOk في القواعد):
  ///  • العروض في الخانة نص واحد مضغوط "hl" طوله ≤ [maxHighlightsChars] (القواعد بتتحقق منه
  ///    بتعبيرين بس، بدل فحص كل عنصر اللي كان بيعدّي حد الـ 1000 تعبير لكل طلب).
  ///  • خانة المحل ≤ [maxIndexEntryBytes] في التطبيق، و250 محل بالكتير.
  static const int maxHighlightsChars = 1400;
  static const int maxIndexEntryBytes = 3500;
  static const int maxIndexStores = 250;
  static const int maxIndexBytes = 900 * 1024;

  /// الحقول اللي الشاشات بتستخدمها من مستند المحل. لازم تطابق القواعد (indexEntryMatchesStore).
  static const List<String> indexKeys = [
    'name', 'category', 'icon', 'color', 'imageUrl', 'storePhone',
    'rating', 'ratingSum', 'ratingCount', 'time', 'active', 'order',
    'products', 'minOrder', 'minimumOrder', 'hl',
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

  static Map<String, dynamic>? _packItem(Object? value) {
    if (value is! Map) return null;
    final end = value['offerEndsAt'];
    final text = (value['offerText'] ?? '').toString();
    return {
      'n': (value['name'] ?? '').toString(),
      'p': value['price'] is num ? value['price'] : 0,
      if (value['oldPrice'] is num) 'op': value['oldPrice'],
      if (text.isNotEmpty) 't': text,
      if (end is Timestamp) 'e': end.millisecondsSinceEpoch,
      'i': (value['image'] ?? '').toString(),
    };
  }

  static Map<String, dynamic> _unpackItem(Map m) => {
        'name': (m['n'] ?? '').toString(),
        'price': m['p'] is num ? m['p'] : 0,
        if (m['op'] is num) 'oldPrice': m['op'],
        if ((m['t'] ?? '').toString().isNotEmpty) 'offerText': m['t'].toString(),
        if (m['e'] is int) 'offerEndsAt': Timestamp.fromMillisecondsSinceEpoch(m['e'] as int),
        'image': (m['i'] ?? '').toString(),
      };

  static List<Map<String, dynamic>> _packList(Object? raw, int cap) {
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final v in raw) {
      final item = _packItem(v);
      if (item != null) out.add(item);
      if (out.length >= cap) break;
    }
    return out;
  }

  /// العروض والأكثر مبيعًا من النص المضغوط "hl" بنفس شكل مستند المحل (offerItems/bestItems)،
  /// عشان الشاشات تقرا من الفهرس أو من مستند المحل بنفس الكود.
  static Map<String, dynamic> decodeIndexEntry(Map<String, dynamic> entry) {
    final out = Map<String, dynamic>.from(entry)..remove('hl');
    final raw = entry['hl'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final hl = jsonDecode(raw);
        if (hl is Map) {
          out['offerItems'] = [
            for (final m in (hl['o'] as List? ?? const [])) if (m is Map) _unpackItem(m),
          ];
          out['bestItems'] = [
            for (final m in (hl['b'] as List? ?? const [])) if (m is Map) _unpackItem(m),
          ];
        }
      } catch (_) {}
    }
    return out;
  }

  /// خانة المحل في الفهرس: الحقول المعروفة بس (القواعد بتطابقها مع مستند المحل)، والصورة
  /// في imageUrl بس، والعروض في "hl" مقصوصة لحد ما تدخل تحت الحدود (الأكثر مبيعًا الأول).
  @visibleForTesting
  static Map<String, dynamic> indexEntry(Map<String, dynamic> store) {
    final entry = <String, dynamic>{};
    for (final k in indexKeys) {
      if (k == 'imageUrl' || k == 'hl') continue;
      if (store.containsKey(k)) entry[k] = store[k];
    }
    final image = store.containsKey('imageUrl') ? store['imageUrl'] : store['image'];
    if (image != null) entry['imageUrl'] = image;
    final hasHighlights =
        store.containsKey('offerItems') || store.containsKey('bestItems');
    if (!hasHighlights) return entry;
    final offers = _packList(store['offerItems'], indexOffersCap);
    final best = _packList(store['bestItems'], indexBestCap);
    String pack() => jsonEncode({'o': offers, 'b': best});
    var hl = pack();
    entry['hl'] = hl;
    while (hl.length > maxHighlightsChars || estimateBytes(entry) > maxIndexEntryBytes) {
      if (best.isNotEmpty) {
        best.removeLast();
      } else if (offers.isNotEmpty) {
        offers.removeLast();
      } else {
        break;
      }
      hl = pack();
      entry['hl'] = hl;
    }
    return entry;
  }

  /// نص ثابت للمقارنة: مفاتيح الخرائط مرتبة (Firestore ما بيحافظش على ترتيب المفاتيح
  /// لما يرجّع البيانات)، والأوقات بالمللي ثانية، والأرقام بنفس الصيغة (5 و5.0 واحد).
  @visibleForTesting
  static String canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return '{${keys.map((k) => '$k:${canonical(v[k])}').join(',')}}';
    }
    if (v is List) return '[${v.map(canonical).join(',')}]';
    if (v is Timestamp) return 't${v.millisecondsSinceEpoch}';
    if (v is num) return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    if (v == null) return 'null';
    return jsonEncode(v.toString());
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

  /// خانة المحل في الفهرس ما اتحدثتش (هتتكمل مع resumePending).
  static Future<void> markIndexPending(String storeId) => CatalogPending.markIndex(storeId);

  /// بعد أي إضافة/تعديل/حذف أصناف. الترتيب:
  ///  1) القائمة المجمّعة (معاملة؛ فشلها = تعطيل على الخادم)،
  ///  2) ملخص العروض على مستند المحل (من القائمة نفسها من غير قراءات، أو من الخادم لو القائمة مش شغالة)،
  ///  3) خانة المحل في الفهرس لو الملخص اتغير،
  ///  4) رقم إصدار الكتالوج القديم (للمسار القديم) في الآخر،
  /// عشان العميل اللي يشوف أي رقم جديد ياخد بيانات جديدة.
  /// [productIds] = null → إعادة بناء كاملة (CSV/ترحيل).
  /// بيرجع true لو كله اتحدث. false = حاجة ما اكتملتش (القائمة اتعطلت أو فشلت، أو الملخص،
  /// أو الفهرس): العلامة المعلقة بتفضل والمزامنة بتتكمل أول ما صفحة الأصناف تتفتح،
  /// والمحرر لازم يشوف تنبيه (StoreHighlights.withNote).
  static Future<bool> afterProductsChanged(
    String storeId, {
    Iterable<String>? productIds,
  }) async {
    if (storeId.isEmpty) return false;
    final ids = productIds?.where((id) => id.isNotEmpty).toSet();
    final menu = await menuSync.sync(storeId, productIds: ids);

    var highlightsOk = false;
    var highlightsChanged = false;
    var storeActive = true;
    final items = menu.items;
    if (items != null) {
      final r = await _writeHighlights(storeId, items.values);
      highlightsOk = r.ok;
      highlightsChanged = r.changed;
      storeActive = r.active;
    } else {
      highlightsOk = await StoreHighlights.refresh(storeId);
      highlightsChanged = highlightsOk;
    }
    var indexOk = true;
    // محل مقفول أو مسودة مش في الفهرس أصلًا: ما نلمسش الفهرس (وإلا كل العملاء يعيدوا تحميله).
    if (highlightsChanged && storeActive) indexOk = await storeChanged(storeId);
    await CatalogService.bump();

    final menuOk = menu.status == MenuSyncStatus.updated ||
        menu.status == MenuSyncStatus.big;
    final allOk = menuOk && highlightsOk && indexOk;
    if (allOk) {
      await CatalogPending.clear(
        storeId,
        ids == null ? {CatalogPending.all} : ids,
      );
    } else if (!indexOk) {
      // الفهرس بس اللي فشل: نعلّم إن خانة المحل محتاجة تتحدث.
      await CatalogPending.markIndex(storeId);
    }
    return allOk;
  }

  /// كمّل أي مزامنة اتقطعت (التطبيق اتقفل أو النت قطع) — من صفحة صاحب المحل/المدير.
  static Future<void> resumePending([String? onlyStoreId]) async {
    final pending = await CatalogPending.load();
    for (final e in pending.entries) {
      if (onlyStoreId != null && e.key != onlyStoreId) continue;
      final products = e.value.difference({CatalogPending.index});
      if (products.isNotEmpty) {
        await afterProductsChanged(e.key, productIds: CatalogPending.idsFor(products));
      }
      if (e.value.contains(CatalogPending.index) && await storeChanged(e.key)) {
        await CatalogPending.clear(e.key, {CatalogPending.index});
      }
    }
  }

  /// إعادة بناء قائمة محل كاملة (التفعيل/الاعتماد/الترحيل). بيرجع true لو القائمة شغالة بعدها.
  static Future<bool> rebuildStoreMenu(
    String storeId, {
    bool updateHighlights = true,
    bool syncStore = true,
    bool adding = false,
  }) async {
    if (storeId.isEmpty) return false;
    final menu = await menuSync.sync(storeId);
    var highlightsChanged = false;
    final items = menu.items;
    if (items != null && updateHighlights) {
      highlightsChanged = (await _writeHighlights(storeId, items.values)).changed;
    }
    if (syncStore || highlightsChanged) await storeChanged(storeId, adding: adding);
    return menu.status == MenuSyncStatus.updated;
  }

  /// ok: الملخص على مستند المحل صحيح (اتكتب أو كان مطابق). changed: اتكتب فعلًا.
  /// active: المحل نشط (يعني له خانة في الفهرس).
  static Future<({bool ok, bool changed, bool active})> _writeHighlights(
    String storeId,
    Iterable<Map<String, dynamic>> products,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final h = highlightsFrom(products);
        final snap = await CatalogPaths.store(storeId)
            .get(const GetOptions(source: Source.server));
        final data = snap.data();
        if (data == null) return (ok: false, changed: false, active: false);
        final active = data['active'] == true;
        if (canonical(data['offerItems']) == canonical(h.offers) &&
            canonical(data['bestItems']) == canonical(h.best)) {
          return (ok: true, changed: false, active: active);
        }
        await CatalogPaths.store(storeId).update({
          'offerItems': h.offers,
          'bestItems': h.best,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return (ok: true, changed: true, active: active);
      } catch (e) {
        debugPrint('Highlights sync failed for $storeId: $e');
      }
    }
    return (ok: false, changed: false, active: true);
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
      // بنحفظ التوقيع بس لو التحديث نجح، عشان يتعاد المرة الجاية لو فشل.
      if (await storeChanged(storeId)) await prefs.setString(key, signature);
    } catch (e) {
      debugPrint('Rating index refresh skipped for $storeId: $e');
    } finally {
      _ratingRefreshing.remove(storeId);
    }
  }

  /// تحديث خانة المحل في الفهرس من مستند المحل الحالي (أو شيلها لو المحل مش نشط/اتحذف).
  /// محاولة تانية عند الفشل؛ ولو فشلت كمان والمستخدم مدير، بنوقف الفهرس (المسار القديم)
  /// بدل ما العملاء يفضلوا على فهرس قديم. (صاحب المحل ما يقدرش يوقفه للكل.)
  /// [adding]: المحل بيتفعّل/بيتضاف (المدير بيعدّي القواعد، فبنتأكد إن الفهرس فيه مكان).
  /// بيرجع true لو الخانة اتكتبت.
  static Future<bool> storeChanged(String storeId, {bool adding = false}) async {
    if (storeId.isEmpty) return false;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        // الفهرس مليان: ما بنكتبش وما بنوقفش الفهرس للكل (المتصل بيبلّغ المدير).
        if (!await _writeStoreEntry(storeId, adding: adding)) return false;
        CatalogReader.invalidate();
        return true;
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
    return false;
  }

  /// المدير قبل تفعيل محل: هل الفهرس فيه مكان؟ (قراءة واحدة لمستند الفهرس.)
  static Future<bool> indexHasRoom(String storeId) async {
    try {
      final snap = await CatalogPaths.storeIndex
          .get(const GetOptions(source: Source.server));
      return indexRoomFor(snap.data(), storeId);
    } catch (_) {
      return true; // الفهرس مش موجود/مش متاح: التفعيل ما يتمنعش (العملاء على المسار القديم).
    }
  }

  @visibleForTesting
  static bool indexRoomFor(Map<String, dynamic>? index, String storeId) {
    if (index == null) return true;
    if (index.containsKey('s_$storeId')) return true;
    final count = index.keys.where((k) => k.startsWith('s_')).length;
    return count < maxIndexStores;
  }

  /// معاملة بتقرا مستند المحل: لو اتعدّل من جهاز تاني قبل الحفظ، بتتعاد بالبيانات الجديدة.
  /// بيرجع false لو الفهرس مليان (من غير كتابة). أي فشل تاني بيرمي استثناء.
  static Future<bool> _writeStoreEntry(String storeId, {bool adding = false}) async {
    final result = await _db.runTransaction<({bool existed, bool full})>((tx) async {
      final snap = await tx.get(CatalogPaths.store(storeId));
      final data = snap.data();
      if (adding && data?['active'] == true) {
        final index = await tx.get(CatalogPaths.storeIndex);
        if (!indexRoomFor(index.data(), storeId)) {
          return (existed: snap.exists, full: true);
        }
      }
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
      return (existed: snap.exists, full: false);
    });
    if (result.full) return false;
    if (!result.existed) {
      // المحل اتحذف: نشيل قائمته اليتيمة (المدير بس يقدر؛ غيره بيتجاهل).
      try {
        await CatalogPaths.menu(storeId).delete();
      } catch (_) {}
    }
    return true;
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

