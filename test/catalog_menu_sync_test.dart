import 'package:city_store/services/catalog_menu_sync.dart';
import 'package:city_store/services/catalog_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// بديل وهمي لـ Firestore: معاملات متفائلة (لو مستند اتقرا جوه المعاملة اتغير قبل الحفظ
/// بتتعاد)، ونفس قاعدة أرقام إصدار القائمة اللي في firestore.rules (|السابق|+1 أو -السابق).
class FakeBackend implements CatalogBackend {
  final Map<String, Map<String, dynamic>> docs = {};
  final Map<String, int> _rev = {};

  /// بيتنفذ مرة واحدة قبل أول حفظ لمعاملة (لمحاكاة جهاز تاني في نفس اللحظة).
  Future<void> Function()? beforeCommit;

  /// كل الكتابات بتفشل (نت قاطع / رفض).
  bool failWrites = false;

  /// عدد المعاملات اللي حفظها هيفشل (والكتابات العادية زي التعطيل بتنجح).
  int failTransactionCommits = 0;

  int transactions = 0;
  int commits = 0;

  void put(String path, Map<String, dynamic> data) {
    docs[path] = _copy(data);
    _rev[path] = (_rev[path] ?? 0) + 1;
  }

  void remove(String path) {
    docs.remove(path);
    _rev[path] = (_rev[path] ?? 0) + 1;
  }

  Map<String, dynamic>? doc(String path) => docs[path];

  static Map<String, dynamic> _copy(Map m) => {
        for (final e in m.entries)
          e.key as String: e.value is Map ? _copy(e.value as Map) : e.value,
      };

  @override
  Future<Map<String, dynamic>?> get(String path) async {
    final d = docs[path];
    return d == null ? null : _copy(d);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> allProducts(String storeId) async => {
        for (final e in docs.entries)
          if (e.key.startsWith('stores/$storeId/products/'))
            e.key.split('/').last: _copy(e.value),
      };

  @override
  Future<void> set(String path, Map<String, Object?> data, {bool merge = false}) async {
    if (failWrites) throw StateError('offline');
    _apply([_Write(path, data, null, merge)]);
  }

  @override
  Future<T> runTransaction<T>(Future<T> Function(CatalogTx tx) body) async {
    transactions++;
    for (var attempt = 0; attempt < 5; attempt++) {
      final tx = _Tx(this);
      final result = await body(tx);
      final hook = beforeCommit;
      if (hook != null) {
        beforeCommit = null;
        await hook();
      }
      if (failWrites) throw StateError('offline');
      if (failTransactionCommits > 0) {
        failTransactionCommits--;
        throw StateError('unavailable');
      }
      final stale = tx.reads.entries.any((e) => (_rev[e.key] ?? 0) != e.value);
      if (stale) continue;
      _apply(tx.writes);
      commits++;
      return result;
    }
    throw StateError('transaction contention');
  }

  void _apply(List<_Write> writes) {
    final next = {for (final e in docs.entries) e.key: _copy(e.value)};
    for (final w in writes) {
      final before = next[w.path];
      Map<String, dynamic> out;
      if (w.mergeFields != null) {
        out = before == null ? {} : _copy(before);
        for (final f in w.mergeFields!) {
          _setPath(out, f, _getPath(w.data, f), _getPath(before ?? {}, f));
        }
      } else if (w.merge) {
        out = before == null ? {} : _copy(before);
        for (final e in w.data.entries) {
          _setPath(out, [e.key], e.value, out[e.key]);
        }
      } else {
        out = {};
        for (final e in w.data.entries) {
          _setPath(out, [e.key], e.value, null);
        }
      }
      if (w.path == CatalogDocPaths.versions) _checkVersionRule(before ?? {}, out);
      next[w.path] = out;
    }
    for (final w in writes) {
      docs[w.path] = next[w.path]!;
      _rev[w.path] = (_rev[w.path] ?? 0) + 1;
    }
  }

  /// نفس catalogVersionsWriteOk: m_<id> الجديد = |السابق|+1 أو -السابق (لو السابق موجب).
  static void _checkVersionRule(Map<String, dynamic> before, Map<String, dynamic> after) {
    for (final k in after.keys.where((k) => k.startsWith('m_'))) {
      final prev = (before[k] as num?)?.toInt() ?? 0;
      final now = (after[k] as num?)?.toInt();
      if (now == prev) continue;
      final ok = now == prev.abs() + 1 || (prev > 0 && now == -prev);
      if (!ok) throw StateError('permission-denied: $k $prev -> $now');
    }
  }

  static Object? _getPath(Map m, List<String> path) {
    Object? cur = m;
    for (final p in path) {
      if (cur is! Map || !cur.containsKey(p)) return null;
      cur = cur[p];
    }
    return cur;
  }

  static void _setPath(Map<String, dynamic> m, List<String> path, Object? value, Object? prev) {
    var cur = m;
    for (final p in path.take(path.length - 1)) {
      final child = cur[p];
      if (child is Map<String, dynamic>) {
        cur = child;
      } else {
        cur = cur[p] = <String, dynamic>{};
      }
    }
    final last = path.last;
    if (value is CatalogDel) {
      cur.remove(last);
    } else if (value is CatalogInc) {
      cur[last] = ((prev as num?) ?? 0) + value.by;
    } else if (value is CatalogNow) {
      cur[last] = 'now';
    } else if (value is Map) {
      cur[last] = {
        for (final e in value.entries)
          if (e.value is! CatalogDel) e.key as String: e.value is Map ? _copy(e.value as Map) : e.value,
      };
    } else {
      cur[last] = value;
    }
  }
}

class _Write {
  _Write(this.path, this.data, this.mergeFields, this.merge);
  final String path;
  final Map<String, Object?> data;
  final List<List<String>>? mergeFields;
  final bool merge;
}

class _Tx implements CatalogTx {
  _Tx(this._b);
  final FakeBackend _b;
  final Map<String, int> reads = {};
  final List<_Write> writes = [];

