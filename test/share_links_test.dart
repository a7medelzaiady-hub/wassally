import 'package:city_store/utils/share_links.dart';
import 'package:city_store/widgets/share_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  test('رابط جوجل بلاي فيه اسم الحزمة ومعرّف المحل في referrer', () {
    final link = Uri.parse(ShareLinks.playLink(storeId: 's123'));
    expect(link.host, 'play.google.com');
    expect(link.queryParameters['id'], 'com.wassally.app');
    expect(link.queryParameters['referrer'], 'utm_source=share&utm_content=store_s123');
  });

  test('من غير محل: رابط التطبيق بس', () {
    final link = Uri.parse(ShareLinks.playLink());
    expect(link.queryParameters.containsKey('referrer'), isFalse);
  });

  test('رسالة مشاركة المحل', () {
    final msg = ShareLinks.storeMessage(storeName: 'بقالة الحاج سيد', storeId: 's1');
    expect(msg, contains('محل بقالة الحاج سيد'));
    expect(msg, contains('وصّلي'));
    expect(msg, contains('play.google.com'));
  });

  test('رسالة مشاركة الصنف بالسعر والعرض', () {
    final msg = ShareLinks.productMessage(
      productName: 'زيت عافية',
      price: 85,
      oldPrice: 95,
      storeName: 'بقالة الحاج سيد',
      storeId: 's1',
    );
    expect(msg, startsWith('زيت عافية بـ 85 ج.م بدل 95 ج.م من بقالة الحاج سيد'));
    final noOffer = ShareLinks.productMessage(
      productName: 'سكر',
      price: 35,
      storeName: '',
      storeId: '',
    );
    expect(noOffer, startsWith('سكر بـ 35 ج.م على تطبيق وصّلي'));
  });

  testWidgets('كود QR بيعرض اسم المحل والرابط', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StoreQrSheet(storeName: 'بقالة الحاج سيد', storeId: 's1'),
      ),
    ));
    expect(find.text('بقالة الحاج سيد'), findsOneWidget);
    final qr = tester.widget<QrImageView>(find.byKey(const Key('store-qr')));
    expect(qr, isNotNull);
    expect(find.byKey(const Key('store-qr-share')), findsOneWidget);
  });
}
