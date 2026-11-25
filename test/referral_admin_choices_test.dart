import 'package:city_store/models/referral_admin_choices.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('قوائم الإدارة الآمنة للدعوات', () {
    test('ترتبط المحلات بأصحاب الحسابات النشطين فقط، وتدعم أكثر من مالك', () {
      final options = referralStoreOwnerChoices(
        storeNames: {'s1': 'بقالة النور', 's2': 'مخبز', 's3': ''},
        owners: [
          {'uid': 'u1', 'storeId': 's1', 'name': 'أحمد', 'active': true},
          {'uid': 'u2', 'storeId': 's1', 'name': 'محمد', 'active': true},
          {'uid': 'u3', 'storeId': 's2', 'name': 'مغلق', 'active': false},
          {'uid': 'u4', 'storeId': 'bad', 'name': 'غير مرتبط'},
          {'uid': 'u1', 'storeId': 's1', 'name': 'مكرر'},
          {'uid': 'u5', 'storeId': 's3', 'name': 'بدون اسم محل'},
        ],
      );
      expect(options.length, 2);
      expect(options.map((option) => option.ownerUid), containsAll(['u1', 'u2']));
      expect(options.every((option) => option.storeId == 's1'), isTrue);
      expect(options.map((option) => option.key).toSet().length, 2);
    });

    test('تعرض طلبات نقاط مسلّمة أو ملغاة فقط وتستبعد الصفر والمكرّر', () {
      final choices = referralEligibleOrders([
        {'id': 'delivered', 'status': 'delivered', 'storeName': 'المحل', 'referralDiscountMinor': 500},
        {'id': 'cancelled', 'status': 'cancelled', 'referralDiscountMinor': 120},
        {'id': 'new', 'status': 'new', 'referralDiscountMinor': 300},
        {'id': 'no-points', 'status': 'delivered', 'referralDiscountMinor': 0},
        {'id': 'delivered', 'status': 'delivered', 'referralDiscountMinor': 500},
        {'id': 'invalid', 'status': 'delivered', 'referralDiscountMinor': 1.5},
      ]);
      expect(choices.map((option) => option.id), ['delivered', 'cancelled']);
      expect(choices.first.isDelivered, isTrue);
      expect(choices.last.isCancelled, isTrue);
      expect(choices.first.label, contains('5.00'));
    });
  });
}
