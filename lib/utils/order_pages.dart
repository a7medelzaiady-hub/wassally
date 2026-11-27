import '../models/order.dart';

/// دمج صفحات طلبات الإدارة: الصفحة الأولى لحظية (مستمع واحد بحد ثابت)،
/// والصفحات الأقدم بتتحمّل مرة واحدة بمؤشر (cursor) بعد آخر طلب ظاهر.
///
/// قبل كده «عرض طلبات أقدم» كان بيكبّر حد نفس المستمع (100 ← 200 ← 300)،
/// فكل ضغطة بتفتح مستمع جديد يعيد قراية كل الطلبات اللي اتحمّلت قبل كده.
/// دلوقتي كل ضغطة بتقرا الصفحة الجديدة بس.

/// الطلبات اللي كانت في الصفحة اللحظية وخرجت منها (لأن طلبات أحدث وصلت)
/// بتتحفظ في [spill] عشان ما تختفيش من القايمة بين الصفحة اللحظية والصفحات الأقدم.
/// أي طلب رجع للصفحة اللحظية بيتشال من [spill] (اللحظي هو الأحدث).
void spillDroppedOrders({
  required List<AppOrder> previousLive,
  required List<AppOrder> nextLive,
  required Map<String, AppOrder> spill,
}) {
  final nextIds = {for (final o in nextLive) o.id};
  for (final o in previousLive) {
    if (!nextIds.contains(o.id)) spill[o.id] = o;
  }
  spill.removeWhere((id, _) => nextIds.contains(id));
}

/// القايمة اللي بتظهر: اللحظي أولًا (أحدث نسخة من الطلب)، وبعده الباقي من غير تكرار،
/// مترتبة من الأحدث للأقدم (الطلب اللي لسه بيتحفظ من غير وقت بيظهر الأول).
List<AppOrder> mergeOrderPages(List<AppOrder> live, Iterable<AppOrder> extra) {
  final byId = <String, AppOrder>{};
  for (final o in extra) {
    byId[o.id] = o;
  }
  for (final o in live) {
    byId[o.id] = o;
  }
  final list = byId.values.toList();
  list.sort((a, b) {
    final aMs = a.createdAt?.millisecondsSinceEpoch ?? 1 << 53;
    final bMs = b.createdAt?.millisecondsSinceEpoch ?? 1 << 53;
    final byTime = bMs.compareTo(aMs);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  });
  return list;
}

/// آخر طلب له وقت في القايمة: المؤشر اللي الصفحة الأقدم بتبدأ بعده.
AppOrder? oldestTimedOrder(List<AppOrder> orders) {
  for (var i = orders.length - 1; i >= 0; i--) {
    if (orders[i].createdAt != null) return orders[i];
  }
  return null;
}
