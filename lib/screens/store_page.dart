import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart' as audio;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_role.dart';
import '../models/product.dart';
import '../models/product_offer.dart';
import '../models/store.dart';
import '../services/cart_book.dart';
import '../services/cart_model.dart';
import '../services/catalog_service.dart';
import '../services/store_highlights.dart';
import '../services/catalog_sync.dart';
import '../services/image_service.dart';
import '../services/role_service.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/attachment_notice.dart';
import '../utils/format.dart';
import '../utils/img.dart';
import '../widgets/app_image.dart';
import '../widgets/empty_state.dart';
import '../widgets/option_groups_editor.dart';
import '../widgets/product_sheet.dart';
import '../widgets/qty_stepper.dart';
import 'cart_page.dart';
import '../widgets/cached_net_image.dart';

typedef _Json = Map<String, dynamic>;

/// تحويل نص السعر لرقم (يدعم الفاصلة العربية والأرقام العربية).
double? _parsePrice(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  var v = input.trim();
  for (var i = 0; i < 10; i++) {
    v = v.replaceAll(arabic[i], '$i');
  }
  v = v.replaceAll('٫', '.').replaceAll('،', '.').replaceAll(',', '.');
  return double.tryParse(v.replaceAll(' ', ''));
}

class StorePage extends StatefulWidget {
  final Store store;
  const StorePage({super.key, required this.store});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  static const _pageSize = 24;

  Store get store => widget.store;

  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  final List<Product> _items = [];

  /// آخر قائمة كاملة للمحل (عشان نراجع أسعار سلة راجعة من آخر مرة).
  List<Product>? _lastMenu;

  /// لو سلة المحل ده راجعة من «سلّاتي» والأسعار اتغيرت، نحدّثها ونبلّغ العميل.
  void _syncCartWithMenu() {
    final menu = _lastMenu;
    if (menu == null) return;
    final changes = cart.syncWithMenu(store.id, menu);
    if (changes.isNotEmpty && mounted) _say(changes.join('\n'));
  }
  DocumentSnapshot? _last;
  Timer? _debounce;
  bool _loading = false;
  bool _hasMore = true;
  bool _error = false;
  String _term = '';
  int _gen = 0;

  bool _collapsed = false; // الغلاف اتطوى: نظهر اسم المحل في الشريط العلوي
  bool _specialOpen = false; // كارت الطلب الخاص مطوي افتراضيًا
  bool _canEditStore = false; // المدير (كل المحلات) وصاحب المحل (محله) يشوفوا أزرار الإضافة والرفع

  final _specialRequestCtrl = TextEditingController();
  final _voiceRecorder = AudioRecorder();
  final _voicePreviewPlayer = audio.AudioPlayer();
  StreamSubscription<void>? _voicePreviewCompleteSub;
  bool _playingVoicePreview = false;
  int _specialQty = 1;
  String? _specialImageUrl;
  String? _voicePath;
  bool _recording = false;
  bool _sendingSpecial = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;

  DocumentReference<_Json> get _storeRef =>
      FirebaseFirestore.instance.collection('stores').doc(store.id);

  CollectionReference<_Json> get _col => _storeRef.collection('products');

  /// الأصناف المعروضة: الأصناف القديمة (المخزنة جوه المحل) + أصناف Firestore.
  List<Product> get _visible {
    final term = _term.toLowerCase();
    final legacy = store.products.where(
      (p) => term.isEmpty || p.name.toLowerCase().contains(term),
    );
    // الأصناف الموقوفة (available=false) بتظهر للمدير بس، والعميل ما يشوفهاش.
    final live = _items.where((p) => p.available || _canEditStore);
    return [...legacy, ...live];
  }

