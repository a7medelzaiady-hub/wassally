import 'package:city_store/models/product.dart';
import 'package:city_store/services/cart_model.dart';
import 'package:city_store/utils/cart_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WhatsApp cart text contains checked items and totals only', () {
    final cart = CartModel();
    cart.add(const Product('لبن 1 لتر', 35),
        storeId: 's1', storeName: 'بقالة الخير', qty: 2);
    cart.add(const Product('سكر 1 كيلو', 28),
        storeId: 's1', storeName: 'بقالة الخير');
    final text = buildCartShareText(cart);
    expect(text, contains('بقالة الخير'));
    expect(text, contains('2 × لبن 1 لتر'));
    expect(text, contains('1 × سكر 1 كيلو'));
    expect(text, contains('إجمالي الأصناف'));
    expect(text, contains('98'));
    expect(text, isNot(contains('http')));
    expect(text, isNot(contains('0100')));
  });
}
