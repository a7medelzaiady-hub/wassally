import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../widgets/app_header.dart';

/// من نحن
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget point(IconData i, String t, String d) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kPrimarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(i, color: kPrimary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  d,
                  style: TextStyle(fontSize: 13, height: 1.5, color: kMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: kBg,
      body: Column(
        children: [
          const InnerHeader(title: 'من نحن'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: Brand.headerGradient,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        'وصلي',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'كل محلات مدينتك في تطبيق واحد، وبيوصلك لحد باب البيت.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                point(
                  Icons.local_mall_outlined,
                  'اطلب من محلاتك المفضلة',
                  'مطاعم، سوبر ماركت، وورد ومحلات متنوعة في مكان واحد.',
                ),
                point(
                  Icons.delivery_dining_outlined,
                  'توصيل سريع',
                  'مناديب بيستلموا طلبك من المحل ويوصلوه لحد عندك.',
                ),
                point(
                  Icons.support_agent_outlined,
                  'دعم مباشر',
                  'لو عندك أي مشكلة كلمنا من التطبيق وهنرد عليك.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// وسائل التواصل الخارجية من إعدادات الاتصال، بدون مستمع Firestore مستمر.

/// Opens WhatsApp directly for support or complaints.
/// The fallback number is temporary and can be changed by an admin.
/// رقم واتساب الدعم الافتراضي لو app_info/contact مش متظبط أو مش متاح.
const String kDefaultSupportWhatsApp = '01000197222';

/// بيحوّل رقم مصري (01xxxxxxxxx أو +20...) لصيغة wa.me الدولية (20xxxxxxxxxx).
/// لو فاضي بيرجع الرقم الافتراضي.
String normalizeWhatsAppNumber(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) digits = kDefaultSupportWhatsApp;
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('0')) digits = '20${digits.substring(1)}';
  return digits;
}

Future<void> openWasallyWhatsApp(String message) async {
  var number = normalizeWhatsAppNumber('');
  try {
    final doc = await FirebaseFirestore.instance
        .collection('app_info').doc('contact').get();
    number = normalizeWhatsAppNumber((doc.data()?['whatsapp'] ?? '').toString());
  } catch (_) {
    // Fall back to the default number if offline.
  }
  final uri = Uri.https('wa.me', '/$number', {'text': message});
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!opened) {
    NotificationService.messengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('تعذر فتح واتساب. تأكد إنه متثبّت على جهازك.')),
    );
  }
}

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData i, String t, String sub, VoidCallback onTap) =>
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kLine),
          ),
          child: ListTile(
            onTap: onTap,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kPrimarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(i, color: kPrimary, size: 22),
            ),
            title: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: sub.isEmpty
                ? null
                : Directionality(
                    textDirection: TextDirection.ltr,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(sub),
                    ),
                  ),
            trailing: const Icon(Icons.chevron_left),
          ),
        );

    return Scaffold(
      backgroundColor: kBg,
      body: Column(
        children: [
          const InnerHeader(title: 'تواصل معنا'),
          Expanded(
            child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('app_info')
                  .doc('contact')
                  .get(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                // لو المستند مش موجود أو القراءة فشلت، واتساب بيظهر بالرقم الافتراضي
                // بدل ما الصفحة تبقى فاضية.
                final m = snap.data?.data() ?? const <String, dynamic>{};
                final phone = (m['phone'] ?? '').toString().trim();
                final waRaw = (m['whatsapp'] ?? '').toString().trim();
                final wa = waRaw.isEmpty ? kDefaultSupportWhatsApp : waRaw;
                final mail = (m['email'] ?? '').toString().trim();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    tile(
                      Icons.message_outlined,
                      'الدعم والشكاوى عبر واتساب',
                      wa,
                      () => _open('https://wa.me/${normalizeWhatsAppNumber(wa)}'),
                    ),
                    if (phone.isNotEmpty)
                      tile(
                        Icons.call_outlined,
                        'اتصل بينا',
                        phone,
                        () => _open('tel:$phone'),
                      ),
                    if (mail.isNotEmpty)
                      tile(
                        Icons.mail_outline,
                        'الإيميل',
                        mail,
                        () => _open('mailto:$mail'),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