  @override
  Future<Map<String, dynamic>?> get(String path) async {
    reads[path] = _b._rev[path] ?? 0;
    return _b.get(path);
  }

  @override
  void set(String path, Map<String, Object?> data,
      {List<List<String>>? mergeFields, bool merge = false}) {
    writes.add(_Write(path, data, mergeFields, merge));
  }
}

const sid = 'shop1';
String p(String id) => CatalogDocPaths.product(sid, id);
int? version(FakeBackend b) => (b.doc(CatalogDocPaths.versions)?['m_$sid'] as num?)?.toInt();
Map<String, dynamic> menuItems(FakeBackend b) =>
    Map<String, dynamic>.from(b.doc(CatalogDocPaths.menu(sid))?['items'] as Map? ?? {});

Future<FakeBackend> seeded() async {
  final b = FakeBackend();
  b.put(p('a'), {'name': 'عصير', 'price': 10});
  b.put(p('b'), {'name': 'بيتزا', 'price': 80});
  final r = await MenuSync(b).sync(sid);
  expect(r.status, MenuSyncStatus.updated);
  return b;
}

void main() {
  group('MenuSync: التحديث العادي', () {
    test('أول مرة: إعادة بناء كاملة وإصدار 1', () async {
      final b = await seeded();
      expect(version(b), 1);
      expect(menuItems(b).keys.toSet(), {'a', 'b'});
      expect(b.doc(CatalogDocPaths.menu(sid))?['count'], 2);
    });

    test('تعديل سعر صنفين: تحديث موجّه للصنفين بس والإصدار +1', () async {
      final b = await seeded();
      b.put(p('a'), {'name': 'عصير', 'price': 12});
      b.put(p('b'), {'name': 'بيتزا', 'price': 75});
      final r = await MenuSync(b).sync(sid, productIds: ['a', 'b']);
      expect(r.status, MenuSyncStatus.updated);
      expect(version(b), 2);
      expect((menuItems(b)['a'] as Map)['price'], 12);
      expect((menuItems(b)['b'] as Map)['price'], 75);
      expect(r.items!.length, 2);
    });

    test('إضافة 10 أصناف وحذف 5', () async {
      final b = await seeded();
      final added = [for (var i = 0; i < 10; i++) 'n$i'];
      for (final id in added) {
        b.put(p(id), {'name': id, 'price': 5});
      }
      await MenuSync(b).sync(sid, productIds: added);
      expect(menuItems(b).length, 12);
      final removed = added.take(5).toList();
      for (final id in removed) {
        b.remove(p(id));
      }
      final r = await MenuSync(b).sync(sid, productIds: removed);
      expect(r.status, MenuSyncStatus.updated);
      expect(menuItems(b).length, 7);
      expect(menuItems(b).keys.toSet().intersection(removed.toSet()), isEmpty);
      expect(b.doc(CatalogDocPaths.menu(sid))?['count'], 7);
    });

    test('أكتر من 25 صنف مرة واحدة = إعادة بناء كاملة', () async {
      final b = await seeded();
      final ids = [for (var i = 0; i < 30; i++) 'x$i'];
      for (final id in ids) {
        b.put(p(id), {'name': id, 'price': 1});
      }
      final r = await MenuSync(b).sync(sid, productIds: ids);
      expect(r.status, MenuSyncStatus.updated);
      expect(menuItems(b).length, 32);
      expect(version(b), 2);
    });

    test('القائمة ناقصة رغم إن الإصدار موجب: بتتبني من الأول', () async {
      final b = await seeded();
      b.remove(CatalogDocPaths.menu(sid));
      final r = await MenuSync(b).sync(sid, productIds: ['a']);
      expect(r.status, MenuSyncStatus.updated);
      expect(menuItems(b).keys.toSet(), {'a', 'b'});
      expect(version(b), 2);
    });
  });

  group('MenuSync: الفشل وإعادة المحاولة', () {
    test('فشل الحفظ: القائمة بتتعطل على الخادم (رقم سالب)', () async {
      final b = await seeded();
      b.put(p('a'), {'name': 'عصير', 'price': 99});
      // حفظ القائمة يفشل، لكن التعطيل ينجح: العملاء ما يشوفوش السعر القديم من القائمة.
      b.failTransactionCommits = 1;
      final r = await MenuSync(b).sync(sid, productIds: ['a']);
      expect(r.status, MenuSyncStatus.disabled);
      expect(r.settled, isTrue);
      expect(version(b), -1);
      expect((menuItems(b)['a'] as Map)['price'], 10); // القائمة القديمة موجودة بس معطلة
    });

    test('فشل الحفظ والتعطيل معًا: status=failed والعلامة المعلقة لازم تفضل', () async {
      final b = await seeded();
      b.failWrites = true;
      final r = await MenuSync(b).sync(sid, productIds: ['a']);
      expect(r.status, MenuSyncStatus.failed);
      expect(r.settled, isFalse);
      expect(version(b), 1); // ما اتغيرش: لسه محتاج مزامنة
    });

    test('بعد التعطيل: العملاء على المسار القديم حتى بعد إعادة الفتح، وأول تعديل يرجّعها برقم جديد', () async {
      final b = await seeded();
      expect(await MenuSync(b).disable(sid, tooBig: false), isTrue);
      expect(version(b), -1);
      // "إعادة فتح التطبيق": القرار مبني على مستند الإصدارات على الخادم، مش ذاكرة الجلسة.
      expect(CatalogReader.menuUsable(current: version(b)), isFalse);
      final r = await MenuSync(b).sync(sid, productIds: ['a']);
      expect(r.status, MenuSyncStatus.updated);
      expect(version(b), 2); // |−1|+1، مش 1 تاني
      expect(CatalogReader.menuUsable(current: version(b)), isTrue);
    });

    test('قائمة أكبر من الحد: big_ + تعطيل، والمحل على المسار القديم من غير إعادة بناء مع كل تعديل', () async {
      final b = await seeded();
      for (var i = 0; i < 400; i++) {
        b.put(p('big$i'), {'name': 'ص' * 600, 'description': 'و' * 600, 'price': 1});
      }
      final r = await MenuSync(b).sync(sid);
      expect(r.status, MenuSyncStatus.big);
      expect(b.doc(CatalogDocPaths.versions)?['big_$sid'], isTrue);
      expect(version(b), -1);
      final again = await MenuSync(b).sync(sid, productIds: ['a']);
      expect(again.status, MenuSyncStatus.big);
      // أول بناء + معاملة التعطيل؛ والتعديل التالي من غير أي معاملة.
      expect(b.transactions, 2);
    });
  });

  group('MenuSync: التعديل المتزامن من جهازين', () {
    test('جهازين عدّلوا نفس الصنف: الأحدث هو اللي يفضل (المعاملة بتتعاد)', () async {
      final b = await seeded();
      b.put(p('a'), {'name': 'عصير', 'price': 11}); // تعديل الجهاز A
      b.beforeCommit = () async {
        // الجهاز B عدّل نفس الصنف وحفظ قائمته قبل ما A يحفظ.
        b.put(p('a'), {'name': 'عصير', 'price': 13});
        await MenuSync(b).sync(sid, productIds: ['a']);
      };
      await MenuSync(b).sync(sid, productIds: ['a']);
      expect((menuItems(b)['a'] as Map)['price'], 13);
      expect(version(b), 3);
    });

    test('إعادة بناء أثناء تعديل موجّه من جهاز تاني: البناء بيعيد القراءة وما يكتبش نسخة قديمة', () async {
      final b = await seeded();
      b.beforeCommit = () async {
        b.put(p('b'), {'name': 'بيتزا', 'price': 60});
        await MenuSync(b).sync(sid, productIds: ['b']);
      };
      final r = await MenuSync(b).sync(sid);
      expect(r.status, MenuSyncStatus.updated);
      expect((menuItems(b)['b'] as Map)['price'], 60);
      expect(version(b), 3);
    });

    test('القائمة اتعطلت من جهاز تاني وقت التعديل: المعاملة بتتعاد وتبني من الأول برقم جديد', () async {
      final b = await seeded();
      b.put(p('a'), {'name': 'عصير', 'price': 20});
      b.beforeCommit = () => MenuSync(b).disable(sid, tooBig: false).then((_) {});
      final r = await MenuSync(b).sync(sid, productIds: ['a']);
      expect(r.status, MenuSyncStatus.updated);
      // 1 → -1 (تعطيل) → 2: ولا رقم اتكرر.
      expect(version(b), 2);
      expect((menuItems(b)['a'] as Map)['price'], 20);
    });

    test('أرقام الإصدار ما تتكررش حتى لو الكاتب بيعدّي القواعد (زي المدير)', () async {
      final b = await seeded();
      final seen = <int>{version(b)!};
      for (var i = 0; i < 3; i++) {
        await MenuSync(b).disable(sid, tooBig: false);
        seen.add(version(b)!.abs());
        await MenuSync(b).sync(sid, productIds: ['a']);
        expect(seen.contains(version(b)), isFalse);
        seen.add(version(b)!);
      }
    });
  });

  group('CatalogPending (ضمان بعد إعادة الفتح)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('العلامة بتفضل لحد ما المزامنة تنجح، وبتتشال بعدها', () async {
      final b = await seeded();
      await CatalogPending.mark(sid, ['a']);
      b.put(p('a'), {'name': 'عصير', 'price': 15});
      b.failWrites = true;
      final failed = await MenuSync(b).sync(sid, productIds: ['a']);
      if (failed.settled) await CatalogPending.clear(sid, {'a'});
      expect((await CatalogPending.load())[sid], {'a'});

      // "إعادة فتح التطبيق" والنت رجع: نكمّل من العلامة.
      b.failWrites = false;
      final pending = await CatalogPending.load();
      final ids = CatalogPending.idsFor(pending[sid]!);
      final ok = await MenuSync(b).sync(sid, productIds: ids);
      expect(ok.status, MenuSyncStatus.updated);
      if (ok.settled) await CatalogPending.clear(sid, pending[sid]!);
      expect(await CatalogPending.load(), isEmpty);
      expect((menuItems(b)['a'] as Map)['price'], 15);
    });

