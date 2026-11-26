import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/utils/product_photo.dart';

void main() {
  group('illustrative product photos', () {
    test('uploaded store photo always has priority, even with automotive name', () {
      final photo = productPhotoFor(
        name: 'زيت موتور بترومين 20 لتر',
        uploadedUrl: ' https://cdn.example.com/real.jpg ',
        storeCategory: 'قطع غيار',
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

    test('specific Egyptian supermarket products have relevant photo groups', () {
      final cases = <String, String>{
        'لبن جهينة 1 لتر': 'photo-1550583724-b2692b85b150',
        'حليب كامل الدسم': 'photo-1550583724-b2692b85b150',
        'جبنة رومي': 'photo-1486297678162-eb2a19b0a32d',
        'بيض بلدي 30 بيضة': 'photo-1506976785307-8732e854ad03',
        'رز بسمتي 5 كيلو': 'photo-1586201375761-83865001e31c',
        'أرز مصري': 'photo-1586201375761-83865001e31c',
        'زيت عافية 1 لتر': 'photo-1604908177225-45c3d5f3c7c1',
        'قهوة تركي': 'photo-1495474472287-4d71bcdd2085',
        'شاي العروسة 40 فتلة': 'photo-1544787219-7f47ccb76574',
        'بيبسي 2 لتر': 'photo-1581636625402-29b2a704ef13',
        'شيبسي جبنة': 'photo-1566478989037-eec170784d0b',
        'بسكويت سادة': 'photo-1499636136210-6f4ee915583e',
        'عسل نحل': 'photo-1587049352851-8d4e89133924',
        'سكر ابيض 1 كيلو': 'photo-1769259397222-33e425659c43',
        'دقيق فاخر': 'photo-1714842981153-ffeaf74e7a1a',
      };
      for (final entry in cases.entries) {
        final result = productPhotoFor(name: entry.key);
        expect(result.matchedName, isTrue, reason: entry.key);
        expect(result.url, contains(entry.value), reason: entry.key);
      }
    });

    test('produce matching uses the actual produce type, not one icon', () {
      final names = <String, String>{
        'طماطم بلدي': 'photo-1582284540020-8acbe03f4924',
        'بطاطس 3 كيلو': 'photo-1518977676601-b53f82aba655',
        'بصل ابيض': 'photo-1508747703725-719777637510',
        'تفاح احمر': 'photo-1560806887-1e4cd0b6cbd6',
        'موز بلدي': 'photo-1571771894821-ce9b6c11b08e',
        'برتقال عصير': 'photo-1547514701-42782101795e',
      };
      for (final entry in names.entries) {
        expect(productPhotoFor(name: entry.key).url,
            contains(entry.value), reason: entry.key);
      }
    });

    test('the leading product noun wins over a flavor or ingredient', () {
      expect(productPhotoFor(name: 'شيبسي جبنة').url,
          contains('photo-1566478989037-eec170784d0b'));
      expect(productPhotoFor(name: 'شاي بلبن').url,
          contains('photo-1544787219-7f47ccb76574'));
      expect(productPhotoFor(name: 'بسكويت شوكولاتة').url,
          contains('photo-1499636136210-6f4ee915583e'));
      expect(productPhotoFor(name: 'عصير برتقال').url,
          contains('photo-1613478223719-2ab802602423'));
      expect(productPhotoFor(name: 'برتقال عصير').url,
          contains('photo-1547514701-42782101795e'));
    });

    test('specific descriptions win over general product keywords', () {
      final fries = productPhotoFor(name: 'بطاطس مقلية');
      final potato = productPhotoFor(name: 'بطاطس نيّة');
      expect(fries.url, isNot(equals(potato.url)));

      final sandwich = productPhotoFor(name: 'ساندوتش بطاطس');
      expect(sandwich.url, isNot(equals(potato.url)));

      final hairOil = productPhotoFor(name: 'زيت شعر');
      final cookingOil = productPhotoFor(name: 'زيت طعام');
      expect(hairOil.url, isNot(equals(cookingOil.url)));

      final motorOil = productPhotoFor(name: 'زيت محرك');
      expect(motorOil.url, isNot(equals(cookingOil.url)));
      expect(productPhotoFor(name: 'زيت بترومين 50 20 لتر').url,
          motorOil.url);
    });

    test('automotive store resolves ambiguous oil as motor oil', () {
      final food = productPhotoFor(name: 'زيت 1 لتر', storeCategory: 'بقالة');
      final motor = productPhotoFor(name: 'زيت 1 لتر', storeCategory: 'قطع غيار سيارات');
      expect(food.matchedName, isTrue);
      expect(motor.matchedName, isTrue);
      expect(motor.url, isNot(equals(food.url)));
    });

    test('cleaning, grooming and shop supplies do not use food pictures', () {
      final cases = <String, String>{
        'برسيل 3 كيلو': 'photo-1643107303813-077f2061cec1',
        'سائل مواعين فيري': 'photo-1643107303813-077f2061cec1',
        'شامبو للشعر': 'photo-1608248543803-ba4f8c70ae0b',
        'معجون اسنان': 'photo-1608248543803-ba4f8c70ae0b',
        'قلم جاف ازرق': 'photo-1455390582262-044cdead277a',
        'كابل شحن': 'photo-1511707171634-5f897ff02aa9',
        'سمك بلطي': 'photo-1572419324726-bdb79b8b3ad3',
        'مناديل ورق': 'photo-1618034229737-cb68d1277aa1',
        'حفاضات اطفال': 'photo-1734599406023-80b2212b713b',
      };
      for (final entry in cases.entries) {
        expect(productPhotoFor(name: entry.key).url, contains(entry.value),
            reason: entry.key);
      }
    });

    test('Arabic diacritics and punctuation do not break known names', () {
      expect(productPhotoFor(name: 'اللبن كامل الدسم').url,
          productPhotoFor(name: 'لبن كامل الدسم').url);
      expect(productPhotoFor(name: 'الزيت 1 لتر').url,
          productPhotoFor(name: 'زيت 1 لتر').url);
      final a = productPhotoFor(name: 'طَمَاطِم، بلدي!');
      final b = productPhotoFor(name: 'طماطم بلدي');
      expect(a.url, b.url);
      expect(a.matchedName, isTrue);
    });

    test('whole-word matching avoids accidental substring associations', () {
      final unrelated = productPhotoFor(name: 'مورد جديد');
      final unrelated2 = productPhotoFor(name: 'ارزاق جديدة');
      final flowers = productPhotoFor(name: 'ورد احمر');
      final rice = productPhotoFor(name: 'رز مصري');
      expect(unrelated.url, isNot(equals(flowers.url)));
      expect(unrelated2.url, isNot(equals(rice.url)));
      expect(unrelated.matchedName, isFalse);
      expect(unrelated2.matchedName, isFalse);
    });

    test('unknown item uses store category without database/network lookup', () {
      final restaurant = productPhotoFor(
        name: 'صنف الموسم الجديد',
        storeCategory: 'مطاعم',
      );
      final bakery = productPhotoFor(
        name: 'منتج جديد',
        storeCategory: 'مخبوزات وحلويات',
      );
      final cleaner = productPhotoFor(
        name: 'نوع جديد غير مصنف',
        storeCategory: 'منظفات',
      );
      expect(restaurant.matchedName, isFalse);
      expect(bakery.matchedName, isFalse);
      expect(cleaner.matchedName, isFalse);
      expect(restaurant.url, isNot(bakery.url));
      expect(bakery.url, isNot(cleaner.url));
    });

    test('unknown category has a fixed small real photo, not search API', () {
      final photo = productPhotoFor(name: 'اسم جديد غير معروف');
      final second = productPhotoFor(name: 'اسم جديد غير معروف');
      expect(photo.url, startsWith('https://images.unsplash.com/'));
      expect(photo.url, second.url);
      expect(photo.url, contains('w=320'));
      expect(photo.url, contains('q=65'));
      expect(photo.matchedName, isFalse);
    });

    test('known image URLs are shared for variants to benefit disk cache', () {
      expect(productPhotoFor(name: 'ارز مصري 1 كيلو').url,
          productPhotoFor(name: 'رز بسمتي 5 كيلو').url);
      expect(productPhotoFor(name: 'زيت طعام 1 لتر').url,
          productPhotoFor(name: 'زيت عافية 2 لتر').url);
    });

    test('different specific foods keep different illustrative photos', () {
      final pizza = productPhotoFor(name: 'بيتزا مارجريتا');
      final burger = productPhotoFor(name: 'برجر لحم');
      final chips = productPhotoFor(name: 'بطاطس مقلية');
      expect(pizza.url, isNot(burger.url));
      expect(burger.url, isNot(chips.url));
      expect(chips.matchedName, isTrue);
    });
  });
}
