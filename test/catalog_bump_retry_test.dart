import 'package:city_store/services/catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('إعادة رفع إصدار الكتالوج بعد حد السرعة (60 ث في القواعد)', () {
    expect(CatalogService.shouldRetryBump('permission-denied'), isTrue);
    expect(CatalogService.shouldRetryBump('unavailable'), isFalse);
    expect(CatalogService.bumpRetryDelay > const Duration(seconds: 60), isTrue);
  });
}
