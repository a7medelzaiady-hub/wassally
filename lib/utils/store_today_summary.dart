import '../models/order.dart';

/// ملخص «النهارده» لصاحب المحل، محسوب من الطلبات اللي ظاهرة عنده أصلًا
/// (نفس مستمع صفحة المحل): صفر قراءات زيادة.
class StoreTodaySummary {
  /// كل طلبات النهارده ما عدا الملغي.
  final int orders;
  final int delivered;
  final int cancelled;

  /// قيمة البضاعة للطلبات المسلّمة النهارده.
  final double deliveredGoods;

  /// قيمة البضاعة لكل طلبات النهارده غير الملغية (مسلّم + شغال).
  final double expectedGoods;

  const StoreTodaySummary({
    required this.orders,
    required this.delivered,
    required this.cancelled,
    required this.deliveredGoods,
    required this.expectedGoods,
  });

  bool get isEmpty => orders == 0 && cancelled == 0;

  /// الطلبات اللي اتعملت من أول اليوم (بتوقيت الموبايل) لحد [now].
  factory StoreTodaySummary.of(List<AppOrder> all, DateTime now) {
    final start = DateTime(now.year, now.month, now.day);
    var orders = 0, delivered = 0, cancelled = 0;
    var deliveredGoods = 0.0, expectedGoods = 0.0;
    for (final o in all) {
      final at = o.createdAt?.toLocal();
      if (at == null || at.isBefore(start) || at.isAfter(now)) continue;
      if (o.status == OrderStatus.cancelled) {
        cancelled++;
        continue;
      }
      orders++;
      expectedGoods += o.subtotal;
      if (o.status == OrderStatus.delivered) {
        delivered++;
        deliveredGoods += o.subtotal;
      }
    }
    return StoreTodaySummary(
      orders: orders,
      delivered: delivered,
      cancelled: cancelled,
      deliveredGoods: deliveredGoods,
      expectedGoods: expectedGoods,
    );
  }
}
