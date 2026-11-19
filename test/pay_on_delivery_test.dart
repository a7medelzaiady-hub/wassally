import 'package:city_store/models/order.dart';
import 'package:flutter_test/flutter_test.dart';

AppOrder _order({String paidBy = '', double total = 40, double? verifiedTotal}) =>
    AppOrder.fromMap('o1', {
      'storeName': 'S',
      'items': const [],
      'subtotal': total - 20,
      'deliveryFee': 20,
      'total': total,
      'status': 'on_the_way',
      if (paidBy.isNotEmpty) 'paidBy': paidBy,
      'verifiedTotal': ?verifiedTotal,
    });

void main() {
  group('cash the courier collected (must match expectedCollected in firestore.rules)', () {
    test('cash or not recorded yet: the approved total', () {
      expect(_order().cashToCollect, 40);
      expect(_order(paidBy: 'cash').cashToCollect, 40);
      expect(_order(verifiedTotal: 35).cashToCollect, 35);
      expect(_order(paidBy: 'cash').collectFor(55), 55);
    });

    test('paid to the store wallet: zero cash, whatever the total', () {
      final o = _order(paidBy: 'store_wallet', verifiedTotal: 55);
      expect(o.paidToStoreWallet, isTrue);
      expect(o.cashToCollect, 0);
      expect(o.collectFor(70), 0);
    });

    test('old orders without paidBy are cash', () {
      final legacy = AppOrder.fromMap('o2', {'total': 25, 'status': 'delivered'});
      expect(legacy.paidBy, '');
      expect(legacy.paidToStoreWallet, isFalse);
      expect(legacy.cashToCollect, 25);
    });
  });
}
