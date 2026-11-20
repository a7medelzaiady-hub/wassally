import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/services/notifications_query.dart';

Stream<int> _failing(String code) async* {
  yield 1;
  throw FirebaseException(plugin: 'cloud_firestore', code: code);
}

void main() {
  group('withIndexFallback', () {
    test('فهرس ناقص (failed-precondition): يكمل على الاستعلام البديل', () async {
      final out = await withIndexFallback<int>(
        _failing('failed-precondition'),
        () => Stream.fromIterable([2, 3]),
      ).toList();
      expect(out, [1, 2, 3]);
    });

    test('permission-denied: الخطأ يوصل للشاشة ومفيش استعلام بديل', () async {
      var fallbackCalled = false;
      final stream = withIndexFallback<int>(_failing('permission-denied'), () {
        fallbackCalled = true;
        return Stream.value(99);
      });
      await expectLater(
        stream,
        emitsInOrder([
          1,
          emitsError(
            isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied'),
          ),
        ]),
      );
      expect(fallbackCalled, isFalse);
    });

    test('لو الأساسي شغال، البديل ما بيتشغّلش خالص', () async {
      var fallbackCalled = false;
      final out = await withIndexFallback<int>(Stream.fromIterable([1, 2]), () {
        fallbackCalled = true;
        return Stream.value(99);
      }).toList();
      expect(out, [1, 2]);
      expect(fallbackCalled, isFalse);
    });
  });

  test('sortNewestFirstBy: الأحدث أولًا واللي من غير تاريخ في الآخر', () {
    final t = DateTime(2026, 11, 20, 10);
    final items = <(String, DateTime?)>[
      ('old', t.subtract(const Duration(days: 2))),
      ('none', null),
      ('new', t),
      ('mid', t.subtract(const Duration(hours: 5))),
    ];
    final out = sortNewestFirstBy(items, (e) => e.$2).map((e) => e.$1).toList();
    expect(out, ['new', 'mid', 'old', 'none']);
  });

  test('الفهرس المركّب لشاشة الإشعارات (userId + createdAt تنازلي) موجود في firestore.indexes.json', () {
    final json = jsonDecode(File('firestore.indexes.json').readAsStringSync()) as Map<String, dynamic>;
    final indexes = (json['indexes'] as List).cast<Map<String, dynamic>>();
    final found = indexes.any((ix) {
      if (ix['collectionGroup'] != 'notifications' || ix['queryScope'] != 'COLLECTION') return false;
      final f = (ix['fields'] as List).cast<Map<String, dynamic>>();
      return f.length >= 2 &&
          f[0]['fieldPath'] == 'userId' && f[0]['order'] == 'ASCENDING' &&
          f[1]['fieldPath'] == 'createdAt' && f[1]['order'] == 'DESCENDING';
    });
    expect(found, isTrue, reason: 'استعلام الإشعارات محتاج الفهرس ده، ولازم يتنشر (firebase deploy --only firestore:indexes).');
  });
}
