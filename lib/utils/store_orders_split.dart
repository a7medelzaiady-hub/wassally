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

/// يوم محلي (بتوقيت جهاز المستخدم، وهو المصري عندنا) لطلبات منتهية.
class ClosedDayGroup {
  final DateTime day; // 00:00 محلي
  final List<AppOrder> orders; // الأحدث أولاً
  final ClosedOrdersMoney money;
  const ClosedDayGroup({required this.day, required this.orders, required this.money});
}

/// وقت الطلب المستخدم للتجميع: وقت التسليم للمسلّم، وإلا وقت الإنشاء.
DateTime? closedOrderTime(AppOrder o) => (o.deliveredAt ?? o.createdAt)?.toLocal();

/// تجميع الطلبات المنتهية حسب اليوم المحلي، الأحدث أولاً.
/// المجاميع (بضاعة/رسوم) للمسلّم بس؛ الملغي بيتعدّ ومش بيدخل في أي مبلغ.
List<ClosedDayGroup> groupClosedByDay(List<AppOrder> closed) {
  final byDay = <DateTime, List<AppOrder>>{};
  for (final o in closed) {
    final t = closedOrderTime(o);
    if (t == null) continue;
    byDay.putIfAbsent(DateTime(t.year, t.month, t.day), () => []).add(o);
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final d in days)
      ClosedDayGroup(
        day: d,
        orders: (byDay[d]!..sort((a, b) => closedOrderTime(b)!.compareTo(closedOrderTime(a)!))),
        money: ClosedOrdersMoney.of(byDay[d]!),
      ),
  ];
}
