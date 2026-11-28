// #339: أسماء المسارات القابلة للاستعادة ما فيهاش بيانات شخصية.
import 'package:city_store/services/route_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds and parses plain and id routes', () {
    expect(RouteKey.make('notifications'), 'notifications');
    expect(RouteKey.make('order', 'abc_123-XYZ'), 'order:abc_123-XYZ');
    final parsed = RouteKey.parse('quick-order:u1_00ff');
    expect(parsed?.kind, 'quick-order');
    expect(parsed?.id, 'u1_00ff');
    expect(RouteKey.parse('notifications')?.id, isNull);
    expect(RouteKey.parse('notifications')?.toString(), 'notifications');
  });

  test('rejects unknown kinds, root routes and service locations', () {
    for (final name in ['/', '/s/abc', 'service:quick', 'shell:2', 'store:abc', 'dashboard', '', null]) {
      expect(RouteKey.parse(name), isNull, reason: '$name');
    }
  });

  test('rejects ids that could carry personal data or break the format', () {
    expect(RouteKey.make('order', ''), isNull);
    // أرقام طويلة بشكل رقم تليفون ما تتحطش في اسم مسار.
    expect(RouteKey.make('order', '01012345678'), isNull);
    expect(RouteKey.make('order', '201012345678'), isNull);
    // معرّف مستند عادي فيه حروف وأرقام مسموح.
    expect(RouteKey.make('order', 'a01012345678'), isNotNull);
    for (final id in [
      'أحمد محمد',
      'a b',
      'a|b',
      'a,b',
      'a;b',
      'a=b',
      'a/b',
      'a:b',
      'x@y.com',
      '+201012345678',
      'شارع التحرير 5',
      'a' * 129,
    ]) {
      expect(RouteKey.make('order', id), isNull, reason: id);
      expect(RouteKey.parse('order:$id'), isNull, reason: id);
    }
  });

  test('id kinds need an id and plain kinds must not carry one', () {
    expect(RouteKey.make('order'), isNull);
    expect(RouteKey.make('notifications', 'x'), isNull);
    expect(RouteKey.parse('order'), isNull);
    expect(RouteKey.parse('notifications:x'), isNull);
    expect(RouteKey.order('abc'), 'order:abc');
    expect(RouteKey.order('أ ب'), isNull);
    expect(RouteKey.quickOrder('q1'), 'quick-order:q1');
    expect(RouteKey.courierQuick('c1'), 'courier-quick:c1');
  });

  test('every built-in constant is a valid plain route', () {
    for (final name in [
      RouteKey.notifications,
      RouteKey.stores,
      RouteKey.checkout,
      RouteKey.quickOrders,
      RouteKey.courierQuickOrders,
      RouteKey.adminInbox,
      RouteKey.adminTools,
    ]) {
      expect(RouteKey.parse(name), isNotNull, reason: name);
    }
  });

  test('finished order statuses are never restored', () {
    expect(RouteKey.isFinalStatus('delivered'), isTrue);
    expect(RouteKey.isFinalStatus('cancelled'), isTrue);
    expect(RouteKey.isFinalStatus('canceled'), isTrue);
    expect(RouteKey.isFinalStatus('open'), isFalse);
    expect(RouteKey.isFinalStatus('on_the_way'), isFalse);
    expect(RouteKey.isFinalStatus(null), isFalse);
  });
}
