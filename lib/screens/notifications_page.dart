import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../widgets/empty_state.dart';

// ───────────────────────── أنواع الإشعارات ─────────────────────────

/// نوع الإشعار: بيتحدد من نص العنوان والمحتوى.
enum _NotifKind { received, preparing, onTheWay, delivered, cancelled, general }

class _KindStyle {
  final String label;
  final IconData icon;
  final Color color;

  /// ترتيب الخطوة في شريط تتبع الطلب (-1 = من غير شريط).
  final int step;
  const _KindStyle(this.label, this.icon, this.color, this.step);
}

Map<_NotifKind, _KindStyle> get _kStyles => <_NotifKind, _KindStyle>{
  _NotifKind.received: _KindStyle(
    'تم الاستلام',
    Icons.receipt_long_rounded,
    Color(0xFF5B6EE1),
    0,
  ),
  _NotifKind.preparing: _KindStyle(
    'قيد التجهيز',
    Icons.restaurant_rounded,
    Color(0xFFE59A00),
    1,
  ),
  _NotifKind.onTheWay: _KindStyle(
    'في الطريق',
    Icons.two_wheeler_rounded,
    Color(0xFF2F6FED),
    2,
  ),
  _NotifKind.delivered: _KindStyle(
    'تم التسليم',
    Icons.celebration_rounded,
    Color(0xFF1F9D63),
    3,
  ),
  _NotifKind.cancelled: _KindStyle(
    'ملغي',
    Icons.cancel_rounded,
    Color(0xFFD92D20),
    -1,
  ),
  _NotifKind.general: _KindStyle(
    'إشعار',
    Icons.notifications_active_rounded,
    Brand.goldDeep,
    -1,
  ),
};

_NotifKind? _testKind(String s) {
  if (s.contains('ملغ') || s.contains('إلغاء') || s.contains('الغاء')) {
    return _NotifKind.cancelled;
  }
  if (s.contains('تسليم') || s.contains('التوصيل')) {
    return _NotifKind.delivered;
  }
  if (s.contains('في الطريق')) return _NotifKind.onTheWay;
  if (s.contains('تجهيز') || s.contains('تحضير')) return _NotifKind.preparing;
  if (s.contains('استلام')) return _NotifKind.received;
  return null;
}

/// العنوان له الأولوية، وبعدين المحتوى.
_NotifKind _kindOf(String title, String body) =>
    _testKind(title) ?? _testKind(body) ?? _NotifKind.general;

// ───────────────────────── الوقت والتجميع ─────────────────────────

String _two(int n) => n.toString().padLeft(2, '0');

String _ago(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'الآن';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    if (m == 1) return 'منذ دقيقة';
    if (m == 2) return 'منذ دقيقتين';
    if (m <= 10) return 'منذ $m دقائق';
    return 'منذ $m دقيقة';
  }
  final h = diff.inHours;
  if (h == 1) return 'منذ ساعة';
  if (h == 2) return 'منذ ساعتين';
  if (h <= 10) return 'منذ $h ساعات';
  return 'منذ $h ساعة';
}

String _stamp(DateTime d) {
  final clock = '${_two(d.hour)}:${_two(d.minute)}';
  if (DateTime.now().difference(d).inHours < 24) {
    return '${_ago(d)}  •  $clock';
  }
  return '${d.year}/${_two(d.month)}/${_two(d.day)}  •  $clock';
}

String _groupOf(DateTime? d) {
  if (d == null) return 'أقدم';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  return 'أقدم';
}

Widget _blob(double size, Color color, double alpha) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: alpha),
    ),
  );
}

Widget _shell({required Widget header, required Widget child}) {
  return Column(
    children: [
      header,
      Expanded(child: child),
    ],
  );
}

// ───────────────────────── الصفحة ─────────────────────────

