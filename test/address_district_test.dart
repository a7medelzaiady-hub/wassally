import 'package:city_store/utils/address_district.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('الحي من أول العنوان', () {
    test('بياخد اسم المنطقة ويسيب الشارع والعمارة والدور', () {
      expect(districtFromAddress('حي السلام شارع 5 عمارة 12 الدور التالت'), 'حي السلام');
      expect(districtFromAddress('المعادي، شارع 9، عمارة 4'), 'المعادي');
      expect(districtFromAddress('مدينة نصر - عباس العقاد'), 'مدينة نصر');
      expect(districtFromAddress('الزقازيق ش الجلاء بجوار المسجد'), 'الزقازيق');
    });

    test('مفيش منطقة لو العنوان بيبدأ برقم أو فاضي', () {
      expect(districtFromAddress('١٢ شارع التحرير'), '');
      expect(districtFromAddress('12 ش التحرير'), '');
      expect(districtFromAddress('   '), '');
    });

    test('بحد أقصى 4 كلمات و40 حرف', () {
      expect(
        districtFromAddress('كفر الشيخ مركز دسوق قرية محلة أبو علي القنطرة'),
        'كفر الشيخ مركز دسوق',
      );
      expect(districtFromAddress('ا' * 80).length, addressDistrictMaxLength);
    });
  });
}
