/// بيطلب نسخة مصغّرة من صور Cloudinary (أسرع وبتوفّر نت). أي رابط تاني بيرجع زي ما هو.
String thumb(String url, {int w = 400}) {
  const marker = '/image/upload/';
  final i = url.indexOf(marker);
  if (i < 0 || !url.contains('res.cloudinary.com')) return url;
  final rest = url.substring(i + marker.length);
  // لو فيه تحويلات متحطة أصلًا (مثل w_ أو c_) منعدّلش.
  if (rest.startsWith('w_') || rest.startsWith('c_') || rest.startsWith('f_')) {
    return url;
  }
  return '${url.substring(0, i + marker.length)}w_$w,c_limit,q_auto,f_auto/$rest';
}
