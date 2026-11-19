import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ───────────────────────── قيم خاصة (بدل FieldValue عشان الاختبار) ─────────────────────────

/// قيم بتتحول لـ FieldValue عند الكتابة في Firestore، ومفهومة في البديل الوهمي للاختبار.
sealed class CatalogOp {
  const CatalogOp();
}

class CatalogInc extends CatalogOp {
  const CatalogInc(this.by);
  final int by;
}

class CatalogDel extends CatalogOp {
  const CatalogDel();
}

class CatalogNow extends CatalogOp {
  const CatalogNow();
}

// ───────────────────────── واجهة التخزين ─────────────────────────

abstract class CatalogTx {
  Future<Map<String, dynamic>?> get(String path);

  /// [mergeFields]: مسارات الحقول اللي تتكتب بس (زي SetOptions.mergeFields).
  /// [merge]: دمج كل الحقول المذكورة. ولا واحد منهم = استبدال المستند.
  void set(
    String path,
    Map<String, Object?> data, {
    List<List<String>>? mergeFields,
    bool merge = false,
  });
}

abstract class CatalogBackend {
  /// معاملة: لو أي مستند اتقرا جواها اتغير قبل الحفظ، بتتعاد من الأول.
  Future<T> runTransaction<T>(Future<T> Function(CatalogTx tx) body);

  /// قراءة مستند من الخادم (برا المعاملة).
  Future<Map<String, dynamic>?> get(String path);

  /// كل أصناف المحل من الخادم.
  Future<Map<String, Map<String, dynamic>>> allProducts(String storeId);

  Future<void> set(String path, Map<String, Object?> data, {bool merge = false});
}

class CatalogDocPaths {
  const CatalogDocPaths._();
  static const versions = 'app_info/catalog_versions';
  static String menu(String storeId) => 'stores/$storeId/menu/current';
  static String product(String storeId, String id) => 'stores/$storeId/products/$id';
}

// ───────────────────────── المنطق ─────────────────────────

enum MenuSyncStatus {
  /// القائمة اتحدثت والإصدار زاد.
  updated,

  /// المحل على المسار القديم (القائمة أكبر من الحد): مفيش قائمة تتحدث.
  big,

  /// التحديث فشل، والقائمة اتعطلت على الخادم (العملاء على المسار القديم، حتى بعد إعادة الفتح).
  disabled,

  /// التحديث فشل وكمان التعطيل فشل: لازم نعيد المحاولة لاحقًا (العلامة المعلقة بتفضل).
  failed,
}

class MenuSyncResult {
  const MenuSyncResult(this.status, [this.items]);
  final MenuSyncStatus status;

  /// كل أصناف القائمة بعد التحديث (لما status == updated) لحساب ملخص العروض من غير قراءات.
  final Map<String, Map<String, dynamic>>? items;

  /// حالة الخادم متسقة (القائمة صحيحة أو معطلة أو المحل كبير) فينفع نشيل العلامة المعلقة.
  bool get settled => status != MenuSyncStatus.failed;
}

class _TooBig implements Exception {
  const _TooBig();
}

/// نتيجة جسم المعاملة الموجّهة (من غير استثناءات جوه المعاملة: بعض المنصات بتغلّفها).
enum _Targeted { done, needsRebuild, tooBig }

/// مزامنة مستند القائمة المجمّعة (stores/{id}/menu/current) مع أصناف المحل.
///
/// الضمانات:
///  • التحديث الموجّه جوه معاملة بتقرا القائمة والأصناف المتغيرة: لو جهاز تاني حدّث القائمة
///    في نفس اللحظة، المعاملة بتتعاد بالبيانات الجديدة (مفيش سعر قديم يكتب فوق الجديد).
///  • إعادة البناء بتتأكد إن إصدار القائمة ما اتغيرش بين قراءة الأصناف والحفظ، وإلا بتعيد.
///  • أي فشل → تعطيل القائمة على الخادم (رقم سالب)، فكل العملاء يرجعوا للمسار القديم
///    حتى بعد إعادة فتح التطبيق. ولو التعطيل كمان فشل → status = failed والعلامة المعلقة بتفضل.
class MenuSync {
  MenuSync(this.backend);

  final CatalogBackend backend;

  /// أكتر من كده يبقى إعادة بناء كاملة بدل تحديث صنف صنف.
  static const int targetedLimit = 25;

