import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/utils/product_photo.dart';

void main() {
  group('illustrative product photos', () {
    test('uploaded store photo always has priority', () {
      final photo = productPhotoFor(
        name: 'ساندوتش بطاطس',
        uploadedUrl: 'https://cdn.example.com/real.jpg',
        storeCategory: 'مطاعم',
      );
      expect(photo.url, 'https://cdn.example.com/real.jpg');
      expect(photo.matchedName, isFalse);
    });

    test('Arabic spelling variants and sandwich names match photos', () {
      final sandwich = productPhotoFor(name: 'ساندوتش باذنجان');
      final alternate = productPhotoFor(name: 'سندوتش بطاطس');
      final moussaka = productPhotoFor(name: 'طبق مَسَقَّعة');
      expect(sandwich.matchedName, isTrue);
      expect(alternate.matchedName, isTrue);
      expect(moussaka.matchedName, isTrue);
      expect(sandwich.url, isNot(equals(moussaka.url)));
    });

    test('different product keywords get different illustrations', () {
      final pizza = productPhotoFor(name: 'بيتزا مارجريتا');
      final burger = productPhotoFor(name: 'برجر لحم');
      final chips = productPhotoFor(name: 'بطاطس مقلية');
      expect(pizza.url, isNot(burger.url));
      expect(burger.url, isNot(chips.url));
      expect(chips.matchedName, isTrue);
    });

    test('unknown product uses its store category without a database read', () {
      final restaurant = productPhotoFor(
        name: 'طبق الموسم الجديد',
        storeCategory: 'مطاعم',
      );
      final bakery = productPhotoFor(
        name: 'منتج جديد',
        storeCategory: 'مخبوزات وحلويات',
      );
      expect(restaurant.url, startsWith('https://'));
      expect(restaurant.matchedName, isFalse);
      expect(bakery.url, isNot(restaurant.url));
    });

    test('unknown category has a generic real photo', () {
      final photo = productPhotoFor(name: 'اسم جديد غير معروف');
      expect(photo.url, startsWith('https://images.unsplash.com/'));
      expect(photo.matchedName, isFalse);
    });
  });
}
