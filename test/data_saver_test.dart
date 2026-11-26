import 'package:city_store/services/data_saver.dart';
import 'package:city_store/utils/img.dart';
import 'package:city_store/widgets/data_saver_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const c = 'https://res.cloudinary.com/demo/image/upload/v1/a.jpg';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DataSaver.enabled.value = false;
  });

  test('الوضع العادي: نفس الرابط القديم بالظبط', () {
    expect(
      thumb(c, w: 300, saver: false),
      'https://res.cloudinary.com/demo/image/upload/w_300,c_limit,q_auto,f_auto/v1/a.jpg',
    );
  });

  test('توفير الباقة: عرض أصغر وجودة eco', () {
    expect(
      thumb(c, w: 500, saver: true),
      'https://res.cloudinary.com/demo/image/upload/w_300,c_limit,q_auto:eco,f_auto/v1/a.jpg',
    );
  });

  test('توفير الباقة ما يصغّرش الصور الصغيرة أقل من الحد الأدنى', () {
    expect(DataSaver.width(120, saver: true), DataSaver.minWidth);
    expect(DataSaver.width(60, saver: true), 60);
    expect(DataSaver.width(1080, saver: true), 648);
    expect(DataSaver.width(1080, saver: false), 1080);
  });

  test('الروابط اللي مش Cloudinary أو فيها تحويلات بترجع زي ما هي', () {
    const other = 'https://example.com/a.jpg';
    expect(thumb(other, w: 300, saver: true), other);
    const done = 'https://res.cloudinary.com/demo/image/upload/w_100/v1/a.jpg';
    expect(thumb(done, w: 300, saver: true), done);
  });

  test('thumb بياخد الوضع من اختيار المستخدم لو ما اتحددش', () {
    DataSaver.enabled.value = true;
    expect(thumb(c, w: 500), contains('w_300,c_limit,q_auto:eco'));
    DataSaver.enabled.value = false;
    expect(thumb(c, w: 500), contains('w_500,c_limit,q_auto,f_auto'));
  });

  test('الاختيار بيتحفظ على الموبايل ويرجع بعد فتح التطبيق', () async {
    await DataSaver.set(true);
    DataSaver.enabled.value = false;
    await DataSaver.load();
    expect(DataSaver.enabled.value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DataSaver.prefsKey), isTrue);
  });

  testWidgets('مفتاح توفير الباقة بيشغّل ويقفل الوضع', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DataSaverTile()),
    ));
    expect(find.text('توفير الباقة'), findsOneWidget);
    expect(DataSaver.enabled.value, isFalse);

    await tester.tap(find.byKey(const Key('account-data-saver')));
    await tester.pumpAndSettle();
    expect(DataSaver.enabled.value, isTrue);

    await tester.tap(find.byKey(const Key('account-data-saver')));
    await tester.pumpAndSettle();
    expect(DataSaver.enabled.value, isFalse);
  });
}