    test('دمج العلامات: أصناف كتير أو رفع جماعي = إعادة بناء كاملة', () {
      var m = CatalogPending.merge({}, sid, ['a', 'b']);
      expect(m[sid], {'a', 'b'});
      m = CatalogPending.merge(m, sid, null);
      expect(m[sid], {CatalogPending.all});
      expect(CatalogPending.idsFor(m[sid]!), isNull);
      final many = CatalogPending.merge({}, sid, [for (var i = 0; i < 30; i++) 'x$i']);
      expect(many[sid], {CatalogPending.all});
      expect(CatalogPending.decode(CatalogPending.encode(m)), m);
    });

    test('علامة الفهرس بتفضل مع الأصناف، ومش بتتحسب صنف', () async {
      await CatalogPending.mark(sid, ['a']);
      await CatalogPending.markIndex(sid);
      await CatalogPending.mark(sid);
      final pending = (await CatalogPending.load())[sid]!;
      expect(pending, {CatalogPending.all, CatalogPending.index});
      expect(CatalogPending.idsFor(pending), isNull);
      expect(CatalogPending.idsFor({'a', CatalogPending.index}), {'a'});
      await CatalogPending.clear(sid, {CatalogPending.index});
      expect((await CatalogPending.load())[sid], {CatalogPending.all});
    });