  /// حد آمن تحت 1MiB لمستند القائمة.
  static const int maxMenuBytes = 900 * 1024;

  static const int _rebuildAttempts = 3;

  static int estimateBytes(Map<String, Map<String, dynamic>> items) =>
      utf8.encode(items.toString()).length;

  static ({int? version, bool big}) stateOf(
    Map<String, dynamic>? versions,
    String storeId,
  ) {
    final v = versions?['m_$storeId'];
    return (
      version: v is num ? v.toInt() : null,
      big: versions?['big_$storeId'] == true,
    );
  }

  /// الإصدار الجاي (لازم يطابق القواعد): |السابق| + 1، فما يتكررش حتى بعد التعطيل.
  static int nextVersion(int? current) =>
      (current != null && current >= 1) ? current + 1 : (current ?? 0).abs() + 1;

  static Map<String, Map<String, dynamic>> itemsOf(Map<String, dynamic>? menu) {
    final out = <String, Map<String, dynamic>>{};
    final raw = menu?['items'];
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.key is String && e.value is Map) {
          out[e.key as String] = Map<String, dynamic>.from(e.value as Map);
        }
      }
    }
    return out;
  }

  /// [productIds] = null أو كتير → إعادة بناء كاملة.
  Future<MenuSyncResult> sync(String storeId, {Iterable<String>? productIds}) async {
    final ids = productIds?.where((id) => id.isNotEmpty).toSet();
    try {
      final state = stateOf(await backend.get(CatalogDocPaths.versions), storeId);
      // المحل الكبير: التعديلات العادية على المسار القديم؛ إعادة البناء الكاملة بس هي اللي
      // بتجرب تاني (لو الأصناف قلّت، بترجّع القائمة وتشيل big_).
      if (state.big && ids != null) return const MenuSyncResult(MenuSyncStatus.big);
      if (ids != null && ids.isEmpty) {
        return const MenuSyncResult(MenuSyncStatus.updated);
      }
      if (ids != null &&
          ids.length <= targetedLimit &&
          state.version != null &&
          state.version! >= 1) {
        final r = await _targeted(storeId, ids);
        if (r.status == _Targeted.tooBig) throw const _TooBig();
        if (r.status == _Targeted.done) {
          return MenuSyncResult(MenuSyncStatus.updated, r.items);
        }
        // القائمة ناقصة: نبنيها من الأول.
      }
      return await _rebuild(storeId);
    } on _TooBig {
      return _fail(storeId, tooBig: true);
    } catch (e) {
      debugPrint('Menu sync failed for $storeId: $e');
      return _fail(storeId, tooBig: false);
    }
  }

  Future<({_Targeted status, Map<String, Map<String, dynamic>>? items})> _targeted(
    String storeId,
    Set<String> ids,
  ) {
    return backend.runTransaction((tx) async {
      // الإصدار بيتقرا جوه المعاملة وبيتكتب رقم صريح (|السابق|+1): المدير بيعدّي القواعد،
      // فمن غير كده تعطيل من جهاز تاني في نفس اللحظة كان ممكن يرجّع رقم اتستخدم قبل كده.
      final current =
          stateOf(await tx.get(CatalogDocPaths.versions), storeId).version;
      if (current == null || current < 1) {
        return (status: _Targeted.needsRebuild, items: null);
      }
      final menu = await tx.get(CatalogDocPaths.menu(storeId));
      if (menu == null) return (status: _Targeted.needsRebuild, items: null);
      final items = itemsOf(menu);
      final changed = <String, Object?>{};
      final fields = <List<String>>[
        ['count'],
        ['updatedAt'],
      ];
      for (final id in ids) {
        final data = await tx.get(CatalogDocPaths.product(storeId, id));
        if (data != null) {
          items[id] = data;
          changed[id] = data;
        } else {
          items.remove(id);
          changed[id] = const CatalogDel();
        }
        fields.add(['items', id]);
      }
      if (estimateBytes(items) > maxMenuBytes) {
        return (status: _Targeted.tooBig, items: null);
      }
      tx.set(
        CatalogDocPaths.menu(storeId),
        {'items': changed, 'count': items.length, 'updatedAt': const CatalogNow()},
        mergeFields: fields,
      );
      tx.set(
        CatalogDocPaths.versions,
        {'m_$storeId': current + 1, 'updatedAt': const CatalogNow()},
        merge: true,
      );
      return (status: _Targeted.done, items: items);
    });
  }

  Future<MenuSyncResult> _rebuild(String storeId) async {
    for (var attempt = 0; attempt < _rebuildAttempts; attempt++) {
      final before =
          stateOf(await backend.get(CatalogDocPaths.versions), storeId);
      final items = await backend.allProducts(storeId);
      if (estimateBytes(items) > maxMenuBytes) throw const _TooBig();
      final written = await backend.runTransaction((tx) async {
        final now = stateOf(await tx.get(CatalogDocPaths.versions), storeId);
        // جهاز تاني حدّث القائمة بعد ما قرينا الأصناف: نعيد القراءة بدل ما نكتب نسخة قديمة.
        if (now.version != before.version) return false;
        tx.set(CatalogDocPaths.menu(storeId), {
          'items': items,
          'count': items.length,
          'updatedAt': const CatalogNow(),
        });
        tx.set(
          CatalogDocPaths.versions,
          {
            'm_$storeId': nextVersion(now.version),
            if (now.big) 'big_$storeId': false,
            'updatedAt': const CatalogNow(),
          },
          merge: true,
        );
        return true;
      });
      if (written) return MenuSyncResult(MenuSyncStatus.updated, items);
    }
    throw StateError('menu kept changing during rebuild');
  }

  Future<MenuSyncResult> _fail(String storeId, {required bool tooBig}) async {
    final ok = await disable(storeId, tooBig: tooBig);
    if (!ok) return const MenuSyncResult(MenuSyncStatus.failed);
    return MenuSyncResult(tooBig ? MenuSyncStatus.big : MenuSyncStatus.disabled);
  }

  /// تعطيل القائمة (العملاء على المسار القديم) من غير رقم اتستخدم قبل كده. معاملة، محاولتين.
  Future<bool> disable(String storeId, {required bool tooBig}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await backend.runTransaction((tx) async {
          final current =
              stateOf(await tx.get(CatalogDocPaths.versions), storeId).version;
          tx.set(
            CatalogDocPaths.versions,
            {
              if (current != null && current > 0) 'm_$storeId': -current,
              if (tooBig) 'big_$storeId': true,
              'updatedAt': const CatalogNow(),
            },
            merge: true,
          );
        });
        return true;
      } catch (e) {
        debugPrint('Could not disable menu for $storeId (try ${attempt + 1}): $e');
      }
    }
    return false;
  }
}

