import 'package:city_store/utils/shop_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Egyptian local product search', () {
    test('ignores Arabic diacritics, ta marbuta, punctuation and al prefix', () {
      expect(matchesShopSearch('الجُبْنَة الرومي', 'جبنه'), isTrue);
      expect(matchesShopSearch('أرز مصري 1 كيلو', 'رز'), isTrue);
      expect(matchesShopSearch('الطماطم البلدي', 'طماطم'), isTrue);
      expect(matchesShopSearch('مكرونة بشاميل', 'المكرونة'), isTrue);
      expect(matchesShopSearch('فول - مدمس', 'فول مدمس'), isTrue);
    });

    test('matches common product aliases without cloud calls', () {
      expect(matchesShopSearch('بيبسي 1 لتر', 'كولا'), isTrue);
      expect(matchesShopSearch('شيبس كبير', 'شيبسي'), isTrue);
      expect(matchesShopSearch('حليب 1 لتر', 'لبن'), isTrue);
      expect(matchesShopSearch('ساندوتش طعمية', 'سندوتش فلافل'), isTrue);
    });

    test('all search words must match and unrelated products stay hidden', () {
      expect(matchesShopSearch('جبنة رومي 500 جرام', 'جبنة رومي'), isTrue);
      expect(matchesShopSearch('جبنة رومي', 'جبنة شيدر'), isFalse);
      expect(matchesShopSearch('شاي أخضر', 'زيت'), isFalse);
      expect(matchesShopSearch('بيتزا مارجريتا', ''), isTrue);
    });
  });
}
