import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feedback_service.dart';
import 'notification_service.dart';

/// تنبيهات لحظية للدردشة والشكاوى، من غير Cloud Functions (شغّالة على الخطة المجانية).
///
/// بتسمع على Firestore وتعرض شريط تنبيه + صوت لما التطبيق يكون شغّال (مفتوح أو في الخلفية
/// وعملية التطبيق لسه عايشة). لو التطبيق اتقفل تمامًا مفيش طريقة تبعت إشعار جهاز من غير سيرفر
/// (Blaze + Functions)، وساعتها بنفس الأحداث دي بتتبعت إشعارات FCM.
///
///  • أي مستخدم: رد الإدارة في الدردشة، ورد الإدارة على شكواه/اقتراحه.
///  • المدير بس: رسالة دردشة جديدة، وشكوى أو اقتراح جديد.
///  • صاحب المحل: طلب جديد على محله.
///  • المندوب: طلب جديد متاح للاستلام، وتأكيد المحل إن طلبه جاهز.
class LiveAlerts {
  const LiveAlerts._();

  /// معرّف المحادثة المفتوحة حاليًا في SupportChatPage (عشان ما ننبّهش على اللي قدام عينه).
  static String? openChatUid;

  static final List<StreamSubscription<dynamic>> _subs = [];
  static String _uid = '';
  static bool _admin = false;
  static String _storeId = '';
  static bool _courier = false;
  static final AudioPlayer _player = AudioPlayer();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// بتتنادي بعد معرفة دور المستخدم. آمنة لو اتنادت أكتر من مرة.
  static Future<void> start({
    required bool isAdmin,
    String storeId = '',
    bool isCourier = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_uid == user.uid &&
        _admin == isAdmin &&
        _storeId == storeId &&
        _courier == isCourier &&
        _subs.isNotEmpty) {
      return;
    }
    await stop();
    _uid = user.uid;
    _admin = isAdmin;
    _storeId = storeId;
    _courier = isCourier;

    _watchMyChat(user.uid);
    _watchMyComplaints(user.uid);
    if (isAdmin) {
      _watchAdminChats();
      _watchAdminComplaints(user.uid);
    }
    if (storeId.isNotEmpty) _watchStoreOrders(storeId);
    if (isCourier) {
      _watchAvailableOrders();
      _watchMyReadyOrders(user.uid);
    }
  }