    test('إعادة بناء كاملة ناجحة ما بتمسحش علامة فهرس لسه ما اتحدثش', () async {
      await CatalogPending.mark(sid, ['a']);
      await CatalogPending.markIndex(sid);
      await CatalogPending.clear(sid, {CatalogPending.all});
      expect((await CatalogPending.load())[sid], {CatalogPending.index});
      await CatalogPending.clear(sid, {CatalogPending.index});
      expect(await CatalogPending.load(), isEmpty);
    });

    test('تعديل جديد أثناء المزامنة ما يتمسحش مع العلامة القديمة', () async {
      await CatalogPending.mark(sid, ['a']);
      await CatalogPending.mark(sid, ['b']);
      await CatalogPending.clear(sid, {'a'});
      expect((await CatalogPending.load())[sid], {'b'});
    });
  });

  group('CatalogReader: رفض القائمة بعد سعر غلط', () {
    test('الرفض مربوط برقم الإصدار: بيفضل بعد إعادة الفتح ويتلغي مع إصدار جديد', () {
      expect(CatalogReader.menuUsable(current: 4, distrustedAt: 4), isFalse);
      expect(CatalogReader.menuUsable(current: 5, distrustedAt: 4), isTrue);
      expect(CatalogReader.menuUsable(current: 5), isTrue);
      expect(CatalogReader.menuUsable(current: -5), isFalse);
      expect(CatalogReader.menuUsable(current: null), isFalse);
    });
  });
}
