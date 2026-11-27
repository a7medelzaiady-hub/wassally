import '../models/order.dart';

/// مدى بالدقايق (من-إلى).
typedef EtaRange = ({int min, int max});

/// لو المحل ما كتبش وقت توصيل: تقدير عام معقول لمشوار جوه الحي.
const EtaRange kDefaultStoreEta = (min: 30, max: 45);

/// مشوار المندوب من المحل للعميل بعد ما يستلم الطلب.
const EtaRange kCourierLegEta = (min: 10, max: 20);

/// بيفهم وقت المحل اللي الإدارة كاتباه: «25-35 د» / «٢٥ - ٣٥ دقيقة» / «30» / «20–30».
/// بيرجع null لو مش مفهوم أو برا حدود معقولة (5 دقايق لـ 3 ساعات).
EtaRange? parseStoreEta(String raw) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  var text = raw;
  for (var i = 0; i < arabic.length; i++) {
    text = text.replaceAll(arabic[i], '$i');
  }
  final nums = RegExp(r'\d+').allMatches(text).map((m) => int.parse(m.group(0)!)).toList();
  if (nums.isEmpty || nums.length > 2) return null;
  var a = nums.first;
  var b = nums.length == 2 ? nums[1] : nums.first;
  if (a > b) (a, b) = (b, a);
  if (a < 5 || b > 180) return null;
  if (a == b) b = a + 10; // «30» = 30–40
  return (min: a, max: b);
}

EtaRange storeEtaOrDefault(String? raw) =>
    (raw == null ? null : parseStoreEta(raw)) ?? kDefaultStoreEta;

/// «25–35 دقيقة»
String etaRangeText(EtaRange r) => '${r.min}–${r.max} دقيقة';

/// «6:25» (من غير ص/م لو الاتنين في نفس النص من اليوم).
String _clock(DateTime d, {bool withPeriod = true}) {
  var h = d.hour % 12;
  if (h == 0) h = 12;
  final m = d.minute.toString().padLeft(2, '0');
  return withPeriod ? '$h:$m ${d.hour >= 12 ? 'م' : 'ص'}' : '$h:$m';
}

/// «بين 6:25 و 6:40 م»
String etaWindowText(DateTime from, DateTime to) {
  final samePeriod = (from.hour >= 12) == (to.hour >= 12);
  return 'بين ${_clock(from, withPeriod: !samePeriod)} و ${_clock(to)}';
}

/// تقدير وصول الطلب للعميل، محسوب من حالة الطلب وأوقاته ووقت المحل (من غير قراءات).
class DeliveryEta {
  final DateTime from;
  final DateTime to;

  /// عدّى آخر الوقت المتوقع والطلب لسه ما وصلش.
  final bool overdue;
  const DeliveryEta(this.from, this.to, {required this.overdue});

  String get text => etaWindowText(from, to);
}

/// - بيجهّز: من وقت الطلب + وقت المحل.
/// - في الطريق: من وقت استلام المندوب + مشوار الحي.
/// - جديد (المحل لسه ما أكدش) / المندوب وصل / خلص: مفيش تقدير.
DeliveryEta? deliveryEtaFor(AppOrder order, EtaRange storeEta, DateTime now) {
  DateTime? base;
  EtaRange range;
  switch (order.status) {
    case OrderStatus.preparing:
      base = order.createdAt;
      range = storeEta;
    case OrderStatus.onTheWay:
      if (order.courierArrivedAt != null || order.customerConfirmedAt != null) return null;
      base = order.pickedUpAt ?? order.courierAt;
      range = kCourierLegEta;
      // الطلب اتسجل في الطريق من غير وقت استلام: نرجع لتقدير المحل من وقت الطلب.
      if (base == null) {
        base = order.createdAt;
        range = storeEta;
      }
    default:
      return null;
  }
  if (base == null) return null;
  final from = base.add(Duration(minutes: range.min));
  final to = base.add(Duration(minutes: range.max));
  return DeliveryEta(from, to, overdue: now.isAfter(to));
}