  @override
  void initState() {
    super.initState();
    _voicePreviewCompleteSub = _voicePreviewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingVoicePreview = false);
    });
    _checkAdmin();

    _scroll.addListener(() {
      final collapsed = _scroll.hasClients && _scroll.offset > 120;
      if (collapsed != _collapsed) setState(() => _collapsed = collapsed);

      _onScroll();
    });

    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    _specialRequestCtrl.dispose();
    _recordTimer?.cancel();
    _voiceRecorder.dispose();
    _voicePreviewCompleteSub?.cancel();
    _voicePreviewPlayer.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// المدير يشوف الأزرار في كل المحلات، وصاحب المحل في محله هو بس.
  /// ملاحظة: الحماية الحقيقية في قواعد Firestore، وده لإظهار الأزرار فقط.
  Future<void> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // الدور اتحدد قبل كده في RoleGate، فمفيش داعي لقراءة إضافية في كل زيارة محل.
    final known = RoleService.cachedFor(user.uid);
    if (known != null) {
      final ownsThis =
          known.role == AppRole.storeOwner && known.storeId == store.id;
      if ((known.role == AppRole.admin || ownsThis) && mounted) {
        setState(() => _canEditStore = true);
      }
      return;
    }

    try {
      final db = FirebaseFirestore.instance;
      final adminDoc = await db.collection('admins').doc(user.uid).get();
      if (adminDoc.exists) {
        if (mounted) setState(() => _canEditStore = true);
        return;
      }
      final ownerDoc = await db.collection('storeOwners').doc(user.uid).get();
      final data = ownerDoc.data();
      if (ownerDoc.exists &&
          (data?['active'] as bool?) != false &&
          (data?['storeId'] ?? '').toString() == store.id &&
          mounted) {
        setState(() => _canEditStore = true);
      }
    } catch (_) {}
  }

  Future<void> _pickSpecialImage() async {
    if (_sendingSpecial) return;
    if (!await _ensureCartForStore()) return;
    try {
      final url = await ImageService.pickAndUpload('special_requests', storeId: store.id);
      if (url != null && mounted) setState(() => _specialImageUrl = url);
    } catch (e) {
      _say('تعذر إرفاق الصورة: $e');
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_sendingSpecial) return;
    if (_recording) {
      try {
        final path = await _voiceRecorder.stop();
        _recordTimer?.cancel();
        if (path == null || path.isEmpty || !await File(path).exists()) {
          throw StateError('ملف التسجيل لم يُحفظ. حاول التسجيل مرة أخرى.');
        }
        if (!mounted) return;
        setState(() {
          _recording = false;
          _voicePath = path;
        });
      } catch (_) {
        if (mounted) setState(() => _recording = false);
        _say('تعذر إنهاء التسجيل.');
      }
      return;
    }
    try {
      if (!await _voiceRecorder.hasPermission()) {
        _say('اسمح باستخدام الميكروفون لتسجيل الرسالة الصوتية.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/wasally-request-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 22050,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordSeconds = 0;
        _voicePath = null;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        if (_recordSeconds >= 15) {
          _toggleVoiceRecording();
          return;
        }
        setState(() => _recordSeconds++);
      });
    } catch (e) {
      _say('تعذر بدء التسجيل: $e');
    }
  }

  Future<void> _toggleVoicePreview() async {
    final path = _voicePath;
    if (path == null || path.isEmpty || _sendingSpecial) return;
    try {
      if (_playingVoicePreview) {
        await _voicePreviewPlayer.pause();
        if (mounted) setState(() => _playingVoicePreview = false);
        return;
      }
      await _voicePreviewPlayer.stop();
      await _voicePreviewPlayer.setSource(audio.DeviceFileSource(path));
      await _voicePreviewPlayer.resume();
      if (mounted) setState(() => _playingVoicePreview = true);
    } catch (e) {
      if (mounted) {
        setState(() => _playingVoicePreview = false);
        _say('تعذر تشغيل التسجيل قبل الإرسال: $e');
      }
    }
  }

  Future<void> _sendSpecialRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    final description = _specialRequestCtrl.text.trim();
    if (user == null) {
      _say('سجّل الدخول الأول لإرسال الطلب.');
      return;
    }
    if (!await _ensureCartForStore()) return;
    if (description.isEmpty && _specialImageUrl == null && _voicePath == null) {
      _say('اكتب وصف المنتج أو أرفق صورة أو رسالة صوتية.');
      return;
    }
    if (_recording) {
      _say('أنه التسجيل الصوتي الأول.');
      return;
    }
    final sentVoicePath = _voicePath;
    setState(() => _sendingSpecial = true);
    try {
      String? voiceUrl;
      if (sentVoicePath != null) {
        final voiceFile = File(sentVoicePath);
        if (!await voiceFile.exists()) {
          throw StateError('ملف التسجيل غير موجود. سجّل الرسالة مرة أخرى.');
        }
        final bytes = await voiceFile.readAsBytes();
        // الصوت بيترفع على Cloudinary والطلب بيشيل الرابط بس (مستند صغير).
        voiceUrl = await ImageService.uploadVoice(bytes, storeId: store.id);
      }
      final attached = cart.setSpecialRequest(
        storeId: store.id,
        storeName: store.name,
        request: {
          'description': description,
          'quantity': _specialQty,
          if ((_specialImageUrl ?? '').isNotEmpty) 'imageUrl': _specialImageUrl,
          if ((voiceUrl ?? '').isNotEmpty) 'voiceUrl': voiceUrl,
          'createdAt': DateTime.now().toIso8601String(),
        },
      );
      if (!attached) {
        throw StateError(
          'سلتك فيها طلب من محل ${cart.storeName}. أفرغ السلة أو أنهِ الطلب الأول.',
        );
      }
      if (sentVoicePath != null) {
        await _voicePreviewPlayer.stop();
      }
      if (!mounted) return;
      setState(() {
        _playingVoicePreview = false;
        _specialRequestCtrl.clear();
        _specialQty = 1;
        _specialImageUrl = null;
        _voicePath = null;
      });
      if (sentVoicePath != null) {
        unawaited(() async {
          try {
            await File(sentVoicePath).delete();
          } catch (_) {}
        }());
      }
      _say('تمت إضافة الطلب الخاص إلى سلتك. كمّل الطلب لإرساله مع المنتجات.');
    } catch (e) {
      _say('تعذر إرسال الطلب الخاص: $e');
    } finally {
      if (mounted) setState(() => _sendingSpecial = false);
    }
  }

  Widget _specialRequestCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Brand.gold.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _specialOpen = !_specialOpen),
            child: Row(
              children: [
                Icon(Icons.edit_note_rounded, color: Brand.green, size: 26),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('طلب خاص / منتج غير موجود؟',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Brand.ink)),
                ),
                Icon(_specialOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: kMuted),
              ],
            ),
          ),
          if (_specialOpen) ...[
          const SizedBox(height: 4),
          Text('اكتب اللي محتاجه أو أرفق صورة أو رسالة صوتية وسيقوم المحل بتجهيزه لك',
              style: TextStyle(fontSize: 15, height: 1.5, color: Brand.ink)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Brand.gold.withValues(alpha: 0.6)),
            ),
            child: const Text(
              'تنبيه: سيتم حذف الصور والتسجيلات الصوتية المرفقة تلقائيًا من مساحة التخزين بعد تأكيد استلامك للطلب.',
              style: TextStyle(fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _specialRequestCtrl,
            minLines: 1,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
              hintText: 'مثال: رغيف حواوشي مخصوص بدون...',
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _sendingSpecial ? null : _pickSpecialImage,
                icon: const Icon(Icons.attach_file),
                label: Text(_specialImageUrl == null ? 'إرفاق صورة' : 'تم إرفاق صورة'),
              ),
              OutlinedButton.icon(
                onPressed: _sendingSpecial ? null : _toggleVoiceRecording,
                icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none),
                label: Text(_recording
                    ? 'إيقاف التسجيل ($_recordSeconds/15 ث)'
                    : (_voicePath == null ? 'رسالة صوتية' : 'تم تسجيل الصوت')),
              ),
              if (_voicePath != null)
                OutlinedButton.icon(
                  onPressed: _sendingSpecial ? null : _toggleVoicePreview,
                  icon: Icon(_playingVoicePreview ? Icons.pause : Icons.play_arrow),
                  label: Text(_playingVoicePreview ? 'إيقاف المعاينة' : 'معاينة الصوت'),
                ),
            ],
          ),
          if (_specialImageUrl != null || _voicePath != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('المرفقات جاهزة للإرسال',
                  style: TextStyle(color: Brand.greenDark, fontWeight: FontWeight.w700)),
            ),
          if (_specialImageUrl != null || _voicePath != null)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(kAttachmentsWillBeDeleted,
                  style: TextStyle(fontSize: 12, height: 1.4)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: _specialQty > 1 && !_sendingSpecial
                    ? () => setState(() => _specialQty--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_specialQty', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              IconButton(
                onPressed: _specialQty < 99 && !_sendingSpecial
                    ? () => setState(() => _specialQty++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _sendingSpecial ? null : _sendSpecialRequest,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B1A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                  shape: const StadiumBorder(),
                ),
                child: _sendingSpecial
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('إضافة للطلب', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          ],
        ],
      ),
    );
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _load();
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final term = v.trim();
      if (term == _term) return;
      _term = term;
      _load(reset: true);
    });
  }

  Product _parse(String id, _Json m) {
    final price = m['price'];
    final ends = m['offerEndsAt'];
    // العرض المنتهي بيتجاهله التطبيق: السعر بيرجع للأصلي وبيختفي الخصم والنص.
    final offer = resolveOfferDisplay(
      price: price is num ? price.toDouble() : 0,
      oldPrice: (m['oldPrice'] is num) ? (m['oldPrice'] as num).toDouble() : 0,
      text: (m['offerText'] ?? '').toString(),
      endsAt: ends is Timestamp ? ends.toDate() : null,
    );
    return Product(
      (m['name'] ?? '').toString(),
      offer.price,
      (m['image'] ?? '').toString(),
      id,
      m['available'] != false && m['isAvailable'] != false,
      offer.oldPrice,
      offer.text,
      offer.endsAt,
      (m['description'] ?? '').toString(),
      parseOptionGroups(m['optionGroups']),
    );
  }

  /// كل أصناف المحل من مستند القائمة المجمّع (للعميل فقط). null = استخدم الاستعلام المباشر.
  List<Product>? _menuAll;
  bool _menuUnavailable = false;

  /// المدير وصاحب المحل يكملوا على الاستعلام المباشر (بيانات لحظية لأزرار التعديل).
  /// لو الدور لسه مش معروف، الأمان إننا نستخدم الاستعلام المباشر.
  bool get _mayEdit {
    if (_canEditStore) return true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final known = RoleService.cachedFor(uid);
    if (known == null) return true;
    if (known.role == AppRole.admin || known.roles.contains(AppRole.admin)) {
      return true;
    }
    // صاحب المحل أو صاحب طلب الانضمام لنفس المحل.
    return known.storeId.isNotEmpty && known.storeId == store.id;
  }

  Future<List<Product>?> _menuProducts() async {
    if (_menuAll != null) return _menuAll;
    if (_menuUnavailable || _mayEdit) return null;
    final docs = await CatalogReader.menu(store.id);
    if (docs == null) {
      _menuUnavailable = true;
      return null;
    }
    final list = <Product>[];
    for (final d in docs) {
      try {
        list.add(_parse(d.id, d.data()));
      } catch (_) {}
    }
    list.sort((a, b) => a.name.compareTo(b.name));
    _menuAll = list;
    return list;
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _gen++;
      _items.clear();
      _last = null;
      _hasMore = true;
      _error = false;
    } else if (_loading || !_hasMore) {
      return;
    }
    final gen = _gen;
    setState(() => _loading = true);
    try {
      // العميل: قراءة واحدة لكل الأصناف (أو صفر لو القائمة متخزنة)، والبحث محلي من غير قراءات.
      final menu = await _menuProducts();
      if (menu != null) {
        if (!mounted || gen != _gen) return;
        final term = _term.toLowerCase();
        setState(() {
          _items
            ..clear()
            ..addAll(term.isEmpty
                ? menu
                : menu.where((p) => p.name.toLowerCase().contains(term)));
          _hasMore = false;
          _loading = false;
        });
        if (_term.isEmpty) {
          _lastMenu = menu;
          _syncCartWithMenu();
        }
        return;
      }

      Query<_Json> q = _col.orderBy('name');
      if (_term.isNotEmpty) {
        q = q
            .where('name', isGreaterThanOrEqualTo: _term)
            .where('name', isLessThan: '$_term\uf8ff');
      }
      final last = _last;
      if (last != null) q = q.startAfterDocument(last);
      final snap = await CatalogService.get(
        q.limit(_pageSize),
        'products/${store.id}/$_term/${last?.id ?? ''}',
        pageSize: _pageSize,
        cacheable: _term.isEmpty,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        for (final d in snap.docs) {
          _items.add(_parse(d.id, d.data()));
        }
        if (snap.docs.isNotEmpty) _last = snap.docs.last;
        _hasMore = snap.docs.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  /// قائمة المنتجات زي طلبات: صف لكل صنف (الاسم والسعر على الجنب، والصورة على الطرف).
  Widget _listSliver(List<Product> products) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverList.separated(
        itemCount: products.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: kLine),
        itemBuilder: (context, i) {
          final p = products[i];
          return _ProductRow(
            product: p,
            store: store,
            canEdit: _canEditStore && p.id.isNotEmpty,
            // الصنف اللي له خيارات بيفتح شاشة الاختيار؛ التاني بيتضاف مباشرة.
            onAdd: () =>
                p.hasOptions ? _openSheet(context, p) : _add(context, p),
            onTap: p.hasOptions || p.description.trim().isNotEmpty
                ? () => _openSheet(context, p)
                : null,
            onEdit: () => _showProductDialog(context, product: p),
          );
        },
      ),
    );
  }

  /// غلاف المحل: صورة كبيرة بتتطوي لشريط بلون السمة، وتحتها كارت المعلومات.
  Widget _cover() {
    final fallback = Container(
      decoration: BoxDecoration(gradient: Brand.headerGradient),
      alignment: Alignment.center,
      child: Icon(store.icon, size: 64, color: Colors.white54),
    );
    Widget circleBtn(IconData icon, VoidCallback onTap, String tip) => Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Tooltip(
            message: tip,
            child: Icon(icon, color: Brand.ink, size: 20),
          ),
        ),
      ),
    );
    return SliverAppBar(
      pinned: true,
      expandedHeight: 210,
      backgroundColor: Brand.green,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      leading: circleBtn(
        Icons.arrow_forward_rounded,
        () => Navigator.of(context).maybePop(),
        'رجوع',
      ),
      title: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _collapsed ? 1 : 0,
        child: Text(
          store.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            store.imageUrl.isEmpty
                ? fallback
                : CachedNetImage(
                    url: thumb(store.imageUrl, w: 900),
                    memCacheWidth: 900,
                    errorWidget: fallback,
                  ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.5],
                ),
              ),
            ),
          ],
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(20),
        child: Container(
          height: 20,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
      ),
    );
  }

  Widget _infoSection() {
    Widget pill(IconData icon, String text, {Color? color}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color ?? Brand.green),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Brand.ink,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            store.name,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Brand.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            store.category,
            style: TextStyle(fontSize: 13.5, color: kMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (store.rating > 0)
                pill(
                  Icons.star_rounded,
                  store.rating.toStringAsFixed(1),
                  color: const Color(0xFFFFA000),
                ),
              if (store.time.isNotEmpty)
                pill(Icons.access_time_rounded, store.time),
              pill(
                Icons.delivery_dining_rounded,
                'توصيل ${formatPrice(CartModel.deliveryFee)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final products = _visible;
    final Widget emptyContent;
    if (_loading) {
      emptyContent = Center(child: CircularProgressIndicator(color: kPrimary));
    } else if (_error) {
      emptyContent = EmptyState(
        icon: Icons.cloud_off,
        title: 'تعذر تحميل الأصناف',
        message: 'تأكد من الاتصال وحاول تاني.',
        actionLabel: 'إعادة المحاولة',
        onAction: () => _load(reset: true),
      );
    } else {
      emptyContent = EmptyState(
        icon: Icons.inventory_2_outlined,
        title: _term.isEmpty ? 'مفيش منتجات في المحل ده لسه' : 'مفيش نتايج للبحث',
        message: _term.isEmpty
            ? (_canEditStore
                ? 'ابدأ بإضافة صنف من زر + أو ارفع ملف أصناف.'
                : 'جرّب محل تاني أو ارجع بعد شوية.')
            : 'جرّب كلمة تانية.',
      );
    }

    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        _cover(),
        SliverToBoxAdapter(child: _infoSection()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'ابحث عن صنف...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0xFFF4F5F7),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: BorderSide(color: Brand.green, width: 1.5),
                      ),
                    ),
                  ),
                ),
                if (_canEditStore) ...[
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => _showProductDialog(context),
                    icon: const Icon(Icons.add, color: Colors.white),
                    tooltip: 'إضافة صنف جديد',
                    style: IconButton.styleFrom(backgroundColor: Brand.green),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    onPressed: _showUploadGuide,
                    icon: const Icon(Icons.upload_file, color: Colors.white),
                    tooltip: 'رفع ملف أصناف (CSV)',
                    style: IconButton.styleFrom(backgroundColor: Brand.goldDeep),
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _specialRequestCard()),
        if (_loading && _items.isNotEmpty)
          SliverToBoxAdapter(
            child: LinearProgressIndicator(minHeight: 2, color: kPrimary),
          ),
        if (products.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: emptyContent,
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Text(
                'المنتجات',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Brand.ink,
                ),
              ),
            ),
          ),
          _listSliver(products),
        ],
      ],
    );
  }

  // ───────────────────── شرح ملف الرفع ─────────────────────

  static const _sampleCsv =
      'اسم الصنف,السعر,رابط الصورة\n'
      'زيت محرك 5 لتر,450,https://example.com/oil.jpg\n'
      'فلتر زيت,85,\n'
      'شمعات بوجيه,230,\n';

  /// نافذة بتشرح شكل الملف قبل ما المستخدم يختاره.
  Future<void> _showUploadGuide() async {
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'رفع أصناف من ملف',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Brand.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'نوع الملف: CSV (أو TXT). لو عندك ملف Excel: '
                'من Excel اختر حفظ باسم ثم CSV UTF-8.',
                style: TextStyle(fontSize: 13.5, height: 1.5, color: kMuted),
              ),
              const SizedBox(height: 16),
              Text(
                'ترتيب الأعمدة',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Brand.ink,
                ),
              ),
              const SizedBox(height: 10),
              const _ColumnRow(
                letter: '1',
                title: 'العمود الأول: اسم الصنف',
                note: 'إجباري',
                required: true,
              ),
              const _ColumnRow(
                letter: '2',
                title: 'العمود التاني: السعر بالجنيه',
                note: 'إجباري، أرقام فقط',
                required: true,
              ),
              const _ColumnRow(
                letter: '3',
                title: 'العمود التالت: رابط الصورة',
                note: 'اختياري، ممكن تسيبه فاضي',
                required: false,
              ),
              const SizedBox(height: 14),
              Text(
                'مثال',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Brand.ink,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8F7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kLine),
                ),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(
                    _sampleCsv,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.6,
                      color: Brand.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const _Tip('السطر الأول (العناوين) بيتجاهل تلقائيًا.'),
              const _Tip('كل صنف في سطر لوحده، والأعمدة مفصولة بفاصلة (,).'),
              const _Tip('ما تكتبش فاصلة جوه اسم الصنف.'),
              const _Tip('أي سطر من غير سعر صحيح أكبر من صفر بيتجاهل.'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          const ClipboardData(text: _sampleCsv),
                        );
                        _say('تم نسخ المثال. الصقه في ملف وسمّيه products.csv');
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('نسخ المثال'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      icon: const Icon(Icons.upload_file, size: 20),
                      label: const Text('اختيار الملف'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (go == true) await _uploadBatchProducts();
  }

  /// رفع المنتجات دفعة واحدة عبر ملف CSV (على دفعات من 400).
  Future<void> _uploadBatchProducts() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true, // بدونها بيرجع bytes فاضي على الموبايل
      );

      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.single.bytes;
      if (bytes == null) {
        _say('تعذر قراءة الملف. حاول مرة تانية.');
        return;
      }

      var content = utf8.decode(bytes, allowMalformed: true);
      if (content.startsWith('\uFEFF')) content = content.substring(1);

      var highlightsOk = true;
      final rows = <_Json>[];
      for (final line in content.split(RegExp(r'\r?\n'))) {
        if (line.trim().isEmpty) continue;
        final parts = line.split(',');
        if (parts.length < 2) continue;

        final name = parts[0].trim();
        final price = _parsePrice(parts[1]);

        // الصفوف بدون سعر صحيح (وعنوان الأعمدة) بتتجاهل.
        if (name.isEmpty || price == null || price <= 0) continue;

        final image = parts.length > 2 ? parts[2].trim() : '';

        rows.add({
          'name': name,
          'price': price,
          'image': image,
          'isAvailable': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (rows.isEmpty) {
        _say('لم يتم العثور على أصناف صالحة داخل الملف.');
        return;
      }

      var uploaded = 0;
      Object? uploadError;
      // رفع جماعي: إعادة بناء القائمة المجمّعة مرة واحدة بعده (والعلامة بتضمنها لو التطبيق اتقفل).
      await CatalogSync.markPending(store.id);
      try {
        for (var start = 0; start < rows.length; start += 400) {
          final end = start + 400 > rows.length ? rows.length : start + 400;
          final batch = FirebaseFirestore.instance.batch();

          for (var i = start; i < end; i++) {
            batch.set(_col.doc(), rows[i]);
          }

          // العداد يتحدث مع كل دفعة.
          batch.update(_storeRef, {
            'productCount': FieldValue.increment(end - start),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          await batch.commit();
          uploaded += end - start;
        }
      } catch (e) {
        uploadError = e;
      }

      if (uploaded > 0) {
        // القائمة ← ملخص العروض ← الفهرس ← رقم الإصدار (ما بيرميش استثناءات).
        highlightsOk = await CatalogSync.afterProductsChanged(store.id);
        _load(reset: true);
      }

      if (uploadError != null) {
        debugPrint('CSV upload error: $uploadError');
        if (uploaded == 0) {
          _say('حدث خطأ أثناء رفع الملف. تأكد أن حسابك مدير وحاول تاني.');
        } else {
          _say(StoreHighlights.withNote(
            'تم رفع $uploaded صنف قبل حدوث خطأ؛ باقي الملف ما اترفعش',
            highlightsOk,
          ));
        }
        return;
      }

      _say(StoreHighlights.withNote('تم رفع $uploaded صنف بنجاح', highlightsOk));
    } catch (e) {
      debugPrint('CSV upload error: $e');
      _say('حدث خطأ أثناء رفع الملف. تأكد أن حسابك مدير وحاول تاني.');
    }
  }

  /// نافذة إضافة وتعديل صنف: الصورة بتترفع من معرض الجهاز بدل الرابط.
  void _showProductDialog(BuildContext context, {Product? product}) {
    final nameController = TextEditingController(text: product?.name ?? '');
    final priceController = TextEditingController(
      text: product != null ? product.price.toString() : '',
    );
    final descController = TextEditingController(
      text: product?.description ?? '',
    );
    var optionGroups = List<OptionGroup>.of(product?.optionGroups ?? const []);
    var image = product?.imageUrl ?? '';
    var uploading = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) {
          Future<void> pickImage() async {
            if (uploading) return;
            setLocal(() => uploading = true);
            try {
              final url = await ImageService.pickAndUpload(
                'products',
                storeId: store.id,
              );
              if (url != null) image = url;
            } catch (e) {
              debugPrint('Product image upload error: $e');
              _say('تعذر رفع الصورة. حاول مرة تانية.');
            } finally {
              if (dialogCtx.mounted) setLocal(() => uploading = false);
            }
          }

          return AlertDialog(
            title: Text(product == null ? 'إضافة صنف جديد' : 'تعديل الصنف'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: uploading ? null : pickImage,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AppImage(
                          url: image,
                          fallbackIcon: Icons.add_a_photo_outlined,
                          color: kPrimary,
                          width: 120,
                          height: 120,
                          iconSize: 42,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        if (uploading)
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          )
                        else
                          Positioned(
                            bottom: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                image.isEmpty ? Icons.add_a_photo : Icons.edit,
                                size: 16,
                                color: kPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    image.isEmpty
                        ? 'اضغط لاختيار صورة من الجهاز'
                        : 'اضغط لتغيير الصورة',
                    style: TextStyle(fontSize: 12, color: kMuted),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'اسم الصنف'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    decoration: const InputDecoration(labelText: 'السعر'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'وصف الصنف (اختياري)',
                    ),
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final res = await showOptionGroupsEditor(
                        dialogCtx,
                        optionGroups,
                      );
                      if (res != null) setLocal(() => optionGroups = res);
                    },
                    icon: const Icon(Icons.tune),
                    label: Text(
                      optionGroups.isEmpty
                          ? 'خيارات الصنف (سكر، إضافات...)'
                          : 'خيارات الصنف (${optionGroups.length})',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: uploading
                    ? null
                    : () async {
                        final name = nameController.text.trim();
                        final price = _parsePrice(priceController.text);

                        if (name.isEmpty || price == null || price <= 0) {
                          _say('اكتب اسم الصنف وسعر صحيح أكبر من صفر.');
                          return;
                        }

                        try {
                          final newRef = product == null ? _col.doc() : null;
                          final savedId = product?.id ?? newRef!.id;
                          await CatalogSync.markPending(store.id, [savedId]);
                          if (newRef != null) {
                            final batch = FirebaseFirestore.instance.batch();
                            batch.set(newRef, {
                              'name': name,
                              'price': price,
                              'image': image,
                              'isAvailable': true,
                              if (descController.text.trim().isNotEmpty)
                                'description': descController.text.trim(),
                              if (optionGroups.isNotEmpty)
                                'optionGroups': optionGroups
                                    .map((g) => g.toMap())
                                    .toList(),
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                            batch.update(_storeRef, {
                              'productCount': FieldValue.increment(1),
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                            await batch.commit();
                          } else if (savedId.isNotEmpty) {
                            await _col.doc(savedId).update({
                              'name': name,
                              'price': price,
                              'image': image,
                              'description': descController.text.trim(),
                              'optionGroups': optionGroups
                                  .map((g) => g.toMap())
                                  .toList(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                          }

                          // القائمة ← ملخص العروض ← الفهرس ← رقم الإصدار.
                          final highlightsOk =
                              await CatalogSync.afterProductsChanged(
                            store.id,
                            productIds: [savedId],
                          );

                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                          _load(reset: true);
                          if (!highlightsOk) {
                            _say(StoreHighlights.withNote(
                                'تم حفظ الصنف', false));
                          }
                        } catch (e) {
                          debugPrint('Save product error: $e');
                          _say('تعذر حفظ الصنف. تأكد أن حسابك مدير.');
                        }
                      },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// بيفتح شاشة الصنف (الوصف والخيارات والكمية) وبيضيف السطر المختار للسلة.
  void _openSheet(BuildContext context, Product p) {
    showProductSheet(
      context,
      product: p,
      storeName: store.name,
      onAdd: (line, qty) => _add(context, line, qty: qty),
    );
  }

  Future<void> _add(BuildContext context, Product p, {int qty = 1}) async {
    if (!store.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('المحل مغلق الآن. تقدر تتفرج على الأصناف وتطلب لما يفتح.'),
      ));
      return;
    }
    carts.rememberStore(store);
    if (!cart.canAddFrom(store.id) && !await _ensureCartForStore()) return;
    cart.rememberLoadedProducts(store.id, _visible);
    cart.add(p, storeId: store.id, storeName: store.name, qty: qty);
  }

  /// العميل معاه سلة من محل تاني: بننبهه بالتفاصيل، ولو وافق سلته القديمة تتحفظ في «سلّاتي»
  /// زي ما هي ونبدأ (أو نكمّل) سلة للمحل ده. مفيش حاجة بتتمسح من غير ما يختار.
  Future<bool> _ensureCartForStore() async {
    carts.rememberStore(store);
    if (cart.canAddFrom(store.id)) return true;
    final other = cart.storeName ?? 'محل تاني';
    final saved = carts.parkedFor(store.id);
    final otherCarts = carts.cartsCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'خلي بالك: معاك سلة من $other',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سلة $other فيها ${cart.count} صنف بـ ${formatPrice(cart.subtotal)}'
              '${cart.specialRequest != null ? ' + طلب خاص' : ''}.',
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              saved != null
                  ? 'عندك كمان سلة محفوظة من ${store.name} فيها ${saved.count} صنف، هنكمّل عليها.'
                  : 'لو كمّلت من ${store.name} هنعملك سلة جديدة، وسلة $other هتتحفظ في «سلّاتي» زي ما هي.',
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              'كل سلة بتتطلب لوحدها وليها رسوم توصيل لوحدها. '
              'قبل التأكيد هتلاقي كل سلالك${otherCarts > 1 ? ' ($otherCarts دلوقتي)' : ''} في «سلّاتي»: تأكد أو تعدّل أو تمسح.',
              style: TextStyle(height: 1.5, color: kMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(saved != null ? 'كمّل سلة ${store.name}' : 'سلة جديدة وكمّل'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return false;
    carts.switchTo(store.id);
    _syncCartWithMenu();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: store.isOpen
          ? _body()
          : Column(
              children: [
                Expanded(child: _body()),
                SafeArea(
                  top: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: kDanger.withValues(alpha: 0.08),
                    child: Text(
                      'المحل مغلق الآن ومش بيستقبل طلبات. تقدر تتفرج على الأصناف.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kDanger, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: ListenableBuilder(
        listenable: cart,
        builder: (context, _) {
          if (cart.isEmpty) return const SizedBox.shrink();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const Scaffold(body: CartPage(showBackButton: true)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('عرض السلة (${cart.count})'),
                      Text(
                        formatPrice(cart.subtotal),
                        style: TextStyle(
                          color: Brand.gold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// سطر بيشرح عمود في ملف الرفع.
class _ColumnRow extends StatelessWidget {
  final String letter;
  final String title;
  final String note;
  final bool required;
  const _ColumnRow({
    required this.letter,
    required this.title,
    required this.note,
    required this.required,
  });

  @override
  Widget build(BuildContext context) {
    final color = required ? Brand.green : kMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              letter,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Brand.ink,
                  ),
                ),
                Text(
                  note,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: required ? Brand.goldDeep : kMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// نقطة ملاحظة صغيرة.
class _Tip extends StatelessWidget {
  final String text;
  const _Tip(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: Brand.gold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: Brand.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// صف الصنف زي طلبات: النص (الاسم والسعر) على الجنب، والصورة على الطرف وزر الإضافة فوقها.
class _ProductRow extends StatelessWidget {
  final Product product;
  final Store store;
  final bool canEdit;
  final VoidCallback onAdd;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  const _ProductRow({
    required this.product,
    required this.store,
    required this.canEdit,
    required this.onAdd,
    required this.onEdit,
    this.onTap,
  });

  Widget _fallback() => Container(
    color: Brand.green.withValues(alpha: 0.10),
    child: Center(child: Icon(store.icon, color: Brand.green, size: 34)),
  );

  Widget _image() {
    if (product.imageUrl.isEmpty) return _fallback();
    return CachedNetImage(
      url: thumb(product.imageUrl, w: 300),
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: 300,
      placeholder: _fallback(),
      errorWidget: _fallback(),
    );
  }

  Widget _addControl() {
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        final qty = cart.qtyOf(product);
        if (qty == 0) {
          return Material(
            color: Colors.white,
            elevation: 3,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onAdd,
              child: SizedBox(
                width: 34,
                height: 34,
                child: Icon(Icons.add, color: Brand.green, size: 22),
              ),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: QtyStepper(
            qty: qty,
            onAdd: onAdd,
            onRemove: () => cart.remove(product),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final discount = product.hasOffer
        ? ((1 - product.price / product.oldPrice) * 100).round()
        : 0;
    return Opacity(
      opacity: product.available ? 1 : 0.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                      color: Brand.ink,
                    ),
                  ),
                  if (product.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      product.description.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, height: 1.35, color: kMuted),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        formatPrice(product.price),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Brand.ink,
                        ),
                      ),
                      if (product.hasOffer) ...[
                        const SizedBox(width: 8),
                        Text(
                          formatPrice(product.oldPrice),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: kMuted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (discount > 0 || product.offerText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (discount > 0) _badge('خصم $discount%', kDanger),
                        if (product.offerText.isNotEmpty)
                          _badge(product.offerText, Brand.goldDeep),
                      ],
                    ),
                  ],
                  if (!product.available) ...[
                    const SizedBox(height: 6),
                    Text(
                      'غير متاح حاليًا',
                      style: TextStyle(fontSize: 12, color: kMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 104,
              height: 104,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _image(),
                    ),
                  ),
                  PositionedDirectional(
                    bottom: -6,
                    end: -6,
                    child: _addControl(),
                  ),
                  if (canEdit)
                    PositionedDirectional(
                      top: 4,
                      start: 4,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.edit,
                            size: 14,
                            color: Colors.white,
                          ),
                          onPressed: onEdit,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
