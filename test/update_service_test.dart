import 'package:city_store/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateService.isNewer', () {
    test('إصدار أحدث', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.1'), isTrue);
      expect(UpdateService.isNewer('1.2.0', '1.10.0'), isTrue);
      expect(UpdateService.isNewer('1.0', '1.0.1'), isTrue);
    });

    test('نفس الإصدار أو أقدم', () {
      expect(UpdateService.isNewer('1.0.1', '1.0.1'), isFalse);
      expect(UpdateService.isNewer('2.0.0', '1.9.9'), isFalse);
      expect(UpdateService.isNewer('1.0.1', '1.0'), isFalse);
    });

    test('الأصفار الزايدة ورقم البناء مبيأثروش', () {
      expect(UpdateService.isNewer('1.0.1', '1.0.1.0'), isFalse);
      expect(UpdateService.isNewer('1.0.0+3', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('1.0.0+1', '1.0.1+9'), isTrue);
    });
  });
}
