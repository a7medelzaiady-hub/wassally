import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/services/referral_device.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only Android-scoped, 16-character hex identifiers are accepted', () {
    expect(ReferralDevice.isValidAndroidId('a1b2c3d4e5f60718'), isTrue);
    expect(ReferralDevice.isValidAndroidId('A1B2C3D4E5F60718'), isTrue);
    expect(ReferralDevice.isValidAndroidId('0000000000000000'), isFalse);
    expect(ReferralDevice.isValidAndroidId('9774d56d682e549c'), isFalse);
    expect(ReferralDevice.isValidAndroidId('not-a-device'), isFalse);
    expect(ReferralDevice.isValidAndroidId(null), isFalse);
  });

  test('Android platform channel returns scoped identifier without storing it', () async {
    const channel = MethodChannel('com.wassally.app/referral_device');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'androidScopedId');
      return 'A1B2C3D4E5F60718';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await ReferralDevice.androidScopedId(), 'a1b2c3d4e5f60718');
  });
}
