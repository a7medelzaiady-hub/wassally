import 'package:city_store/services/server_orders_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Worker-enabled APK never needs an extra Firestore security read',
      () async {
    var reads = 0;
    final enabled = await ServerOrdersGate.resolve(
      clientWorkerEnabled: true,
      readServerMode: () async {
        reads++;
        return false;
      },
    );
    expect(enabled, isTrue);
    expect(reads, 0);
  });

  test('Old APK respects verified live serverOrders=true and blocks old path',
      () async {
    final enabled = await ServerOrdersGate.resolve(
      clientWorkerEnabled: false,
      readServerMode: () async => true,
    );
    expect(enabled, isTrue);
  });

  test('Old APK may use legacy mode only if server explicitly returned false',
      () async {
    final enabled = await ServerOrdersGate.resolve(
      clientWorkerEnabled: false,
      readServerMode: () async => false,
    );
    expect(enabled, isFalse);
  });

  test('Offline or denied security gate fails closed without fake update prompt',
      () async {
    var reads = 0;
    try {
      await ServerOrdersGate.resolve(
        clientWorkerEnabled: false,
        readServerMode: () async {
          reads++;
          throw Exception('unavailable');
        },
      );
      fail('Unknown server gate cannot enable legacy Firestore writes');
    } on StateError catch (error) {
      expect(error.message, contains('اتأكد من اتصال الإنترنت'));
      expect(error.message, contains('سلتك محفوظة'));
      expect(error.message, isNot(contains('حدّث تطبيق')));
    }
    expect(reads, 1);
  });
}
