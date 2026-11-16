/// إشعارات الدفع والتنبيهات تُرسل من أحداث Firestore الموثوقة أو Order Gateway.
/// لا توجد هنا استدعاءات عامة للـWorker؛ أي طلب من التطبيق يحتاج مصادقة وتفويضًا.
@Deprecated('Use trusted Firestore triggers or authenticated order gateway flows.')
class WorkerNotifyService {
  const WorkerNotifyService._();
}
