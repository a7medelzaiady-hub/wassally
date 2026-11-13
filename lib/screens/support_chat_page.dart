import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/live_alerts_service.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../widgets/app_header.dart';

/// شات مع الإدارة. للمستخدم: من غير [chatUid] (محادثته هو).
/// للمدير: [chatUid] = معرّف المستخدم اللي بيرد عليه.
class SupportChatPage extends StatefulWidget {
  final String? chatUid;
  final String title;
  const SupportChatPage({
    super.key,
    this.chatUid,
    this.title = 'محادثة مع الإدارة',
  });

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  String? _markedFor;

  late final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final String _chatUid = widget.chatUid ?? _uid;
  bool get _asAdmin => widget.chatUid != null && widget.chatUid != _uid;

  late final Stream<List<ChatMessage>> _messages = ChatService.watchMessages(
    _chatUid,
  );

  @override
  void initState() {
    super.initState();
    LiveAlerts.openChatUid = _chatUid;
    ChatService.markRead(_chatUid, asAdmin: _asAdmin);
  }

  @override
  void dispose() {
    if (LiveAlerts.openChatUid == _chatUid) LiveAlerts.openChatUid = null;
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty || _sending) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      if (_asAdmin) {
        await ChatService.sendAsAdmin(_chatUid, t);
      } else {
        await ChatService.sendAsUser(t);
      }
      _ctrl.clear();
    } on FirebaseException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر الإرسال (${e.code}). جرّب تاني.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر الإرسال. جرّب تاني.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _time(DateTime? d) {
    if (d == null) return '';
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final suffix = d.hour < 12 ? 'ص' : 'م';
    final now = DateTime.now();
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    final day =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return sameDay ? '$h12:$m $suffix' : '$day  $h12:$m $suffix';
  }

  Widget _bubble(ChatMessage m) {
    // رسالتي: لون السمة. رسالة الطرف التاني: أبيض.
    final mine = _asAdmin ? m.fromAdmin : !m.fromAdmin;
    final bg = mine ? Brand.green : Colors.white;
    final fg = mine ? Colors.white : Brand.ink;
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: mine ? null : Border.all(color: kLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_asAdmin && m.fromAdmin)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  'الإدارة',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Brand.goldDeep,
                  ),
                ),
              ),
            Text(
              m.text,
              style: TextStyle(fontSize: 14, height: 1.4, color: fg),
            ),
            const SizedBox(height: 3),
            Text(
              _time(m.createdAt),
              style: TextStyle(
                fontSize: 10.5,
                color: fg.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          InnerHeader(title: widget.title),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messages,
              builder: (context, snap) {
                if (snap.hasError) {
                  final e = snap.error;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        e is FirebaseException
                            ? 'تعذر تحميل المحادثة (${e.code}). لو permission-denied يبقى لازم تنشر firestore.rules الجديدة.'
                            : 'تعذر تحميل المحادثة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kMuted),
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return Center(
                    child: CircularProgressIndicator(color: Brand.green),
                  );
                }
                final list = snap.data!;
                if (list.isNotEmpty) {
                  final last = list.last;
                  final fromOther = _asAdmin ? !last.fromAdmin : last.fromAdmin;
                  if (fromOther && _markedFor != last.id) {
                    _markedFor = last.id;
                    ChatService.markRead(_chatUid, asAdmin: _asAdmin);
                  }
                }
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        _asAdmin
                            ? 'مفيش رسائل لسه.'
                            : 'اكتب رسالتك وهترد عليك الإدارة في أقرب وقت.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: kMuted),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _bubble(list[list.length - 1 - i]),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: kLine)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: ChatService.maxLength,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالتك...',
                        counterText: '',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: FilledButton(
                      onPressed: _sending ? null : _send,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(46, 46),
                        shape: const CircleBorder(),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
