import 'package:city_store/services/admin_inbox_counts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('شارة الأعداد ونص تنبيه فتح التطبيق', () {
    expect(AdminInboxCounts.badgeText(3), '3');
    expect(AdminInboxCounts.badgeText(12), '9+');
    expect(const AdminInboxCounts(joinRequests: 2, deliveryIssues: 1).total, 3);
    expect(AdminInboxCounts.alertText(const AdminInboxCounts()), isNull);
    expect(AdminInboxCounts.alertText(const AdminInboxCounts(joinRequests: 2, deliveryIssues: 1)),
        'محتاج مراجعتك: 2 طلب انضمام و1 بلاغ تعذر تسليم.');
    expect(AdminInboxCounts.alertText(const AdminInboxCounts(deliveryIssues: 4)),
        'محتاج مراجعتك: 4 بلاغ تعذر تسليم.');
  });
}
