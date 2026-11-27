import 'package:city_store/services/photo_library.dart';
import 'package:city_store/utils/product_photo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => setProductPhotoLibrary(const {}));

  test('صورة المكتبة قبل الصورة التوضيحية، والأطول الأول', () {
    setProductPhotoLibrary({
      normalizeProductPhotoKey('زيت'): 'https://res.cloudinary.com/x/oil.jpg',
      normalizeProductPhotoKey('زيت موبيل'): 'https://res.cloudinary.com/x/mobil.jpg',
      normalizeProductPhotoKey('طماطم'): 'https://res.cloudinary.com/x/tomato.jpg',
    });
    final t = productPhotoFor(name: 'طماطم بلدي');
    expect(t.url, 'https://res.cloudinary.com/x/tomato.jpg');
    expect(t.fromLibrary, isTrue);
    expect(productPhotoFor(name: 'زيت موبيل 1 لتر').url, 'https://res.cloudinary.com/x/mobil.jpg');
  });

  test('صورة المحل نفسه بتفضل الأساس، واسم مش في المكتبة يرجع للتوضيحية', () {
    setProductPhotoLibrary({normalizeProductPhotoKey('طماطم'): 'https://res.cloudinary.com/x/tomato.jpg'});
    expect(productPhotoFor(name: 'طماطم', uploadedUrl: 'https://shop/own.jpg').url, 'https://shop/own.jpg');
    expect(productPhotoFor(name: 'خيار').fromLibrary, isFalse);
  });

  test('بيانات المستند: روابط https بس', () {
    final m = PhotoLibrary.entriesFrom({
      'photos': {
        'طماطم': {'name': 'طماطم', 'url': 'https://a/t.jpg'},
        'بصل': {'name': 'بصل', 'url': 'http://insecure'},
        'x': 'bad',
      },
    });
    expect(m, {'طماطم': 'https://a/t.jpg'});
  });
}
