import '../models/order.dart';
import '../models/product.dart';
import '../models/store.dart';

/// نتيجة مقارنة أسعار الطلب بالكتالوج الحالي.
enum PriceCheckStatus {
  /// كل الأسعار مطابقة للكتالوج.
  match,

  /// فيه صنف سعره مختلف عن الكتالوج، أو الإجمالي مش مطابق.
  mismatch,

  /// معرفناش نتحقق (المحل أو صنف مش موجود في الكتالوج).
  unknown,
}

/// سطر فيه مشكلة في الطلب.
class PriceIssue {
  final String name;
  final double orderPrice;

  /// سعر الصنف في الكتالوج. null = الصنف مش موجود.
  final double? catalogPrice;

  const PriceIssue(this.name, this.orderPrice, this.catalogPrice);

  bool get missing => catalogPrice == null;
}

class PriceCheck {
  final PriceCheckStatus status;

  /// الإجمالي الصحيح حسب الكتالوج (مجموع الأصناف + رسوم التوصيل).
  /// بيكون معتمد بس لما [status] مش unknown.
  final double expectedTotal;
  final List<PriceIssue> issues;

  const PriceCheck(this.status, this.expectedTotal, this.issues);

  const PriceCheck.unknown()
    : status = PriceCheckStatus.unknown,
      expectedTotal = 0,
      issues = const [];
}

/// بيقارن أسعار [order] بأسعار [store] الحالية.
///
/// ملاحظة: الأسعار في الطلب بتتخزن باسم الصنف، فالمقارنة بالاسم. لو الأدمن
/// غيّر سعر أو اسم صنف بعد ما العميل طلب، هتظهر كفرق والأدمن هو اللي يقرر.
///
/// [extraProducts]: أصناف المحل المخزنة في stores/{id}/products (النظام الجديد).
/// الأصناف القديمة (مصفوفة جوه مستند المحل) بتتقرا من [store] نفسه.
PriceCheck checkOrderPrices(
  AppOrder order,
  Store? store, {
  Iterable<Product> extraProducts = const [],
}) {
  final catalog = [...?store?.products, ...extraProducts];
  if (store == null || catalog.isEmpty || order.items.isEmpty) {
    return const PriceCheck.unknown();
  }

  final issues = <PriceIssue>[];
  var catalogSubtotal = 0.0;
  var anyMissing = false;
  var anyDiff = false;

  for (final line in order.items) {
    final matches = catalog.where((p) => p.name == line.name).toList();
    if (matches.isEmpty) {
      anyMissing = true;
      issues.add(PriceIssue(line.name, line.price, null));
      continue;
    }
    // لو فيه أكتر من صنف بنفس الاسم، بنفضّل اللي سعره زي الطلب.
    final product = matches.firstWhere(
      (p) => (p.price - line.price).abs() < 0.01,
      orElse: () => matches.first,
    );
    catalogSubtotal += product.price * line.qty;
    if ((product.price - line.price).abs() >= 0.01) {
      anyDiff = true;
      issues.add(PriceIssue(line.name, line.price, product.price));
    }
  }

  if (anyMissing) return PriceCheck(PriceCheckStatus.unknown, 0, issues);

  final expected = catalogSubtotal + order.deliveryFee - order.discount;
  final totalDiff = (order.total - expected).abs() >= 0.01;
  final status = (anyDiff || totalDiff)
      ? PriceCheckStatus.mismatch
      : PriceCheckStatus.match;
  return PriceCheck(status, expected, issues);
}
