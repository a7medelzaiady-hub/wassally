import 'dart:io';

import 'package:city_store/services/image_cache.dart';
import 'package:city_store/utils/img.dart';
import 'package:city_store/widgets/app_image.dart';
import 'package:city_store/widgets/cached_net_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// جذر المشروع (أقرب مجلد فيه pubspec.yaml)، فالاختبار ما يتوقفش على مكان تشغيله.
File _repoFile(String relative) {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) {
      return File('${dir.path}/$relative');
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return File(relative);
}

void main() {
  test('حدود كاش الصور: عدد ملفات ومدة صلاحية محدودين', () {
    expect(WasallyImageCache.maxObjects, lessThanOrEqualTo(200));
    expect(WasallyImageCache.stalePeriod, lessThanOrEqualTo(const Duration(days: 14)));
  });

  test('thumb بيصغّر صور Cloudinary فقط ويسيب غيرها زي ما هي', () {
    const c = 'https://res.cloudinary.com/demo/image/upload/v1/a.jpg';
    expect(thumb(c, w: 300), contains('w_300,c_limit,q_auto,f_auto'));
    const other = 'https://example.com/a.jpg';
    expect(thumb(other, w: 300), other);
  });

  testWidgets('CachedNetImage: رابط فاضي يظهر البديل بدون أي طلب شبكة', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CachedNetImage(url: '', errorWidget: Text('fallback')),
    ));
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('AppImage: رابط فاضي يظهر أيقونة البديل', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AppImage(
        url: '',
        fallbackIcon: Icons.store,
        color: Colors.green,
        width: 48,
        height: 48,
      ),
    ));
    expect(find.byIcon(Icons.store), findsOneWidget);
  });

  test('الصور الخاصة (مرفقات الطلبات) ما بتستخدمش كاش القرص', () {
    // هذه الشاشات تعرض صور خاصة بالمستخدم/الطلب: لازم تفضل Image.network عادي.
    // لو الملف اتنقل أو اتغير اسمه الاختبار يفشل صراحةً بدل ما يعدّي من غير فحص.
    const privateScreens = [
      'lib/screens/cart_page.dart',
      'lib/screens/order_details_page.dart',
      'lib/screens/courier_orders_page.dart',
      'lib/screens/join_request_page.dart',
    ];
    for (final f in privateScreens) {
      final file = _repoFile(f);
      expect(file.existsSync(), isTrue, reason: '$f is missing: update this privacy test');
      final src = file.readAsStringSync();
      expect(src.contains('Image.network('), isTrue, reason: '$f must keep plain Image.network');
      expect(src.contains('CachedNetImage'), isFalse, reason: '$f must not cache private images');
      expect(src.contains('AppImage('), isFalse, reason: '$f must not cache private images');
      expect(src.contains('cached_network_image'), isFalse, reason: '$f must not cache private images');
    }
  });

  test('صورة الدخول محلية وليست رابط خارجي', () {
    final src = _repoFile('lib/screens/login_screen.dart').readAsStringSync();
    expect(src.contains('unsplash'), isFalse);
    expect(src.contains("assets/images/login_bg.webp"), isTrue);
    expect(_repoFile('assets/images/login_bg.webp').existsSync(), isTrue);
  });
}
