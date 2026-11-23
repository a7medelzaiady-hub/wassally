import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// بيشغّل [primary]، ولو فشل بسبب فهرس مركّب ناقص (`failed-precondition`) بيكمل على [fallback].
/// أي خطأ تاني (صلاحيات، شبكة...) بيعدّي زي ما هو عشان الشاشة تعرضه.
/// الخطأ بيتسجّل بكوده بس (من غير أي بيانات شخصية).
Stream<T> withIndexFallback<T>(
  Stream<T> primary,
  Stream<T> Function() fallback, {
  String label = 'query',
}) async* {
  try {
    await for (final v in primary) {
      yield v;
    }
  } on FirebaseException catch (e) {
    debugPrint('[$label] ${e.plugin}/${e.code}');
    if (e.code != 'failed-precondition') rethrow;
    debugPrint('[$label] فهرس ناقص، تحويل للاستعلام البديل بدون ترتيب على الخادم.');
    yield* fallback();
  }
}

/// ترتيب الأحدث أولًا حسب التاريخ اللي بيرجعه [at] (اللي من غير تاريخ في الآخر).
/// لازم بعد الاستعلام البديل لأنه من غير orderBy.
List<T> sortNewestFirstBy<T>(Iterable<T> items, DateTime? Function(T) at) {
  final list = items.toList();
  list.sort((a, b) {
    final x = at(a), y = at(b);
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  });
  return list;
}

/// نفس الترتيب على مستندات الإشعارات (حقل `createdAt`).
List<QueryDocumentSnapshot<Map<String, dynamic>>> sortNewestFirst(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) => sortNewestFirstBy(docs, (d) {
  final v = d.data()['createdAt'];
  return v is Timestamp ? v.toDate() : null;
});

/// إشعارات المستخدم الحالي (الأحدث أولًا، بحد أقصى [limit]).
/// الأساسي محتاج فهرس (userId + createdAt)، لو لسه ما اتنشرش بنقع على استعلام
/// بحد برضه (userId بس) من غير أي مستمع إضافي، فالقراءات ما بتزيدش.
Stream<QuerySnapshot<Map<String, dynamic>>> watchMyNotifications(
  FirebaseFirestore db,
  String uid,
  int limit,
) {
  final base = db.collection('notifications').where('userId', isEqualTo: uid);
  return withIndexFallback(
    base.orderBy('createdAt', descending: true).limit(limit).snapshots(),
    () => base.limit(limit).snapshots(),
    label: 'notifications',
  );
}
