/// Resolve the server's trusted order-writing mode before submitting an order.
///
/// A debug APK can be compiled with the secure Worker enabled. Older builds
/// may still need to query the live Firestore security gate once. An unknown
/// gate is *not* equivalent to a verified enabled gate, and must never cause
/// an attempt to write directly to Firestore or a misleading update prompt.
class ServerOrdersGate {
  const ServerOrdersGate._();

  /// A missing, non-boolean or unpublished setting is not an explicit
  /// legacy-mode authorization. It must not become `false` by coercion.
  static bool? verifiedFlag(Object? value) => value is bool ? value : null;

  static Future<bool> resolve({
    required bool clientWorkerEnabled,
    required Future<bool?> Function() readServerMode,
  }) async {
    if (clientWorkerEnabled) return true;
    try {
      final verified = await readServerMode();
      if (verified == null) throw StateError('Missing serverOrders flag');
      return verified;
    } catch (_) {
      // Fail closed on network failure, permission errors or unavailable
      // server configuration. Never silently try the legacy Firestore batch.
      throw StateError(
        'تعذر التأكد من إعدادات تأكيد الطلبات. اتأكد من اتصال الإنترنت '
        'وحاول تاني. سلتك محفوظة زي ما هي.',
      );
    }
  }
}
