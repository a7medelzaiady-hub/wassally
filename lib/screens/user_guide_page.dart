import 'package:flutter/material.dart';

import 'onboarding_page.dart';

import '../theme/brand.dart';

/// Offline help reachable from the Account screen by every signed-in role.
/// This page deliberately does not open Firestore streams or require a login.
class UserGuidePage extends StatelessWidget {
  const UserGuidePage({super.key});

  static const _sections = <_GuideSection>[
    _GuideSection(
      'للعميل',
      Icons.shopping_bag_outlined,
      [
        'من الرئيسية اختار القسم أو تصفّح المحلات والعروض، وبعدها افتح المحل.',
        'السلة تخص محل واحد فقط. لو حبيت تتسوّق من محل تاني، خلّي لكل محل سلته المستقلة.',
        'محتويات سلتك بتفضل محفوظة على نفس الجهاز والحساب لحد ما تفرّغها بنفسك. بعد إرسال طلب ناجح مش هيتبعت نفس الطلب مرتين.',
        'راجع الأصناف والسعر والتوصيل في صفحة التأكيد. لو سعر صنف اتغير هيتطلب منك مراجعة السلة، مش هيتبعت بسعر غير صحيح.',
        'خدمة «وصّلي ع السريع» منفصلة عن سلة المحل؛ اكتب طلبك واتبع خطوات الموافقة على كشف الحساب قبل التسليم.',
      ],
    ),
    _GuideSection(
      'لصاحب المحل',
      Icons.storefront_outlined,
      [
        'قدّم طلب انضمام المحل من «حسابي»، وتابع حالة الطلب لحد ما الإدارة توافق.',
        'بعد تفعيل المحل أضف الأصناف والصور والأسعار والاختيارات من لوحة المحل.',
        'راجع تفاصيل طلب العميل والفاتورة، ثم ابدأ تجهيز الطلب. اضغط «جاهز للاستلام» فقط لما الطلب يكون جاهز.',
        'بيانات اتصال العميل وعنوانه التفصيلي مش متاحة لصاحب المحل؛ المندوب المعيّن هو اللي يقدر يوصل لها أثناء الطلب.',
      ],
    ),
    _GuideSection(
      'للمندوب',
      Icons.delivery_dining_outlined,
      [
        'بعد تفعيل حسابك افتح «طلبات التوصيل». تبويب «المتاحة» للطلبات اللي لسه ما اتعيّنتش لمندوب.',
        'اضغط «استلم الطلب» لتعيين الطلب ليك. استنى تأكيد المحل إن الطلب جاهز قبل ما تبدأ التوصيل.',
        'في «طلباتي» افتح «تفاصيل الطلب» لقراءة الفاتورة. عنوان العميل ورقم تليفونه بيظهروا بس أثناء تعيينك الفعّال.',
        'بعد الوصول للعميل اتبع خطوات التسليم المعروضة في التطبيق. الطلبات السريعة متاحة فقط للمناديب المصرّح لهم.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('دليل استخدام وصّلي')),
          body: ListView(
            key: const Key('user-guide-list'),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
            children: [
              Card(
                color: Brand.palette.primary.withValues(alpha: 0.08),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'كل اللي تحتاج تعرفه عن الطلب والتجهيز والتوصيل في مكان واحد. اختار دورك من الأقسام اللي تحت.',
                    style: TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // إعادة عرض الجولة التعريفية يدويًا.
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  key: const Key('guide-replay-tour'),
                  leading: const Icon(Icons.play_circle_outline_rounded),
                  title: const Text('شاهد الجولة التعريفية',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('3 شاشات سريعة عن مميزات وصّلي'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => const OnboardingPage(),
                  )),
                ),
              ),
              for (final section in _sections)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ExpansionTile(
                    key: Key('guide-${section.title}'),
                    leading: Icon(section.icon, color: Brand.palette.primary),
                    title: Text(section.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    children: [
                      for (final (index, line) in section.steps.indexed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: Brand.palette.primary.withValues(alpha: 0.12),
                                child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(line,
                                    style: const TextStyle(fontSize: 13.5, height: 1.5)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              const Text(
                'لو واجهت مشكلة في طلب قائم، استخدم «تواصل مع الإدارة» من صفحة حسابي.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.5),
              ),
            ],
          ),
        ),
      );
}

class _GuideSection {
  final String title;
  final IconData icon;
  final List<String> steps;

  const _GuideSection(this.title, this.icon, this.steps);
}
