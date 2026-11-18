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
/// المطابقة تعتمد على productId عند توفره. الأصناف القديمة بلا معرف لا تُطابق
/// تلقائيًا إذا تكرر الاسم، لتجنب اختيار صنف بناءً على سعر العميل.
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
    // نستخدم معرّف مستند الكتالوج متى توفر؛ الاسم وحده ليس هوية فريدة للصنف.
    final matches = line.productId.isNotEmpty
        ? catalog.where((p) => p.id == line.productId).toList()
        : catalog.where((p) => p.name == line.name).toList();

    // المعرف المفقود أو الاسم المكرر يجعل المطابقة غير مؤكدة؛ لا نختار
    // الصنف الذي يوافق السعر المرسل من العميل لأن ذلك يسمح بإخفاء التلاعب.
    if (matches.length != 1) {
      anyMissing = true;
      issues.add(PriceIssue(line.name, line.price, null));
      continue;
    }

    final product = matches.single;
    // الخيارات الإضافية بتتحقق بالاسم والسعر من خيارات الصنف في الكتالوج.
    final optionsTotal = _catalogOptionsTotal(product, line);
    final unit = product.price + (optionsTotal ?? 0);
    catalogSubtotal += unit * line.qty;
    if (optionsTotal == null || (unit - line.price).abs() >= 0.01) {
      anyDiff = true;
      issues.add(PriceIssue(line.name, line.price, unit));
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

/// مجموع أسعار خيارات [line] حسب خيارات [product] في الكتالوج.
/// بيرجع null لو اختيار مش موجود في الكتالوج أو مجموع السطر مش مطابق.
double? _catalogOptionsTotal(Product product, OrderLine line) {
  if (line.options.isEmpty) {
    return line.optionsTotal.abs() < 0.01 ? 0 : null;
  }
  var total = 0.0;
  for (final name in line.options) {
    ProductOption? found;
    for (final g in product.optionGroups) {
      for (final o in g.options) {
        if (o.name == name) {
          found = o;
          break;
        }
      }
      if (found != null) break;
    }
    if (found == null) return null;
    total += found.price;
  }
  return (total - line.optionsTotal).abs() < 0.01 ? total : null;
}
