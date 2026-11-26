import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Device-scoped Android ID for preventing repeated first-time referral awards.
/// Sent once to the authenticated Cloudflare Worker over HTTPS; the Worker
/// stores only a purpose-limited HMAC, never this raw value or the Google ID.
/// It is scoped per Android user + app signing key and can change on reset.
class ReferralDevice {
  const ReferralDevice._();
  static const MethodChannel _channel =
      MethodChannel('com.wassally.app/referral_device');

  @visibleForTesting
  static bool isValidAndroidId(String? id) =>
      id != null &&
      RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(id) &&
      id.toLowerCase() != '9774d56d682e549c' &&
      id != '0000000000000000';

  static Future<String> androidScopedId() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw StateError('كود الدعوة متاح من تطبيق أندرويد فقط.');
    }
    final id = await _channel.invokeMethod<String>('androidScopedId');
    if (!isValidAndroidId(id)) {
      throw StateError('تعذر التحقق من الجهاز لاستحقاق كود الدعوة.');
    }
    return id!.toLowerCase();
  }
}
