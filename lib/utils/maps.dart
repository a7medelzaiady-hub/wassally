import 'package:url_launcher/url_launcher.dart';

/// بيفتح العنوان في تطبيق الخرائط. بيرجع false لو معرفش يفتحه.
Future<bool> openInMaps(String address) async {
  final q = address.trim();
  if (q.isEmpty) return false;
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