// ───────────────────────── العلامة المعلقة (ضمان بعد إعادة الفتح) ─────────────────────────

/// قبل أي تعديل صنف بنسجل على الجهاز إن قائمة المحل محتاجة مزامنة، وبنشيلها بس لما حالة
/// الخادم تبقى متسقة. لو التطبيق اتقفل (أو النت قطع وكتابة الصنف اتأجلت)، أول فتح لصفحة
/// المحل بيكمل المزامنة.
class CatalogPending {
  const CatalogPending._();

  static const _key = 'catalog_pending_sync';

  /// '*' = إعادة بناء كاملة.
  static const all = '*';

  /// '#i' = خانة المحل في الفهرس محتاجة تتحدث.
  static const index = '#i';

  static Map<String, Set<String>> decode(List<String>? raw) {
    final out = <String, Set<String>>{};
    for (final entry in raw ?? const <String>[]) {
      final i = entry.indexOf('|');
      if (i <= 0) continue;
      final ids = entry
          .substring(i + 1)
          .split(',')
          .where((s) => s.isNotEmpty)
          .toSet();
      if (ids.isEmpty) continue;
      (out[entry.substring(0, i)] ??= <String>{}).addAll(ids);
    }
    return out;
  }

  static List<String> encode(Map<String, Set<String>> pending) => [
        for (final e in pending.entries)
          if (e.value.isNotEmpty) '${e.key}|${e.value.join(',')}',
      ];

  static Map<String, Set<String>> merge(
    Map<String, Set<String>> pending,
    String storeId,
    Iterable<String>? productIds,
  ) {
    final out = {for (final e in pending.entries) e.key: {...e.value}};
    final ids = productIds?.where((id) => id.isNotEmpty).toSet();
    final bucket = out[storeId] ??= <String>{};
    final hadIndex = bucket.remove(index);
    if (ids == null ||
        bucket.contains(all) ||
        bucket.length + ids.length > MenuSync.targetedLimit) {
      bucket
        ..clear()
        ..add(all);
    } else {
      bucket.addAll(ids);
    }
    if (hadIndex) bucket.add(index);
    return out;
  }