  static Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _uid = '';
    _admin = false;
    _storeId = '';
    _courier = false;
    openChatUid = null;
  }

  // ───────────────────────── للمستخدم ─────────────────────────

  static void _watchMyChat(String uid) {
    String? lastKey;
    _subs.add(
      _db
          .collection('support_chats')
          .doc(uid)
          .snapshots()
          .listen(
            (snap) {
              if (snap.metadata.hasPendingWrites) return;
              final d = snap.data();
              if (d == null) return;
              final unread =
                  d['unreadForUser'] == true && d['lastSender'] == 'admin';
              if (!unread || openChatUid == uid) return;
              final key = '${d['lastAt']}';
              if (key == lastKey) return;
              lastKey = key;
              _notify('رد جديد من الدعم', (d['lastMessage'] ?? '').toString());
            },
            onError: (Object e) => debugPrint('LiveAlerts chat: $e'),
          ),
    );
  }

  /// ردود الإدارة على شكاوى المستخدم. أول مرة بنسجّل الحالي بدون تنبيه، وبعدها أي رد جديد بينبّه.
  static void _watchMyComplaints(String uid) {
    final prefsKey = 'seen_complaint_replies_$uid';
    _subs.add(
      _db
          .collection('complaints')
          .where('userId', isEqualTo: uid)
          .snapshots()
          .listen(
            (snap) async {
              if (snap.metadata.hasPendingWrites) return;
              try {
                final prefs = await SharedPreferences.getInstance();
                final firstRun = !prefs.containsKey(prefsKey);
                final seen = (prefs.getStringList(prefsKey) ?? const <String>[])
                    .toSet();
                var fresh = 0;
                String preview = '';
                for (final doc in snap.docs) {
                  final d = doc.data();
                  final status = (d['status'] ?? 'open').toString();
                  final note = (d['adminNote'] ?? '').toString();
                  if (status == 'open' && note.isEmpty) continue;
                  final sig = '${doc.id}:$status:${note.hashCode}';
                  if (seen.add(sig) && !firstRun) {
                    fresh++;
                    preview = note.isNotEmpty ? note : _statusText(status);
                  }
                }
                await prefs.setStringList(prefsKey, seen.toList());
                if (fresh > 0) {
                  _notify(
                    fresh == 1
                        ? 'تم الرد على شكواك/اقتراحك'
                        : 'فيه $fresh ردود جديدة على شكاواك',
                    preview,
                  );
                }
              } catch (e) {
                debugPrint('LiveAlerts complaints: $e');
              }
            },
            onError: (Object e) => debugPrint('LiveAlerts complaints: $e'),
          ),
    );
  }

  static String _statusText(String status) => switch (status) {
    'in_progress' => 'شكواك قيد المراجعة.',
    'resolved' => 'تم حل شكواك.',
    _ => 'اتحدّثت حالة شكواك.',
  };

  // ───────────────────────── للمدير ─────────────────────────

  static void _watchAdminChats() {
    var first = true;
    final seen = <String>{};
    _subs.add(
      _db
          .collection('support_chats')
          .where('unreadForAdmin', isEqualTo: true)
          .snapshots()
          .listen(
            (snap) {
              if (snap.metadata.hasPendingWrites) return;
              if (first) {
                first = false;
                for (final d in snap.docs) {
                  seen.add('${d.id}:${d.data()['lastAt']}');
                }
                if (snap.docs.isNotEmpty) {
                  _notify(
                    'محادثات الدعم',
                    'عندك ${snap.docs.length} محادثة غير مقروءة.',
                  );
                }
                return;
              }
              for (final ch in snap.docChanges) {
                if (ch.type == DocumentChangeType.removed) continue;
                final d = ch.doc.data();
                if (d == null || d['lastSender'] != 'user') continue;
                if (ch.doc.id == openChatUid) continue;
                if (!seen.add('${ch.doc.id}:${d['lastAt']}')) continue;
                final who = (d['userName'] ?? '').toString();
                _notify(
                  'رسالة جديدة${who.isEmpty ? '' : ' من $who'}',
                  (d['lastMessage'] ?? '').toString(),
                );
              }
            },
            onError: (Object e) => debugPrint('LiveAlerts admin chats: $e'),
          ),
    );
  }

  static void _watchAdminComplaints(String myUid) {
    var first = true;
    _subs.add(
      _db
          .collection('complaints')
          .where('status', isEqualTo: 'open')
          .snapshots()
          .listen(
            (snap) {
              if (snap.metadata.hasPendingWrites) return;
              if (first) {
                first = false;
                if (snap.docs.isNotEmpty) {
                  _notify(
                    'الشكاوى والاقتراحات',
                    'عندك ${snap.docs.length} شكوى/اقتراح مفتوح.',
                  );
                }
                return;
              }
              for (final ch in snap.docChanges) {
                if (ch.type != DocumentChangeType.added) continue;
                final d = ch.doc.data();
                if (d == null || d['userId'] == myUid) continue;
                final kind = FeedbackKind.parse(d['kind']?.toString()).label;
                final who = (d['userName'] ?? '').toString();
                _notify(
                  '$kind جديد${who.isEmpty ? '' : ' من $who'}',
                  (d['message'] ?? '').toString(),
                );
              }
            },
            onError: (Object e) => debugPrint('LiveAlerts admin complaints: $e'),
          ),
    );
  }

  // ───────────────────────── لصاحب المحل ─────────────────────────

  /// طلب جديد (status = new) على محل صاحب الحساب. أول مرة بنعرض ملخص بالعدد بس.
  static void _watchStoreOrders(String storeId) {
    var first = true;
    final seen = <String>{};
    _subs.add(
      _db
          .collection('orders')
          .where('storeId', isEqualTo: storeId)
          .where('status', isEqualTo: 'new')
          .snapshots()
          .listen(
            (snap) {
              // أول لقطة ممكن تيجي من الكاش، فنستنى لقطة السيرفر عشان ما ننبّهش على طلبات قديمة.
              if (snap.metadata.hasPendingWrites) return;
              if (first) {
                if (snap.metadata.isFromCache) return;
                first = false;
                for (final d in snap.docs) {
                  seen.add(d.id);
                }
                if (snap.docs.isNotEmpty) {
                  _notify(
                    'طلبات جديدة',
                    'عندك ${snap.docs.length} طلب جديد مستني القبول.',
                  );
                }
                return;
              }
              for (final ch in snap.docChanges) {
                if (ch.type != DocumentChangeType.added) continue;
                if (!seen.add(ch.doc.id)) continue;
                _notify('طلب جديد', 'وصل طلب جديد على محلك. افتح الطلبات وراجعه.');
              }
            },
            onError: (Object e) => debugPrint('LiveAlerts store orders: $e'),
          ),
    );
  }

  // ───────────────────────── للمندوب ─────────────────────────

  /// طلب جديد بقى متاح للاستلام (المحل بدأ التجهيز).
  static void _watchAvailableOrders() {
    var first = true;
    final seen = <String>{};
    _subs.add(
      _db.collection('courier_available_orders').snapshots().listen(
        (snap) {
          if (snap.metadata.hasPendingWrites) return;
          if (first) {
            if (snap.metadata.isFromCache) return;
            first = false;
            for (final d in snap.docs) {
              seen.add(d.id);
            }
            if (snap.docs.isNotEmpty) {
              _notify(
                'طلبات متاحة',
                'فيه ${snap.docs.length} طلب متاح للاستلام.',
              );
            }
            return;
          }
          for (final ch in snap.docChanges) {
            if (ch.type != DocumentChangeType.added) continue;
            if (!seen.add(ch.doc.id)) continue;
            final store = (ch.doc.data()?['storeName'] ?? '').toString();
            _notify(
              'طلب جديد متاح',
              store.isEmpty ? 'فيه طلب جديد متاح للاستلام.' : 'طلب من $store متاح للاستلام.',
            );
          }
        },
        onError: (Object e) => debugPrint('LiveAlerts available: $e'),
      ),
    );
  }

  /// المحل أكّد إن طلب المندوب (اللي استلمه) بقى جاهز.
  static void _watchMyReadyOrders(String uid) {
    var first = true;
    final wasReady = <String, bool>{};
    _subs.add(
      _db
          .collection('orders')
          .where('courierId', isEqualTo: uid)
          .snapshots()
          .listen(
            (snap) {
              if (snap.metadata.hasPendingWrites) return;
              final initial = first;
              if (first) {
                if (snap.metadata.isFromCache) return;
                first = false;
              }
              for (final ch in snap.docChanges) {
                if (ch.type == DocumentChangeType.removed) continue;
                final d = ch.doc.data();
                if (d == null) continue;
                final ready = d['ready'] == true;
                final before = wasReady[ch.doc.id];
                wasReady[ch.doc.id] = ready;
                if (initial) continue;
                if (ready && before == false && d['status'] == 'preparing') {
                  final store = (d['storeName'] ?? '').toString();
                  _notify(
                    'الطلب جاهز للاستلام',
                    store.isEmpty ? 'طلبك جاهز عند المحل.' : 'طلبك من $store جاهز.',
                  );
                }
              }
            },
            onError: (Object e) => debugPrint('LiveAlerts ready orders: $e'),
          ),
    );
  }

  // ───────────────────────── العرض ─────────────────────────

  static void _notify(String title, String body) {
    final messenger = NotificationService.messengerKey.currentState;
    if (messenger == null) return;
    final preview = body.length > 90 ? '${body.substring(0, 90)}…' : body;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (preview.isNotEmpty) Text(preview),
            ],
          ),
        ),
      );
    _beep();
  }

  static Future<void> _beep() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/bell.wav'));
    } catch (_) {
      // الصوت اختياري: لو الملف مش متضمّن في assets التنبيه المرئي كفاية.
    }
  }
}