/// صفحة الإشعارات: كروت ملونة حسب حالة الطلب، مع شريط تتبع وحركات.
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  Future<void> _markAllRead(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final d in docs) {
        if (d.data()['read'] != true) {
          batch.update(d.reference, {'read': true});
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Mark all read error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: Brand.bg,
      body: uid == null
          ? _shell(
              header: const _NotifHeader(),
              child: const EmptyState(
                icon: Icons.lock_outline,
                title: 'سجّل الدخول أولًا',
                message: 'الإشعارات بتظهر بعد تسجيل الدخول.',
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('userId', isEqualTo: uid)
                  .orderBy('createdAt', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _shell(
                    header: const _NotifHeader(),
                    child: const EmptyState(
                      icon: Icons.cloud_off,
                      title: 'تعذر تحميل الإشعارات',
                      message: 'حاول مرة تانية بعد شوية.',
                    ),
                  );
                }
                if (!snap.hasData) {
                  return _shell(
                    header: const _NotifHeader(),
                    child: Center(
                      child: CircularProgressIndicator(color: Brand.green),
                    ),
                  );
                }

                final docs = [...snap.data!.docs];
                docs.sort((a, b) {
                  final at = a.data()['createdAt'];
                  final bt = b.data()['createdAt'];
                  final am = at is Timestamp ? at.millisecondsSinceEpoch : 0;
                  final bm = bt is Timestamp ? bt.millisecondsSinceEpoch : 0;
                  return bm.compareTo(am);
                });

                final unread = docs
                    .where((d) => d.data()['read'] != true)
                    .length;

                // قائمة مسطّحة: عنوان مجموعة (String) أو إشعار.
                final entries = <Object>[];
                String? last;
                for (final d in docs) {
                  final ts = d.data()['createdAt'];
                  final g = _groupOf(ts is Timestamp ? ts.toDate() : null);
                  if (g != last) {
                    entries.add(g);
                    last = g;
                  }
                  entries.add(d);
                }

                return _shell(
                  header: _NotifHeader(
                    unread: unread,
                    onMarkAll: unread > 0 ? () => _markAllRead(docs) : null,
                  ),
                  child: docs.isEmpty
                      ? const EmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: 'مفيش إشعارات لسه',
                          message: 'أي تحديث على طلباتك هيظهر هنا.',
                        )
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                          itemCount: entries.length,
                          itemBuilder: (context, i) {
                            final e = entries[i];
                            if (e is String) return _GroupLabel(e);
                            final d =
                                e
                                    as QueryDocumentSnapshot<
                                      Map<String, dynamic>
                                    >;
                            return _NotifCard(
                              key: ValueKey(d.id),
                              doc: d,
                              index: i,
                            );
                          },
                        ),
                );
              },
            ),
    );
  }
}

// ───────────────────────── الهيدر ─────────────────────────

class _NotifHeader extends StatelessWidget {
  final int unread;
  final VoidCallback? onMarkAll;
  const _NotifHeader({this.unread = 0, this.onMarkAll});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final subtitle = unread == 0
        ? 'مفيش إشعارات جديدة'
        : unread == 1
        ? 'عندك إشعار جديد'
        : 'عندك $unread إشعارات جديدة';

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(gradient: Brand.headerGradient),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -36,
              end: -24,
              child: _blob(120, Colors.white, 0.09),
            ),
            PositionedDirectional(
              bottom: -40,
              start: 70,
              child: _blob(90, Brand.gold, 0.14),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, top + 10, 16, 20),
              child: Row(
                children: [
                  Material(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'الإشعارات',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onMarkAll != null)
                    Material(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: onMarkAll,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.done_all_rounded,
                                color: Brand.gold,
                                size: 18,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'قراءة الكل',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: Brand.gold,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Brand.ink,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(height: 1, color: kLine)),
        ],
      ),
    );
  }
}

// ───────────────────────── كارت الإشعار ─────────────────────────

class _NotifCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final int index;
  const _NotifCard({super.key, required this.doc, required this.index});

  @override
  State<_NotifCard> createState() => _NotifCardState();
}

