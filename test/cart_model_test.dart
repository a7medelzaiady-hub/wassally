import 'package:city_store/models/product.dart';
import 'package:city_store/services/cart_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const falafel = Product('ساندوتش فلافل', 10);
  const fries = Product('بطاطس', 12);

  group('CartModel', () {
    late CartModel cart;
    setUp(() => cart = CartModel());

    test('تبدأ فاضية والإجمالي صفر', () {
      expect(cart.isEmpty, isTrue);
      expect(cart.count, 0);
      expect(cart.total, 0);
    });

    test('الإضافة بتزوّد الكمية وتحسب الإجمالي مع التوصيل', () {
      cart.add(falafel, storeId: 'a', storeName: 'مطعم');
      cart.add(falafel, storeId: 'a', storeName: 'مطعم');
      cart.add(fries, storeId: 'a', storeName: 'مطعم');

      expect(cart.count, 3);
      expect(cart.qtyOf(falafel), 2);
      expect(cart.subtotal, 32);
      expect(cart.total, 32 + CartModel.deliveryFee);
    });

    test('مينفعش تضيف من محل تاني قبل تفريغ السلة', () {
      expect(cart.add(falafel, storeId: 'a', storeName: 'مطعم'), isTrue);
      expect(cart.add(fries, storeId: 'b', storeName: 'سوبر'), isFalse);
      expect(cart.count, 1);
      expect(cart.storeName, 'مطعم');
    });

    test('الحذف بينقّص الكمية، وآخر منتج بيفرّغ السلة والمحل', () {
      cart.add(falafel, storeId: 'a', storeName: 'مطعم');
      cart.add(falafel, storeId: 'a', storeName: 'مطعم');

      cart.remove(falafel);
      expect(cart.qtyOf(falafel), 1);

      cart.remove(falafel);
      expect(cart.isEmpty, isTrue);
      expect(cart.storeId, isNull);
      expect(cart.add(fries, storeId: 'b', storeName: 'سوبر'), isTrue);
    });

    test('clear بتمسح كل حاجة', () {
      cart.add(falafel, storeId: 'a', storeName: 'مطعم');
      cart.clear();
      expect(cart.isEmpty, isTrue);
      expect(cart.total, 0);
    });

    test('السلة بتفضل بعد إرسال ناجح وبتمنع التكرار لحد اختيار العميل', () {
      cart.add(falafel, storeId: 'a', storeName: 'مطعم');
      cart.markSubmitted('order_123');
      expect(cart.items, contains(falafel));
      expect(cart.submittedOrderId, 'order_123');
      final saved = cart.snapshot();
      final restored = CartModel()..restore(saved);
      expect(restored.submittedOrderId, 'order_123');
      expect(restored.qtyOf(falafel), 1);
      restored.beginNewOrder();
      expect(restored.submittedOrderId, isNull);
      expect(restored.qtyOf(falafel), 1);
      restored.markSubmitted('order_456');
      restored.add(falafel, storeId: 'a', storeName: 'مطعم');
      expect(restored.submittedOrderId, isNull);
    });

    test('بتبلّغ المستمعين عند التغيير', () {
      var calls = 0;
      cart.addListener(() => calls++);
      cart.add(falafel, storeId: 'a', storeName: 'مطعم');
      cart.remove(falafel);
      expect(calls, 2);
    });

    test('التوصيل المجاني لأول طلب بيشيل الرسوم من الإجمالي', () {
      cart.add(falafel, storeId: 'a', storeName: 'مطعم');
      cart.setArea('منطقة بدون رسوم', 0);

      expect(cart.effectiveFee, 0);
      expect(cart.total, 10);

      cart.setArea('', CartModel.deliveryFee);
      expect(cart.total, 10 + CartModel.deliveryFee);
    });
  });
}
