/// استخراج «الحي» من أول العنوان اللي كتبه العميل.
///
/// بيتسجل في `area` في مستند الطلب العام لما مفيش قائمة مناطق توصيل (أو العميل
/// ما اختارش منطقة)، عشان الأدمن والمناديب يشوفوا الوجهة في القايمة.
/// المستند ده بيشوفه صاحب المحل، فبناخد اسم المنطقة بس ونسيب الباقي:
/// بنقف عند أول فاصلة/سطر، أو أول كلمة فيها رقم، أو كلمة زي «شارع/عمارة/دور».
/// نفس المنطق متكرر في الـ Worker (`address_district.ts`) — لازم يفضلوا متطابقين.
library;

const _stopWords = {
  'شارع', 'ش', 'ش.', 'عمارة', 'عماره', 'عمارات', 'برج', 'بلوك', 'دور', 'الدور',
  'شقة', 'شقه', 'رقم', 'منزل', 'بيت', 'بجوار', 'جنب', 'امام', 'أمام', 'قدام',
  'خلف', 'ورا', 'بعد', 'قبل', 'عند', 'فوق', 'تحت', 'مدخل', 'بوابة', 'بوابه',
};

const int addressDistrictMaxLength = 40;
const int _maxWords = 4;

String districtFromAddress(String address) {
  final first = address.trim().split(RegExp(r'[،,؛;\n\-–—/\\|]')).first;
  final words = first.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final kept = <String>[];
  for (final w in words) {
    if (RegExp(r'[0-9٠-٩]').hasMatch(w)) break;
    if (_stopWords.contains(w)) break;
    kept.add(w);
    if (kept.length == _maxWords) break;
  }
  var out = kept.join(' ').trim();
  if (out.length > addressDistrictMaxLength) {
    out = out.substring(0, addressDistrictMaxLength).trim();
  }
  return out;
}