class _NotifCardState extends State<_NotifCard> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.doc.data();
    final unread = m['read'] != true;
    final title = (m['title'] ?? '').toString();
    final body = (m['body'] ?? '').toString();
    final ts = m['createdAt'];
    final dt = ts is Timestamp ? ts.toDate() : null;
    final st = _kStyles[_kindOf(title, body)]!;
    final color = st.color;

    final card = GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: unread ? () => widget.doc.reference.update({'read': true}) : null,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: unread ? Colors.white : const Color(0xFFFBFCFB),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: unread ? color.withValues(alpha: 0.45) : kLine,
              width: unread ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: unread ? 0.16 : 0.04),
                blurRadius: unread ? 16 : 8,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // شريط جانبي بلون الحالة
                Container(
                  width: 6,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [color, color.withValues(alpha: 0.45)],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _KindIcon(style: st, glow: unread),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _KindChip(style: st),
                                      const Spacer(),
                                      if (unread) const _PulseDot(),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    title.isEmpty ? 'إشعار' : title,
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w900,
                                      color: Brand.ink,
                                    ),
                                  ),
                                  if (body.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      body,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.4,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (st.step >= 0) ...[
                          const SizedBox(height: 14),
                          _Stepper(
                            step: st.step,
                            color: color,
                            animate: unread,
                          ),
                        ],
                        if (dt != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 13,
                                color: kMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _stamp(dt),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: kMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // دخول متدرّج: كل كارت يطلع من تحت بتأخير بسيط.
    final step = widget.index > 8 ? 8 : widget.index;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + step * 60),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - v)),
          child: child,
        ),
      ),
      child: card,
    );
  }
}

class _KindIcon extends StatelessWidget {
  final _KindStyle style;
  final bool glow;
  const _KindIcon({required this.style, required this.glow});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [style.color, Color.lerp(style.color, Colors.black, 0.25)!],
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: style.color.withValues(alpha: 0.40),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Icon(style.icon, color: Colors.white, size: 24),
    );
  }
}

class _KindChip extends StatelessWidget {
  final _KindStyle style;
  const _KindChip({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: style.color,
        ),
      ),
    );
  }
}

/// نقطة نابضة بتوضّح إن الإشعار لسه ما اتقراش.
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 10 + 12 * t,
                height: 10 + 12 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Brand.gold.withValues(alpha: 0.40 * (1 - t)),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Brand.gold,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// شريط تتبع الطلب: استلام ← تجهيز ← في الطريق ← تسليم.
class _Stepper extends StatefulWidget {
  final int step;
  final Color color;
  final bool animate;
  const _Stepper({
    required this.step,
    required this.color,
    required this.animate,
  });

  @override
  State<_Stepper> createState() => _StepperState();
}

class _StepperState extends State<_Stepper>
    with SingleTickerProviderStateMixin {
  static const _labels = ['استلام', 'تجهيز', 'في الطريق', 'تسليم'];
  static const double _dot = 20;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Stepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _line({required bool visible, required bool active}) {
    return Container(
      height: 3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: !visible ? Colors.transparent : (active ? widget.color : kLine),
      ),
    );
  }

  Widget _dotFor(int i) {
    final color = widget.color;
    if (i < widget.step) {
      return Container(
        width: _dot,
        height: _dot,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
      );
    }
    if (i == widget.step) {
      return AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Transform.scale(
            scale: 1 + 0.18 * _c.value,
            child: Container(
              width: _dot,
              height: _dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35 + 0.25 * _c.value),
                    blurRadius: 8 + 6 * _c.value,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    return Container(
      width: _dot,
      height: _dot,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: kLine, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: _dot + 4,
                  child: Row(
                    children: [
                      Expanded(
                        child: _line(visible: i > 0, active: i <= widget.step),
                      ),
                      _dotFor(i),
                      Expanded(
                        child: _line(visible: i < 3, active: i < widget.step),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _labels[i],
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: i == widget.step
                        ? FontWeight.w900
                        : FontWeight.w600,
                    color: i == widget.step
                        ? widget.color
                        : (i < widget.step ? Brand.ink : kMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
