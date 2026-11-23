import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_header.dart';

/// دليل حسابات Firestore للإدارة: الاسم، UID، والأدوار الفعلية.
/// قراءات محدودة عند فتح الصفحة فقط، بدون مستمعات مستمرة.
class AdminUserDirectoryPage extends StatefulWidget {
  const AdminUserDirectoryPage({super.key});

  @override
  State<AdminUserDirectoryPage> createState() => _AdminUserDirectoryPageState();
}

class _AdminUserDirectoryPageState extends State<AdminUserDirectoryPage> {
  final _search = TextEditingController();
  late final Future<_DirectoryData> _data = _load();

  Future<_DirectoryData> _load() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('users').limit(200).get(),
      db.collection('couriers').limit(200).get(),
      db.collection('storeOwners').limit(200).get(),
      db.collection('admins').limit(200).get(),
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
            return const Center(child: Text('تعذر تحميل المستخدمين. تأكد من صلاحية الإدارة ونشر القواعد.'));
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
                    prefixIcon: Icon(Icons.search),
                    hintText: 'ابحث بالاسم أو UID أو الصلاحية',
                    border: OutlineInputBorder(),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final u = users[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(u.name, style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Wrap(spacing: 6, runSpacing: 4, children: [
                                for (final role in u.roles) Chip(label: Text(role)),
                              ]),
                              const SizedBox(height: 4),
                              Row(children: [
                                Expanded(
                                  child: SelectableText(u.uid, textDirection: TextDirection.ltr,
                                      style: Theme.of(context).textTheme.bodySmall),
                                ),
                                IconButton(
                                  tooltip: 'نسخ UID',
                                  icon: const Icon(Icons.copy_outlined),
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: u.uid));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('تم نسخ UID')),
                                      );
                                    }
                                  },
                                ),
                              ]),
                            ],
                          ),
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
