import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_tokens.dart';
import '../widgets/app_ui.dart';
import '../widgets/app_header.dart';
import '../widgets/app_snack.dart';

/// دليل حسابات Firestore للإدارة: الاسم، UID، والأدوار الفعلية.
/// قراءات محدودة عند فتح الصفحة فقط، بدون مستمعات مستمرة.
class AdminUserDirectoryPage extends StatefulWidget {
  const AdminUserDirectoryPage({super.key});

  @override
  State<AdminUserDirectoryPage> createState() => _AdminUserDirectoryPageState();
}

class _AdminUserDirectoryPageState extends State<AdminUserDirectoryPage> {
  final _search = TextEditingController();
  late Future<_DirectoryData> _data = _load();

  Future<_DirectoryData> _load() async {
    final db = FirebaseFirestore.instance;
    Future<QuerySnapshot<Map<String, dynamic>>> readCollection(
      String collection,
      String label,
    ) async {
      try {
        return await db.collection(collection).limit(200).get();
      } on FirebaseException catch (error) {
        throw _DirectoryLoadFailure(label, error.code);
      }
    }

    final results = await Future.wait([
      readCollection('users', 'المستخدمين'),
      readCollection('couriers', 'المناديب'),
      readCollection('storeOwners', 'أصحاب المحلات'),
      readCollection('admins', 'المديرين'),
    ]);
    final couriers = results[1].docs.map((d) => d.id).toSet();
    final owners = results[2].docs.map((d) => d.id).toSet();
    final admins = results[3].docs.map((d) => d.id).toSet();
    final entries = <String, _UserEntry>{};
    for (final doc in results[0].docs) {
      final data = doc.data();
      final name = [
        data['name'],
        data['displayName'],
        data['fullName'],
      ].whereType<String>().map((s) => s.trim()).firstWhere(
            (s) => s.isNotEmpty,
            orElse: () => 'مستخدم بدون اسم',
          );
      entries[doc.id] = _UserEntry(doc.id, name, <String>[]);
    }
    for (final doc in results[1].docs) {
      entries.putIfAbsent(doc.id, () => _UserEntry(doc.id, 'مندوب', <String>[]));
    }
    for (final doc in results[2].docs) {
      entries.putIfAbsent(doc.id, () => _UserEntry(doc.id, 'صاحب محل', <String>[]));
    }
    for (final doc in results[3].docs) {
      entries.putIfAbsent(doc.id, () => _UserEntry(doc.id, 'مدير', <String>[]));
    }
    for (final e in entries.values) {
      if (admins.contains(e.uid)) e.roles.add('إدارة');
      if (owners.contains(e.uid)) e.roles.add('صاحب محل');
      if (couriers.contains(e.uid)) e.roles.add('مندوب');
      if (e.roles.isEmpty) e.roles.add('عميل');
    }
    final list = entries.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return _DirectoryData(list, results.any((r) => r.docs.length == 200));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دليل المستخدمين'), actions: const [HomeActionButton()]),
      body: FutureBuilder<_DirectoryData>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) {
            final error = snap.error;
            final message = error is _DirectoryLoadFailure
                ? 'تعذر تحميل قائمة ${error.label} (${error.code}).'
                : 'تعذر تحميل دليل المستخدمين.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _data = _load()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'ابحث بالاسم أو UID أو الصلاحية',
                  ),
                ),
              ),
              if (snap.data!.limited)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('النتائج محدودة بأول 200 حساب لكل نوع.'),
                ),
              Expanded(
                child: Builder(builder: (context) {
                  final query = _search.text.trim().toLowerCase();
                  final users = snap.data!.users.where((u) =>
                      u.name.toLowerCase().contains(query) ||
                      u.uid.toLowerCase().contains(query) ||
                      u.roles.join(' ').contains(query)).toList();
                  if (users.isEmpty) return const Center(child: Text('مفيش نتائج مطابقة.'));
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.xxl),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final u = users[index];
                      // كارت مضغوط: الاسم + صلاحيات صغيرة في سطر واحد + UID.
                      return AppCard(
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            AppSpacing.lg, AppSpacing.md, AppSpacing.xs, AppSpacing.xs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: AppColors.purpleSoft,
                                child: Text(
                                  u.name.trim().isEmpty ? '؟' : u.name.trim().characters.first.toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.purple,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: AppTypography.sectionTitle),
                              ),
                            ]),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
                              for (final role in u.roles)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
                                  decoration: BoxDecoration(
                                    color: AppColors.purpleSoft,
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                  ),
                                  child: Text(role, style: const TextStyle(
                                    color: AppColors.purple,
                                    fontSize: AppTypography.label,
                                    fontWeight: FontWeight.w800,
                                  )),
                                ),
                            ]),
                            Row(children: [
                              Expanded(
                                child: SelectableText(u.uid, textDirection: TextDirection.ltr,
                                    style: AppTypography.secondary.copyWith(fontSize: AppTypography.label)),
                              ),
                              IconButton(
                                tooltip: 'نسخ UID',
                                icon: const Icon(Icons.copy_rounded, size: 20),
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: u.uid));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      appSnack('تم نسخ UID'),
                                    );
                                  }
                                },
                              ),
                            ]),
                          ],
                        ),
                      );
                    },
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _UserEntry {
  final String uid;
  final String name;
  final List<String> roles;
  _UserEntry(this.uid, this.name, this.roles);
}

class _DirectoryData {
  final List<_UserEntry> users;
  final bool limited;
  _DirectoryData(this.users, this.limited);
}

class _DirectoryLoadFailure implements Exception {
  const _DirectoryLoadFailure(this.label, this.code);

  final String label;
  final String code;
}
