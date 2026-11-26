import 'package:url_launcher/url_launcher.dart';

/// بيفتح العنوان في تطبيق الخرائط. بيرجع false لو معرفش يفتحه.
Future<bool> openInMaps(String address) async {
  var q = address.trim();
  if (q.isEmpty) return false;
  // عنوان فيه إحداثيات (من «حدد موقعي») يفتح النقطة بالظبط.
  final coords = mapCoordinatesIn(q);
  if (coords != null) q = coords;
  final uri = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': q,
  });
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// أول «lat, lng» في النص (مثلًا «الموقع: 31.05123, 30.12345»)، أو null.
String? mapCoordinatesIn(String text) {
  final m = RegExp(r'(-?\d{1,2}\.\d{3,}),\s*(-?\d{1,3}\.\d{3,})').firstMatch(text);
  return m == null ? null : '${m.group(1)},${m.group(2)}';
}
