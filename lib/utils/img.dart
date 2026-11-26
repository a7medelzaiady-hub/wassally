import '../services/data_saver.dart';

/// بيطلب نسخة مصغّرة من صور Cloudinary (أسرع وبتوفّر نت). أي رابط تاني بيرجع زي ما هو.
/// في «وضع توفير الباقة» العرض بيصغر والجودة بتبقى q_auto:eco (راجع [DataSaver]).
/// [saver] للاختبارات بس؛ في التطبيق بيتاخد من اختيار المستخدم.
String thumb(String url, {int w = 400, bool? saver}) {
  const marker = '/image/upload/';
  final i = url.indexOf(marker);
  if (i < 0 || !url.contains('res.cloudinary.com')) return url;
  final rest = url.substring(i + marker.length);
  // لو فيه تحويلات متحطة أصلًا (مثل w_ أو c_) منعدّلش.
  if (rest.startsWith('w_') || rest.startsWith('c_') || rest.startsWith('f_')) {
    return url;
  }
  final width = DataSaver.width(w, saver: saver);
  final q = DataSaver.quality(saver: saver);
  return '${url.substring(0, i + marker.length)}w_$width,c_limit,$q,f_auto/$rest';
}