  /// null = إعادة بناء كاملة.
  static Iterable<String>? idsFor(Set<String> ids) =>
      ids.contains(all) ? null : ids.difference({index});

  static Future<void> markIndex(String storeId) async {
    if (storeId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = decode(prefs.getStringList(_key));
      (pending[storeId] ??= <String>{}).add(index);
      await prefs.setStringList(_key, encode(pending));
    } catch (_) {}
  }

  static Future<void> mark(String storeId, [Iterable<String>? productIds]) async {
    if (storeId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = merge(decode(prefs.getStringList(_key)), storeId, productIds);
      await prefs.setStringList(_key, encode(next));
    } catch (_) {}
  }

  static Future<Map<String, Set<String>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decode(prefs.getStringList(_key));
    } catch (_) {
      return {};
    }
  }

  /// بنشيل بس الأصناف اللي اتزامنت (لو اتضاف غيرها أثناء المزامنة بيفضل).
  static Future<void> clear(String storeId, Set<String> synced) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = decode(prefs.getStringList(_key));
      final current = pending[storeId];
      if (current == null) return;
      if (synced.contains(all)) {
        pending.remove(storeId);
      } else {
        current.removeAll(synced);
        if (current.isEmpty) pending.remove(storeId);
      }
      await prefs.setStringList(_key, encode(pending));
    } catch (_) {}
  }
}

// ───────────────────────── Firestore ─────────────────────────

class FirestoreCatalogBackend implements CatalogBackend {
  FirestoreCatalogBackend([FirebaseFirestore? db])
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _server = GetOptions(source: Source.server);

  DocumentReference<Map<String, dynamic>> _ref(String path) => _db.doc(path);

  static Object? _convert(Object? v) {
    if (v is CatalogInc) return FieldValue.increment(v.by);
    if (v is CatalogDel) return FieldValue.delete();
    if (v is CatalogNow) return FieldValue.serverTimestamp();
    if (v is Map) {
      return {for (final e in v.entries) e.key: _convert(e.value)};
    }
    return v;
  }

  static Map<String, Object?> _data(Map<String, Object?> data) =>
      {for (final e in data.entries) e.key: _convert(e.value)};

  static SetOptions? _options(List<List<String>>? mergeFields, bool merge) {
    if (mergeFields != null) {
      return SetOptions(mergeFields: [for (final f in mergeFields) FieldPath(f)]);
    }
    return merge ? SetOptions(merge: true) : null;
  }

  @override
  Future<T> runTransaction<T>(Future<T> Function(CatalogTx tx) body) =>
      _db.runTransaction((t) => body(_FirestoreTx(t, this)));

  @override
  Future<Map<String, dynamic>?> get(String path) async {
    final snap = await _ref(path).get(_server);
    return snap.exists ? snap.data() : null;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> allProducts(String storeId) async {
    final items = <String, Map<String, dynamic>>{};
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      Query<Map<String, dynamic>> q = _db
          .collection('stores')
          .doc(storeId)
          .collection('products')
          .orderBy(FieldPath.documentId)
          .limit(400);
      if (cursor != null) q = q.startAfterDocument(cursor);
      final page = await q.get(_server);
      for (final d in page.docs) {
        items[d.id] = d.data();
      }
      if (page.docs.length < 400) break;
      cursor = page.docs.last;
    }
    return items;
  }

  @override
  Future<void> set(String path, Map<String, Object?> data, {bool merge = false}) {
    final options = _options(null, merge);
    return options == null
        ? _ref(path).set(_data(data))
        : _ref(path).set(_data(data), options);
  }
}

class _FirestoreTx implements CatalogTx {
  _FirestoreTx(this._t, this._b);

  final Transaction _t;
  final FirestoreCatalogBackend _b;

  @override
  Future<Map<String, dynamic>?> get(String path) async {
    final snap = await _t.get(_b._ref(path));
    return snap.exists ? snap.data() : null;
  }

  @override
  void set(
    String path,
    Map<String, Object?> data, {
    List<List<String>>? mergeFields,
    bool merge = false,
  }) {
    final options = FirestoreCatalogBackend._options(mergeFields, merge);
    final converted = FirestoreCatalogBackend._data(data);
    if (options == null) {
      _t.set(_b._ref(path), converted);
    } else {
      _t.set(_b._ref(path), converted, options);
    }
  }
}
