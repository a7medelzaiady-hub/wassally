import 'package:city_store/models/order.dart';
import 'package:city_store/screens/orders_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('اسم المحل يظهر بصيغة محل كذا بدون تكرار', () {
    expect(orderStoreTitle('الزيادي لزيوت السيارات'), 'محل الزيادي لزيوت السيارات');
    expect(orderStoreTitle('  فواكه وخضروات  '), 'محل فواكه وخضروات');
    expect(orderStoreTitle('محل الأمانة'), 'محل الأمانة');
    expect(orderStoreTitle(''), 'طلب من محل');
  });

  test('حالة الطلب الجديد واضحة للعميل في كل شاشة تستخدم التسمية الموحدة', () {
    expect(OrderStatus.newOrder.label, 'المحل استلم الطلب');
    expect(OrderStatus.parse('new').label, 'المحل استلم الطلب');
    expect(OrderStatus.preparing.label, 'جاري التحضير');
    expect(OrderStatus.delivered.label, 'تم التوصيل');
  });
}
