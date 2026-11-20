import 'package:city_store/models/store.dart';
import 'package:city_store/screens/admin_stores_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('المحل مفتوح افتراضيًا، والمغلق بيتقري صح', () {
    expect(Store.fromMap('s1', {'name': 'A'}).isOpen, isTrue);
    expect(Store.fromMap('s1', {'name': 'A', 'isOpen': false}).isOpen, isFalse);
    expect(Store.fromMap('s1', {'name': 'A', 'isOpen': false}).active, isTrue);
  });

  test('حالة المحل في قائمة الإدارة: الإخفاء منفصل عن الغلق', () {
    expect(storeVisibilityLabel({'active': false}), 'مخفي عن العملاء');
    expect(storeVisibilityLabel({}), 'ظاهر • مفتوح');
    expect(storeVisibilityLabel({'isOpen': false}), 'ظاهر • مغلق الآن');
  });
}
