import 'package:city_store/screens/admin_operations_report_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('مجموع تسويات اليوم: الأرقام بس', () {
    expect(sumAmounts([
      {'amount': 50},
      {'amount': 12.5},
      {'amount': 'x'},
      {},
      {'amount': double.nan},
    ]), 62.5);
    expect(sumAmounts(const []), 0);
    expect(maxSettlementsToday, greaterThan(0));
  });
}
