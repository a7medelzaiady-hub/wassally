import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/services/order_gateway.dart';

void main() {
  test('server order writes stay disabled unless explicitly enabled at build time', () {
    expect(
      OrderGateway.serverOrdersEnabled,
      const bool.fromEnvironment('WASALLY_SERVER_ORDERS', defaultValue: false),
    );
  });

  test('the gateway URL remains independently configurable for signed image uploads', () {
    // The URL may be supplied by the build; it must not implicitly enable
    // server-side order creation or editing.
    expect(OrderGateway.serverOrdersEnabled, isFalse);
  });
  
  test('the gateway URL is HTTPS and independently configured', () {
    expect(Uri.parse(OrderGateway.baseUrl).scheme, 'https');
    expect(OrderGateway.isConfigured, isTrue);
  });
}

