import '../models/order.dart';

/// بعد المدة دي الطلب الجديد اللي المحل ما ردّش عليه بيتحسب متأخر.
/// نفس المدة اللي بتشغّل تنبيه «طلبات ما اتردش عليها» عند الإدارة والمحل
/// (UnansweredOrdersAlert)، فالعميل والإدارة بيشوفوا التأخير في نفس الوقت.
const Duration kStoreReplyGrace = Duration(minutes: 5);

enum StoreWaitStage {
  /// مفيش انتظار: المحل رد (بيجهّز / ناقص أصناف) أو الطلب خلص.
  none,

  /// الطلب اتبعت والمحل لسه ما أكدش، وده لسه في الوقت الطبيعي.
  waiting,

  /// المحل ما أكدش بعد [kStoreReplyGrace].
  late,
}

/// حالة انتظار تأكيد المحل، محسوبة من حالة الطلب ووقته بس (من غير أي قراءة).
///
/// - [createdAt] وقت الخادم؛ لو ساعة الموبايل متأخرة الفرق السالب بيتحسب صفر.
/// - لو المحل علّم أصناف مش متاحة يبقى رد فعلًا، والعميل عنده سؤال تاني يجاوبه.
StoreWaitStage storeWaitStage({
  required OrderStatus status,
  required bool hasUnavailableItems,
  required DateTime? createdAt,
  required DateTime now,
}) {
  if (status != OrderStatus.newOrder || hasUnavailableItems) {
    return StoreWaitStage.none;
  }
  if (createdAt == null) return StoreWaitStage.waiting;
  return storeWaitElapsed(createdAt, now) >= kStoreReplyGrace
      ? StoreWaitStage.late
      : StoreWaitStage.waiting;
}

StoreWaitStage storeWaitStageOf(AppOrder order, DateTime now) => storeWaitStage(
      status: order.status,
      hasUnavailableItems: order.hasUnavailableItems,
      createdAt: order.createdAt,
      now: now,
    );

/// المدة من إرسال الطلب، ومش أقل من صفر (فرق ساعة الموبايل عن الخادم).
Duration storeWaitElapsed(DateTime createdAt, DateTime now) {
  final d = now.difference(createdAt);
  return d.isNegative ? Duration.zero : d;
}

/// «لسه حالًا» / «بقاله دقيقتين» / «بقاله 7 دقايق» / «بقاله 12 دقيقة» / «بقاله ساعة».
String storeWaitAgeText(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return 'لسه حالًا';
  if (m < 60) {
    if (m == 1) return 'بقاله دقيقة';
    if (m == 2) return 'بقاله دقيقتين';
    if (m <= 10) return 'بقاله $m دقايق';
    return 'بقاله $m دقيقة';
  }
  final h = m ~/ 60;
  if (h == 1) return 'بقاله ساعة';
  if (h == 2) return 'بقاله ساعتين';
  if (h <= 10) return 'بقاله $h ساعات';
  return 'بقاله $h ساعة';
}

/// اسم الحالة في قايمة «طلباتي»: الطلب الجديد ما يتكتبش «المحل استلم الطلب»
/// قبل ما المحل يأكد فعلًا.
String customerStatusLabel(AppOrder order, DateTime now) {
  switch (storeWaitStageOf(order, now)) {
    case StoreWaitStage.waiting:
      return 'مستني تأكيد المحل';
    case StoreWaitStage.late:
      return 'المحل اتأخر في التأكيد';
    case StoreWaitStage.none:
      return order.status.label;
  }
}
