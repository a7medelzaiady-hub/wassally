import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_role.dart';
import 'role_service.dart';

class ChatMessage {
  final String id;
  final String senderRole; // 'user' أو 'admin'
  final String text;
  final DateTime? createdAt;
  const ChatMessage(this.id, this.senderRole, this.text, this.createdAt);

  bool get fromAdmin => senderRole == 'admin';
}

/// شات مباشر بين المستخدم والإدارة. محادثة واحدة لكل مستخدم: support_chats/{uid}.
/// الشكل والقواعد في firestore.rules (support_chats).
class ChatService {
  const ChatService._();

  static const int maxLength = 1000;

  static final _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _chat(String uid) =>
      _db.collection('support_chats').doc(uid);

  static String _roleKey(AppRole? r) => switch (r) {
    AppRole.admin => 'admin',
    AppRole.courier => 'courier',
    AppRole.storeOwner => 'store_owner',
    AppRole.supervisor => 'supervisor',
    _ => 'customer',
  };

  static String _preview(String t) => t.length > 120 ? t.substring(0, 120) : t;

  /// رسائل المحادثة بالترتيب (الأقدم أولًا).
  static Stream<List<ChatMessage>> watchMessages(String uid) {
    return _chat(uid)
        .collection('messages')
        .orderBy('createdAt')
        .limitToLast(300)
        .snapshots()
        .map(
          (snap) => [
            for (final d in snap.docs)
              ChatMessage(
                d.id,
                (d.data()['senderRole'] ?? 'user').toString(),
                (d.data()['text'] ?? '').toString(),
                d.data()['createdAt'] is Timestamp
                    ? (d.data()['createdAt'] as Timestamp).toDate()
                    : null,
              ),
          ],
        );
  }

  /// المستخدم بيبعت رسالة للإدارة.
  static Future<void> sendAsUser(String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('سجّل دخول الأول.');
    final t = text.trim();
    if (t.isEmpty || t.length > maxLength)
      throw ArgumentError('رسالة غير صالحة.');
    var name = user.displayName ?? '';
    if (name.length > 80) name = name.substring(0, 80);
    final chat = _chat(user.uid);
    final batch = _db.batch();
    batch.set(chat, {
      'userId': user.uid,
      'userName': name,
      'userEmail': user.email ?? '',
      'appRole': _roleKey(RoleService.cachedFor(user.uid)?.role),
      'lastMessage': _preview(t),
      'lastSender': 'user',
      'lastAt': FieldValue.serverTimestamp(),
      'unreadForAdmin': true,
      'unreadForUser': false,
    }, SetOptions(merge: true));
    batch.set(chat.collection('messages').doc(), {
      'senderId': user.uid,
      'senderRole': 'user',
      'text': t,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// المدير بيرد على محادثة مستخدم.
  static Future<void> sendAsAdmin(String chatUid, String text) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) throw StateError('سجّل دخول الأول.');
    final t = text.trim();
    if (t.isEmpty || t.length > maxLength)
      throw ArgumentError('رسالة غير صالحة.');
    final chat = _chat(chatUid);
    final batch = _db.batch();
    batch.update(chat, {
      'lastMessage': _preview(t),
      'lastSender': 'admin',
      'lastAt': FieldValue.serverTimestamp(),
      'unreadForUser': true,
      'unreadForAdmin': false,
    });
    batch.set(chat.collection('messages').doc(), {
      'senderId': admin.uid,
      'senderRole': 'admin',
      'text': t,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// علّم المحادثة مقروءة من ناحية المستخدم أو المدير.
  static Future<void> markRead(String chatUid, {required bool asAdmin}) async {
    try {
      await _chat(chatUid)
          .update({asAdmin ? 'unreadForAdmin' : 'unreadForUser': false});
    } catch (_) {
      // المحادثة لسه ما اتعملتش، أو مفيش حاجة تتعلّم.
    }
  }

  /// للمدير: كل المحادثات، الأحدث أولًا.
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchAllChats() => _db
      .collection('support_chats')
      .orderBy('lastAt', descending: true)
      .limit(100)
      .snapshots();
}
