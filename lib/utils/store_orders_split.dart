import '../models/order.dart';

/// طلب لسه شغال (مش «تم التوصيل» ولا «ملغي»).
bool isOpenOrder(AppOrder o) =>
    o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled;

/// الطلبات المنتهية (تم التوصيل/ملغي) اللي لسه ما اتقفلش حسابها مع وصّلي.
/// [settledAt] = وقت آخر «تقفيل حساب» من الإدارة (null = عمره ما اتقفل).
/// الطلب بيتقارن بوقت تسليمه، أو وقت إنشائه لو ملغي، فالمقفول حسابه يختفي من صفحة المحل.
List<AppOrder> closedOrdersAfterSettlement(List<AppOrder> orders, DateTime? settledAt) {
  return [
    for (final o in orders)
      if (!isOpenOrder(o))
        if (settledAt == null ||
            (o.deliveredAt ?? o.createdAt) == null ||
            (o.deliveredAt ?? o.createdAt)!.isAfter(settledAt))
          o,
  ];
}

/// ملخص «الفلوس» للطلبات المنتهية المعروضة.
class ClosedOrdersMoney {
  final int completedCount;
  final int cancelledCount;

  /// قيمة البضاعة (أصناف الطلبات المسلّمة).
  final double goodsTotal;

  /// رسوم خدمة وصّلي على الطلبات المسلّمة.
  final double serviceFeeTotal;

  const ClosedOrdersMoney({
    required this.completedCount,
    required this.cancelledCount,
    required this.goodsTotal,
    required this.serviceFeeTotal,
  });

  factory ClosedOrdersMoney.of(List<AppOrder> closed) {
    var completed = 0;
    var cancelled = 0;
    var goods = 0.0;
    var fees = 0.0;
    for (final o in closed) {
      if (o.status == OrderStatus.delivered) {
        completed++;
        goods += o.subtotal;
        fees += o.serviceFee ?? 0;
      } else if (o.status == OrderStatus.cancelled) {
        cancelled++;
      }
    }
    return ClosedOrdersMoney(
      completedCount: completed,
      cancelledCount: cancelled,
      goodsTotal: goods,
      serviceFeeTotal: fees,
    );
  }
}
