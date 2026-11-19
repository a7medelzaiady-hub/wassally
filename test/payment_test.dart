import 'package:city_store/models/order.dart';
import 'package:city_store/services/payment_service.dart';
import 'package:flutter_test/flutter_test.dart';

AppOrder _order({
  String method = 'cash',
  String status = '',
  double total = 40,
  double? verifiedTotal,
}) =>
    AppOrder.fromMap('o1', {
      'storeName': 'S',
      'items': const [],
      'subtotal': total - 20,
      'deliveryFee': 20,
      'total': total,
      'status': 'new',
      'paymentMethod': method,
      if (status.isNotEmpty) 'paymentStatus': status,
      'verifiedTotal': ?verifiedTotal,
    });

void main() {
  group('cash to collect (must match expectedCollected in firestore.rules)', () {
    test('cash orders collect the approved total', () {
      expect(_order().cashToCollect, 40);
      expect(_order(verifiedTotal: 35).cashToCollect, 35);
      expect(_order().paymentCleared, isTrue);
    });

    test('confirmed wallet orders collect nothing, or only an approved increase', () {
      final paid = _order(method: 'vodafone_cash', status: 'confirmed');
      expect(paid.cashToCollect, 0);
      expect(_order(method: 'instapay', status: 'confirmed', verifiedTotal: 55).cashToCollect, 15);
      expect(_order(method: 'instapay', status: 'confirmed', verifiedTotal: 30).cashToCollect, 0);
      expect(paid.paymentCleared, isTrue);
    });

    test('pending or rejected wallet orders are not cleared for preparation', () {
      expect(_order(method: 'vodafone_cash', status: 'pending').paymentCleared, isFalse);
      expect(_order(method: 'vodafone_cash', status: 'rejected').paymentCleared, isFalse);
      expect(_order(method: 'vodafone_cash', status: 'pending').cashToCollect, 40);
    });

    test('old orders without a payment method are treated as cash', () {
      final legacy = AppOrder.fromMap('o2', {'total': 25, 'status': 'new'});
      expect(legacy.paymentMethod, 'cash');
      expect(legacy.isWalletPayment, isFalse);
      expect(legacy.cashToCollect, 25);
    });
  });

  group('transaction reference', () {
    test('normalizes spaces, dashes and case', () {
      expect(PaymentService.normalizeRef(' tx-12 34ab '), 'TX1234AB');
    });

    test('accepts 4-40 letters/digits only', () {
      expect(PaymentService.isValidRef('AB12'), isTrue);
      expect(PaymentService.isValidRef('A' * 40), isTrue);
      expect(PaymentService.isValidRef('AB1'), isFalse);
      expect(PaymentService.isValidRef('A' * 41), isFalse);
      expect(PaymentService.isValidRef('TX_1234'), isFalse);
    });
  });

  group('payment settings', () {
    test('cash is always available; wallets need the switch and a destination', () {
      expect(const PaymentSettings().available, [PaymentMethod.cash]);
      const s = PaymentSettings(enabled: true, vodafoneCashNumber: '01012345678');
      expect(s.available, [PaymentMethod.cash, PaymentMethod.vodafoneCash]);
      const off = PaymentSettings(vodafoneCashNumber: '01012345678', instapayAddress: 'x@instapay');
      expect(off.available, [PaymentMethod.cash]);
    });
  });
}
