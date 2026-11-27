/// صفحة أصناف صاحب المحل: نقرا الأصناف من الكاش ولا من الخادم؟
///
/// قبل كده كل فتح للصفحة (وكل تعديل بعد 10 دقايق) كان بيقرا لحد 200 صنف من
/// الخادم. دلوقتي بنقرا مستند القائمة المجمّعة (stores/{id}/menu/current) مرة
/// واحدة (قراءة واحدة) ونقارن «بصمته» (وقت آخر تحديث + عدد الأصناف) بالبصمة
/// اللي اتسجلت مع آخر تحميل كامل من الخادم. لو زي بعض، الكاش هو نفس اللي على
/// الخادم فبنعرض من الكاش (صفر قراءات للأصناف).
///
/// القائمة المجمّعة بتتحدّث بعد أي تعديل صنف من أي جهاز (CatalogSync)، فتعديل
/// من جهاز تاني بيغيّر البصمة ويجبر تحميل من الخادم.
enum OwnerProductsSource { cache, server }

/// أقصى مدة نعتمد فيها على الكاش من غير تحميل كامل من الخادم (أمان لو مزامنة
/// القائمة فشلت على جهاز تاني).
const Duration kOwnerProductsMaxCacheAge = Duration(hours: 24);

/// بصمة مستند القائمة المجمّعة، أو null لو المستند مش موجود.
String? menuFreshnessToken({required bool exists, int? updatedAtMs, int? count}) {
  if (!exists || updatedAtMs == null) return null;
  return '${updatedAtMs}_${count ?? -1}';
}

OwnerProductsSource ownerProductsSource({
  required bool force,
  required bool hasCache,
  required bool tokenReadFailed,
  required String? serverToken,
  required String? savedToken,
  required DateTime? lastFullLoad,
  required DateTime now,
}) {
  if (force || !hasCache) return OwnerProductsSource.server;
  // مفيش نت للتأكد: الكاش أحسن من رسالة خطأ، والتحميل من الخادم كان هيفشل أصلًا.
  if (tokenReadFailed) return OwnerProductsSource.cache;
  // المحل لسه ما عندوش قائمة مجمّعة (أو اتعطلت): نفس السلوك القديم.
  if (serverToken == null || savedToken == null) return OwnerProductsSource.server;
  if (lastFullLoad == null || now.difference(lastFullLoad) > kOwnerProductsMaxCacheAge) {
    return OwnerProductsSource.server;
  }
  return serverToken == savedToken ? OwnerProductsSource.cache : OwnerProductsSource.server;
}
