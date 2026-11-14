import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/models/product_offer.dart';

void main() {
  group('ProductOffer.percentage', () {
    test('يحسب سعر الخصم ويحفظ السعر الأصلي', () {
      final offer = ProductOffer.percentage(
        originalPrice: 100,
        percentage: 25,
      );

      expect(offer.type, ProductOfferType.percentage);
      expect(offer.originalPrice, 100);
      expect(offer.offerPrice, 75);
      expect(offer.effectivePrice, 75);
      expect(offer.savings, 25);
      expect(offer.calculatedPercentage, 25);
      expect(offer.restoredPrice, 100);
    });

    test('يرفض النسبة غير الصالحة', () {
      expect(
        () => ProductOffer.percentage(originalPrice: 100, percentage: 100),
        throwsArgumentError,
      );
      expect(
        () => ProductOffer.percentage(originalPrice: 100, percentage: 0),
        throwsArgumentError,
      );
    });
  });

  group('ProductOffer.fixedPrice', () {
    test('يقبل سعرًا جديدًا ويحفظ السعر السابق للاستعادة', () {
      final offer = ProductOffer.fixedPrice(
        originalPrice: 125,
        offerPrice: 89.5,
      );

      expect(offer.type, ProductOfferType.fixedPrice);
      expect(offer.originalPrice, 125);
      expect(offer.effectivePrice, 89.5);
      expect(offer.savings, 35.5);
      expect(offer.restoredPrice, 125);
    });

    test('يرفض سعر عرض يساوي أو يتجاوز السعر الأصلي', () {
      expect(
        () => ProductOffer.fixedPrice(originalPrice: 100, offerPrice: 100),
        throwsArgumentError,
      );
      expect(
        () => ProductOffer.fixedPrice(originalPrice: 100, offerPrice: 110),
        throwsArgumentError,
      );
    });
  });

  group('ProductOffer.text', () {
    test('يحتفظ بسعر الوحدة ويقبل عرضًا وصفيًا', () {
      final offer = ProductOffer.text(
        originalPrice: 30,
        description: '  2 + 1 مجانًا  ',
      );

      expect(offer.type, ProductOfferType.text);
      expect(offer.description, '2 + 1 مجانًا');
      expect(offer.originalPrice, 30);
      expect(offer.effectivePrice, 30);
      expect(offer.savings, 0);
      expect(offer.calculatedPercentage, isNull);
      expect(offer.changesUnitPrice, isFalse);
    });

    test('يرفض وصفًا فارغًا أو أطول من الحد', () {
      expect(
        () => ProductOffer.text(originalPrice: 30, description: '   '),
        throwsArgumentError,
      );
      expect(
        () => ProductOffer.text(
          originalPrice: 30,
          description: 'x' * 121,
        ),
        throwsArgumentError,
      );
    });
  });

  test('يرفض الأسعار غير الصالحة', () {
    expect(
      () => ProductOffer.text(originalPrice: 0, description: 'عرض'),
      throwsArgumentError,
    );
    expect(
      () => ProductOffer.fixedPrice(
        originalPrice: double.infinity,
        offerPrice: 5,
      ),
      throwsArgumentError,
    );
  });
}
