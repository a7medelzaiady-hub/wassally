import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('فهرس collection group لتقديمات المناديب (createdAt تنازلي) متعرّف', () {
    final json = jsonDecode(File('firestore.indexes.json').readAsStringSync()) as Map<String, dynamic>;
    final overrides = (json['fieldOverrides'] as List).cast<Map<String, dynamic>>();
    final o = overrides.firstWhere(
      (x) => x['collectionGroup'] == 'applicants' && x['fieldPath'] == 'createdAt',
      orElse: () => const {},
    );
    final idx = ((o['indexes'] as List?) ?? const []).cast<Map<String, dynamic>>();
    expect(
      idx.any((i) => i['queryScope'] == 'COLLECTION_GROUP' && i['order'] == 'DESCENDING'),
      isTrue,
      reason: 'تبويب «تقديمات المناديب» بيستخدم collectionGroup(applicants).orderBy(createdAt desc).',
    );
  });
}
