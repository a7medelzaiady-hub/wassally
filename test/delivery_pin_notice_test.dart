import 'package:city_store/models/order.dart';
import 'package:city_store/screens/order_details_page.dart';
import 'package:city_store/utils/delivery_pin_notice.dart';
import 'package:flutter_test/flutter_test.dart';

AppOrder _o(OrderStatus s, {DateTime? confirmed}) => AppOrder(
      id: 'o1', storeName: 'S', items: const [], subtotal: 10, deliveryFee: 20, total: 30,
      status: s, createdAt: DateTime(2026, 11, 21), address: 'a', phone: '010', notes: '',
      customerConfirmedAt: confirmed,
    );

void main() {
  test('تنبيه رمز التسليم بيذكر الـ4 أرقام والاحتفاظ بيه وإنه ثابت', () {
    expect(kDeliveryPinKeepNotice, contains('4 أرقام'));
    expect(kDeliveryPinKeepNotice, contains('احتفظ'));
    expect(kDeliveryPinKeepNotice, contains('ثابت'));
  });

  test('الرمز بيظهر من أول الطلب لحد التسليم أو الإلغاء أو تأكيد الاستلام', () {
    expect(orderShowsDeliveryPin(_o(OrderStatus.newOrder)), isTrue);
    expect(orderShowsDeliveryPin(_o(OrderStatus.preparing)), isTrue);
    expect(orderShowsDeliveryPin(_o(OrderStatus.onTheWay)), isTrue);
    expect(orderShowsDeliveryPin(_o(OrderStatus.delivered)), isFalse);
    expect(orderShowsDeliveryPin(_o(OrderStatus.cancelled)), isFalse);
    expect(orderShowsDeliveryPin(_o(OrderStatus.onTheWay, confirmed: DateTime(2026, 11, 21))), isFalse);
  });
}
