import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/seed_stores.dart';
import '../legal/legal_content.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/role_request_service.dart';
import '../services/role_service.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/dialogs.dart';
import '../widgets/theme_picker.dart';
import 'join_request_page.dart';
import 'admin_join_requests_page.dart';
import 'info_pages.dart';
import 'support_chat_page.dart';
import 'my_complaints_page.dart';
import 'legal_page.dart';

// تأكد أن اسم الملف والـ class (LoginScreen) مطابقين عندك.

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  // اشتراك واحد في بيانات المستخدم يغذّي كل الأقسام. الـ Stream أحادي الاشتراك،
  // فاستخدامه في أكتر من StreamBuilder كان بيرمي "Stream has already been listened to".
  UserProfile _profileData = const UserProfile();
  StreamSubscription<UserProfile>? _profileSub;

  @override
  void initState() {
    super.initState();
    _profileSub = UserService.watch().listen(
      (p) {
        if (mounted) setState(() => _profileData = p);
      },
      onError: (Object e) => debugPrint('Profile stream error: $e'),
    );
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }

  BoxDecoration get _card => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: kLine),
  );

  // مراقبة حالة الجلسة لحظياً وتأكيد الصلاحية
  Stream<bool> _adminStream() async* {
    await for (final user in FirebaseAuth.instance.authStateChanges()) {
      if (user == null) {
        yield false;
      } else {
        yield await UserService.isAdmin();
      }
    }
  }

  Future<void> _seed() async {
    try {
      final n = await seedDemoStores();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تم رفع $n محلات تجريبية')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل الرفع. تأكد إن حسابك أدمن.')),
      );
    }
  }

  void _openJoin(JoinType type, UserProfile profile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JoinRequestPage(
          type: type,
          initialName: profile.name.isNotEmpty
              ? profile.name
              : FirebaseAuth.instance.currentUser?.displayName ?? '',
          initialPhone: profile.phone,
        ),
      ),
    );
  }

  /// قسم "انضم إلينا": للعميل العادي بس (الأدمن والمندوب وصاحب المحل مش محتاجينه).
  Widget _joinSection(UserProfile profile) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final role = RoleService.cachedFor(uid)?.role;
    if (role != null && role != AppRole.customer) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: RoleRequestService.watchMine(),
      builder: (context, snap) {
        final requests = <String, Map<String, dynamic>>{
          for (final d in snap.data ?? const [])
            (d.data()['type'] ?? '').toString(): d.data(),
        };
        final status = <String, String>{
          for (final entry in requests.entries)
            entry.key: (entry.value['status'] ?? '').toString(),
        };
        Widget tile(JoinType t, IconData icon, String subtitle) {
          final st = status[t.key];
          final pending = st == 'pending';
          final approved = st == 'approved';
          final rejectionReason = (requests[t.key]?['adminNote'] ?? '').toString().trim();
          return ListTile(
            enabled: !pending && !approved,
            onTap: () => _openJoin(t, profile),
            leading: Icon(icon, color: kPrimary),
            title: Text('انضم كـ ${t.label}'),
            subtitle: Text(
              pending
                  ? 'طلبك قيد المراجعة'
                  : approved
                  ? 'تم قبول طلبك. اقفل التطبيق وافتحه تاني'
                  : st == 'rejected'
                  ? 'طلبك اترفض. السبب: ${rejectionReason.isEmpty ? 'راجع الإدارة لمعرفة السبب' : rejectionReason}. تقدر تقدّم تاني'
                  : subtitle,
            ),
            trailing: const Icon(Icons.chevron_left),
          );
        }

        return Container(
          margin: const EdgeInsets.only(top: 12),
          decoration: _card,
          child: Column(
            children: [
              tile(
                JoinType.storeOwner,
                Icons.storefront_outlined,
                'سجّل محلك وأدير طلباتك وأصنافك',
              ),
              const Divider(height: 1),
              tile(
                JoinType.courier,
                Icons.two_wheeler,
                'وصّل الطلبات واكسب عمولة',
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _signOut() async {
    final ok = await confirmDialog(
      context,
      title: 'تسجيل الخروج',
      message: 'هتخرج من حسابك. تقدر ترجع تسجّل دخول في أي وقت.',
      confirmLabel: 'تسجيل الخروج',
      destructive: true,
    );

    if (!ok || !mounted) return;

    // نمسك الـ navigator قبل أي await.
    final navigator = Navigator.of(context, rootNavigator: true);

    try {
      // لو فشل AuthService (مثلاً تسجيل خروج جوجل) نكمل برضه.
      try {
        await AuthService.signOut();
      } catch (e) {
        debugPrint('AuthService.signOut error: $e');
      }

      await FirebaseAuth.instance.signOut();

      // نرجع للبوابة (AuthGate): هي اللي بتعرض شاشة الدخول وبعد الدخول بتفتح التطبيق.
      navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      debugPrint('Sign out error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تسجيل الخروج. حاول مرة أخرى.')),
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await confirmDialog(
      context,
      title: 'متأكد؟',
      message: 'الحذف نهائي ومينفعش يترجع.',
      confirmLabel: 'حذف حسابي',
      destructive: true,
    );
    if (!ok || !mounted) return;

    try {
      await AuthService.deleteAccount(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final cancelled =
          e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request' ||
          e.code == 'web-context-canceled' ||
          e.code == 'canceled';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cancelled
                ? 'اتلغى حذف الحساب'
                : 'تعذر حذف الحساب (${e.code}). جرّب تاني.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Bad state: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? 'تعذر حذف الحساب. جرّب تاني.' : message),
        ),
      );
    }
  }

  void _editProfile(UserProfile current) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditProfileSheet(initial: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final user = FirebaseAuth.instance.currentUser;
    final name = (user?.displayName ?? '').isEmpty
        ? 'مستخدم وصلي'
        : user!.displayName!;

    return Column(
      children: [
        AppHeader(
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: kPrimarySoft,
                foregroundImage: user?.photoURL != null
                    ? NetworkImage(user!.photoURL!)
                    : null,
                child: Icon(Icons.person, color: kPrimary, size: 34),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if ((user?.email ?? '').isNotEmpty)
                      Text(
                        user!.email!,
                        style: text.bodySmall?.copyWith(color: kMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Builder(
                builder: (context) {
                  final profile = _profileData;
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: _card,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'بيانات التوصيل',
                                style: text.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _editProfile(profile),
                              child: const Text('تعديل'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _InfoRow(
                          icon: Icons.phone_outlined,
                          value: profile.phone,
                          empty: 'مفيش رقم موبايل محفوظ',
                        ),
                        const SizedBox(height: 10),
                        _InfoRow(
                          icon: Icons.location_on_outlined,
                          value: profile.address,
                          empty: 'مفيش عنوان محفوظ',
                        ),
                      ],
                    ),
                  );
                },
              ),
              _joinSection(_profileData),
              Container(
                margin: const EdgeInsets.only(top: 12),
                decoration: _card,
                child: ListTile(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SupportChatPage()),
                  ),
                  leading: Icon(Icons.support_agent_outlined, color: kPrimary),
                  title: const Text(
                    'تواصل مع الإدارة',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('اكتب لنا مباشرة وهنرد عليك'),
                  trailing: const Icon(Icons.chevron_left),
                ),
              ),
              const ThemePickerCard(),
              Container(
                margin: const EdgeInsets.only(top: 12),
                decoration: _card,
                child: Column(
                  children: [
                    ListTile(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AboutPage()),
                      ),
                      leading: Icon(
                        Icons.info_outline_rounded,
                        color: kPrimary,
                      ),
                      title: const Text('من نحن'),
                      trailing: const Icon(Icons.chevron_left),
                    ),
                    Divider(height: 1, color: kLine),
                    ListTile(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ContactPage()),
                      ),
                      leading: Icon(
                        Icons.headset_mic_outlined,
                        color: kPrimary,
                      ),
                      title: const Text('تواصل معنا'),
                      trailing: const Icon(Icons.chevron_left),
                    ),
                  ],
                ),
              ),
              StreamBuilder<bool>(
                stream: _adminStream(),
                builder: (context, snapshot) {
                  if (snapshot.data != true) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(top: 12),
                    decoration: _card,
                    child: Column(
                      children: [
                        ListTile(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AdminJoinRequestsPage()),
                          ),
                          leading: Icon(Icons.assignment_turned_in_outlined, color: kPrimary),
                          title: const Text('طلبات الانضمام'),
                          subtitle: const Text('مراجعة طلبات المحلات والمناديب وقبولها أو رفضها'),
                          trailing: const Icon(Icons.chevron_left),
                        ),
                        Divider(height: 1, color: kLine),
                        ListTile(
                          onTap: _seed,
                      leading: Icon(
                        Icons.cloud_upload_outlined,
                        color: kPrimary,
                      ),
                      title: const Text(
                        'رفع المحلات التجريبية',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                          subtitle: const Text('للأدمن فقط'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Container(
                decoration: _card,
                child: Column(
                  children: [
                    ListTile(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MyComplaintsPage(),
                        ),
                      ),
                      leading: Icon(
                        Icons.mark_chat_read_outlined,
                        color: kPrimary,
                      ),
                      title: const Text('شكاواي واقتراحاتي'),
                      subtitle: const Text('شوف رد الإدارة'),
                      trailing: const Icon(Icons.chevron_left),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      onTap: () => LegalPage.open(
                        context,
                        title: 'سياسة الخصوصية',
                        sections: kPrivacySections,
                      ),
                      leading: Icon(
                        Icons.privacy_tip_outlined,
                        color: kPrimary,
                      ),
                      title: const Text('سياسة الخصوصية'),
                      trailing: const Icon(Icons.chevron_left),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      onTap: () => LegalPage.open(
                        context,
                        title: 'شروط الاستخدام',
                        sections: kTermsSections,
                      ),
                      leading: Icon(
                        Icons.description_outlined,
                        color: kPrimary,
                      ),
                      title: const Text('شروط الاستخدام'),
                      trailing: const Icon(Icons.chevron_left),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: _card,
                child: ListTile(
                  onTap: _signOut,
                  leading: const Icon(Icons.logout, color: kDanger),
                  title: const Text(
                    'تسجيل الخروج',
                    style: TextStyle(
                      color: kDanger,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: TextButton(
                  onPressed: _deleteAccount,
                  style: TextButton.styleFrom(
                    foregroundColor: kMuted,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                  ),
                  child: const Text(
                    'حذف الحساب',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final String empty;
  const _InfoRow({
    required this.icon,
    required this.value,
    required this.empty,
  });

  @override
  Widget build(BuildContext context) {
    final has = value.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: kPrimary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            has ? value : empty,
            style: TextStyle(color: has ? kInk : kMuted),
          ),
        ),
      ],
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  final UserProfile initial;
  const _EditProfileSheet({required this.initial});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.initial.name.isNotEmpty
        ? widget.initial.name
        : FirebaseAuth.instance.currentUser?.displayName ?? '',
  );
  late final _phone = TextEditingController(text: widget.initial.phone);
  late final _address = TextEditingController(text: widget.initial.address);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final cleanPhone = _phone.text
          .replaceAll(RegExp(r'[\s\-]'), '')
          .replaceAll('٠', '0')
          .replaceAll('١', '1')
          .replaceAll('٢', '2')
          .replaceAll('٣', '3')
          .replaceAll('٤', '4')
          .replaceAll('٥', '5')
          .replaceAll('٦', '6')
          .replaceAll('٧', '7')
          .replaceAll('٨', '8')
          .replaceAll('٩', '9');

      await UserService.save(
        UserProfile(
          name: _name.text.trim(),
          phone: cleanPhone,
          address: _address.text.trim(),
        ),
      );
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('تم حفظ بياناتك')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر الحفظ. جرّب تاني.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تعديل بيانات التوصيل',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'الاسم',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 2) ? 'اكتب اسمك' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رقم الموبايل',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) {
                  final value = v ?? '';
                  if (value.trim().isEmpty) return null;
                  return isValidEgyptianMobile(value)
                      ? null
                      : 'اكتب رقم موبايل مصري صحيح (11 رقم)';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'العنوان بالتفصيل',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('حفظ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
