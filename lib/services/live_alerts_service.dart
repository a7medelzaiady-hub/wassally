import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'read_meter.dart';
import '../widgets/app_notice.dart';

/// تنبيهات لحظية للمندوب من غير Cloud Functions (شغّالة على الخطة المجانية).
///
/// الدعم والشكاوى بقوا على واتساب، فمفيش مستمعات للدردشة ولا للشكاوى هنا.
/// بتسمع على Firestore وتعرض شريط تنبيه + صوت لما التطبيق يكون شغّال (مفتوح أو في الخلفية
/// وعملية التطبيق لسه عايشة).
///
///  • صاحب المحل: طلب جديد على محله (من شاشته نفسها).
///  • المندوب: تأكيد المحل إن طلبه جاهز.
class LiveAlerts {
  const LiveAlerts._();

  static bool _observerAdded = false;
  static bool _paused = false;

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
    _ensureLifecycleObserver();
    if (!_paused) _attachSubscriptions();
  }

  static void _ensureLifecycleObserver() {
    if (_observerAdded) return;
    WidgetsBinding.instance.addObserver(_LiveAlertsLifecycleObserver());
    _observerAdded = true;
  }

  static void _attachSubscriptions() {
    final uid = _uid;
    if (uid.isEmpty || _subs.isNotEmpty || _paused) return;
    // لا نكرر مستمع الطلبات: شاشة صاحب المحل نفسها تراقب طلبات محله،
    // وشاشة المندوب تراقب قائمة المتاح. تكرار نفس الاستعلام هنا يضاعف القراءات.
    if (_courier) _watchMyReadyOrders(uid);
  }

  static Future<void> _pauseSubscriptions() async {
    if (_paused) return;
    _paused = true;
    final subscriptions = List<StreamSubscription<dynamic>>.from(_subs);
    _subs.clear();
    await Future.wait(subscriptions.map((subscription) => subscription.cancel()));
  }

  static void _resumeSubscriptions() {
    if (!_paused || _uid.isEmpty || FirebaseAuth.instance.currentUser == null) return;
    _paused = false;
    _attachSubscriptions();
  }

  static void _onLifecycleChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pauseSubscriptions();
    } else if (state == AppLifecycleState.resumed) {
      _resumeSubscriptions();
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
    _paused = false;
  }

  // مستمع الطلبات الجديدة للمحل وقائمة الطلبات المتاحة للمندوب
  // موجودان بالفعل في الشاشتين المختصتين؛ لا نعيد فتحهما هنا.

  /// المحل أكّد إن طلب المندوب (اللي استلمه) بقى جاهز.
  static void _watchMyReadyOrders(String uid) {
    var first = true;
    final wasReady = <String, bool>{};
    _subs.add(
      _db
          .collection('orders')
          .where('courierId', isEqualTo: uid)
          .where('status', isEqualTo: 'preparing')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots().metered('alerts:courier-ready')
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
    final preview = body.length > 90 ? '${body.substring(0, 90)}…' : body;
    // إشعار في نص الشاشة بيقفل لوحده بعد شوية، أو بلمسة برّه.
    showAppNotice(
      title: title,
      message: preview,
      kind: AppNoticeKind.info,
      autoClose: const Duration(seconds: 7),
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


class _LiveAlertsLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LiveAlerts._onLifecycleChanged(state);
  }
}
