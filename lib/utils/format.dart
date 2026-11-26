/// تنسيق السعر: 35 ج.م أو 12.5 ج.م
String formatPrice(num value) {
  final v = value.toDouble();
  final text = v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(1);
  return '$text ج.م';
}

/// تنسيق التاريخ: 03/11/2026 - 4:05 م
String formatDateTime(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  final isPm = d.hour >= 12;
  var hour = d.hour % 12;
  if (hour == 0) hour = 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '$day/$month/${d.year} - $hour:$minute ${isPm ? 'م' : 'ص'}';
}

/// رقم الطلب المختصر من معرّف المستند.
String shortOrderId(String id) {
  final clean = id.length <= 5 ? id : id.substring(0, 5);
  return '#${clean.toUpperCase()}';
}

/// رقم الطلب البسيط (6 أرقام) اللي العميل والمندوب بيتكلموا بيه.
/// ثابت لكل طلب ومحسوب من معرّف المستند (من غير أي قراءة).
String simpleOrderNumber(String id) {
  var number = 0;
  for (final unit in id.codeUnits) {
    number = (number * 131 + unit) % 900000;
  }
  return (100000 + number).toString();
}

/// يتأكد إن الرقم موبايل مصري صحيح (01xxxxxxxxx).
bool isValidEgyptianMobile(String input) {
  final digits = input.replaceAll(RegExp(r'[\s\-]'), '');
  return RegExp(r'^01[0125]\d{8}$').hasMatch(digits);
}
