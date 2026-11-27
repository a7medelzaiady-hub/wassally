import 'package:city_store/utils/owner_products_freshness.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 27, 19);

OwnerProductsSource _src({
  bool force = false,
  bool hasCache = true,
  bool tokenReadFailed = false,
  String? serverToken = '100_20',
  String? savedToken = '100_20',
  DateTime? lastFullLoad,
}) =>
    ownerProductsSource(
      force: force,
      hasCache: hasCache,
      tokenReadFailed: tokenReadFailed,
      serverToken: serverToken,
      savedToken: savedToken,
      lastFullLoad: lastFullLoad ?? _now.subtract(const Duration(hours: 1)),
      now: _now,
    );

void main() {
  group('صفحة أصناف صاحب المحل: كاش ولا خادم', () {
    test('القائمة ما اتغيرتش من آخر تحميل: كاش (صفر قراءات للأصناف)', () {
      expect(_src(), OwnerProductsSource.cache);
    });

    test('جهاز تاني عدّل (البصمة اتغيرت): خادم', () {
      expect(_src(serverToken: '200_21'), OwnerProductsSource.server);
    });

    test('مفيش كاش (أول مرة / الكاش اتمسح): خادم', () {
      expect(_src(hasCache: false), OwnerProductsSource.server);
    });

    test('«إعادة المحاولة»: خادم دايمًا', () {
      expect(_src(force: true), OwnerProductsSource.server);
    });

    test('المحل ما عندوش قائمة مجمّعة أو مفيش بصمة متسجلة: خادم (السلوك القديم)', () {
      expect(_src(serverToken: null), OwnerProductsSource.server);
      expect(_src(savedToken: null), OwnerProductsSource.server);
    });

    test('مفيش نت للتأكد والكاش موجود: كاش بدل رسالة خطأ', () {
      expect(_src(tokenReadFailed: true, serverToken: null), OwnerProductsSource.cache);
    });

    test('آخر تحميل كامل أقدم من 24 ساعة: خادم للأمان', () {
      expect(
        _src(lastFullLoad: _now.subtract(const Duration(hours: 25))),
        OwnerProductsSource.server,
      );
      expect(
        ownerProductsSource(
          force: false,
          hasCache: true,
          tokenReadFailed: false,
          serverToken: 'a',
          savedToken: 'a',
          lastFullLoad: null,
          now: _now,
        ),
        OwnerProductsSource.server,
      );
    });

    test('البصمة: وقت التحديث + العدد، وnull لو المستند مش موجود', () {
      expect(menuFreshnessToken(exists: true, updatedAtMs: 100, count: 20), '100_20');
      expect(menuFreshnessToken(exists: true, updatedAtMs: 100, count: 21), isNot('100_20'));
      expect(menuFreshnessToken(exists: false, updatedAtMs: 100, count: 20), isNull);
      expect(menuFreshnessToken(exists: true, updatedAtMs: null, count: 20), isNull);
    });
  });
}
