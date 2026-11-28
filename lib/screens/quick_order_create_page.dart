import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quick_price_guide.dart';
import '../theme/app_tokens.dart';
import '../services/user_service.dart';
import '../services/location_picker.dart';
import 'quick_order_customer_detail_page.dart';
import 'errand_create_page.dart';
import '../services/quick_order_api.dart';
import '../widgets/quick_price_picker.dart';
import '../widgets/app_ui.dart';
import '../widgets/quick_order_promo.dart' show kQuickPhotoOrdersEnabled;
import '../services/image_service.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import '../widgets/app_snack.dart';
import '../widgets/app_notice.dart';
import '../services/route_key.dart';

/// طريقة إرسال الطلب السريع.
/// [callMe] = «كلّمني»: العميل مش هيكتب حاجة، المندوب يتصل بيه وياخد الطلب.
enum QuickOrderMethod { voice, write, camera, gallery, callMe }

enum _AddressMode { mine, other }

/// Separate quick-order entry point; never adds items to the regular store cart.
class QuickOrderCreatePage extends StatefulWidget {
  const QuickOrderCreatePage({
    super.key,
    this.prefillFromAccount = true,
    this.initialMethod,
  });

  /// للاختبارات فقط: تعطيل ملء بيانات الحساب (يحتاج Firebase).
  final bool prefillFromAccount;

  /// للاختبارات/لقطات الشاشة: طريقة مختارة من الأول.
  final QuickOrderMethod? initialMethod;

  @override
  State<QuickOrderCreatePage> createState() => _QuickOrderCreatePageState();
}

class _QuickOrderCreatePageState extends State<QuickOrderCreatePage> {
  static const _lastAreaKey = 'quick_last_area';

  final _name = TextEditingController();
  final _area = TextEditingController();
  final _phone = TextEditingController();

  /// «عنوان تاني» المكتوب.
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _stores = [_QuickStoreDraft()];
  bool _submitting = false;

  /// عنوان الحساب المحفوظ (لـ«على عنواني» لو الموقع ما اتحددش).
  String _savedAddress = '';
  _AddressMode _addressMode = _AddressMode.mine;
  PickedLocation? _picked;
  bool _locating = false;

  late QuickOrderMethod? _method = widget.initialMethod;
  late bool _methodsOpen = widget.initialMethod == null;

  /// «صوّر طلبك»: روابط الصور المرفوعة (لحد 3).
  final List<String> _photos = [];
  bool _uploadingPhoto = false;
  static const _maxPhotos = 3;

  // التسجيل الصوتي (بيتعمل أول ما يتطلب بس).
  AudioRecorder? _recorderInstance;
  audio.AudioPlayer? _playerInstance;
  StreamSubscription<void>? _playerDone;
  AudioRecorder get _voiceRecorder => _recorderInstance ??= AudioRecorder();
  audio.AudioPlayer get _voicePlayer {
    final existing = _playerInstance;
    if (existing != null) return existing;
    final player = _playerInstance = audio.AudioPlayer();
    _playerDone = player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingVoice = false);
    });
    return player;
  }

  Timer? _voiceTimer;
  String? _voicePath;
  String? _uploadedVoiceUrl;
  bool _recording = false;
  bool _playingVoice = false;
  static const _maxVoiceSeconds = 60;
  int _voiceSeconds = 0;
  int _voiceLength = 0;
  String? _pendingOrderId;

  @override
  void initState() {
    super.initState();
    _restoreArea();
    if (!widget.prefillFromAccount) return;
    _name.text = FirebaseAuth.instance.currentUser?.displayName ?? '';
    _prefillContact();
  }

  /// آخر حي اتطلب عليه (محليًا) عشان العميل ما يكتبوش كل مرة.
  Future<void> _restoreArea() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_lastAreaKey) ?? '';
      if (mounted && _area.text.trim().isEmpty && last.isNotEmpty) {
        setState(() => _area.text = last);
      }
    } catch (_) {}
  }

  Future<void> _prefillContact() async {
    final profile = await UserService.load();
    if (!mounted) return;
    // Never overwrite values the customer has already typed.
    if (profile.name.trim().isNotEmpty &&
        (_name.text.trim().isEmpty ||
         _name.text.trim() == (FirebaseAuth.instance.currentUser?.displayName ?? '').trim())) {
      _name.text = profile.name;
    }
    if (_phone.text.trim().isEmpty) _phone.text = profile.phone;
    setState(() {
      _savedAddress = profile.address.trim();
      // البيانات المحفوظة بتظهر كملخص، و«تعديل» يفتح الحقول.
      _contactCollapsed = _contactComplete;
    });
  }

  @override
  void dispose() {
    _voiceTimer?.cancel();
    _playerDone?.cancel();
    _recorderInstance?.dispose();
    _playerInstance?.dispose();
    final path = _voicePath;
    if (path != null) File(path).delete().catchError((_) => File(path));
    for (final c in [_name, _area, _phone, _address, _notes]) {
      c.dispose();
    }
    for (final store in _stores) {
      store.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    if (_uploadingPhoto || _photos.length >= _maxPhotos) return;
    setState(() => _uploadingPhoto = true);
    try {
      final url = await ImageService.pickAndUploadQuickRequest(source: source);
      if (url != null && mounted) setState(() => _photos.add(url));
    } catch (error) {
      if (mounted) {
        _say(error is StateError ? error.message : 'تعذر رفع الصورة، جرّب تاني.');
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _toggleVoice() async {
    if (_submitting) return;
    if (_recording) {
      try {
        final path = await _voiceRecorder.stop();
        _voiceTimer?.cancel();
        if (path == null || !await File(path).exists()) throw StateError('التسجيل لم يُحفظ.');
        final previous = _voicePath;
        if (mounted) {
          setState(() {
            _recording = false;
            _voicePath = path;
            _voiceLength = _voiceSeconds;
            _uploadedVoiceUrl = null;
          });
        }
        if (previous != null && previous != path) {
          await File(previous).delete().catchError((_) => File(previous));
        }
      } catch (e) {
        if (mounted) setState(() => _recording = false);
        _say('تعذر حفظ التسجيل الصوتي.');
      }
      return;
    }
    try {
      if (!await _voiceRecorder.hasPermission()) {
        _say('اسمح باستخدام الميكروفون لتسجيل طلبك.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/quick-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _playerInstance?.stop();
      await _voiceRecorder.start(const RecordConfig(
        encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 22050, numChannels: 1,
      ), path: path);
      if (!mounted) return;
      setState(() { _recording = true; _playingVoice = false; _voiceSeconds = 0; });
      _voiceTimer?.cancel();
      _voiceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_recording) { timer.cancel(); return; }
        if (_voiceSeconds + 1 >= _maxVoiceSeconds) {
          setState(() => _voiceSeconds = _maxVoiceSeconds);
          timer.cancel();
          _toggleVoice();
          return;
        }
        setState(() => _voiceSeconds++);
      });
    } catch (_) { _say('تعذر بدء التسجيل. حاول مرة تانية.'); }
  }

  Future<void> _previewVoice() async {
    final path = _voicePath;
    if (path == null || _submitting) return;
    try {
      if (_playingVoice) {
        await _voicePlayer.stop();
        if (mounted) setState(() => _playingVoice = false);
      } else {
        await _voicePlayer.stop();
        await _voicePlayer.setSource(audio.DeviceFileSource(path));
        await _voicePlayer.resume();
        if (mounted) setState(() => _playingVoice = true);
      }
    } catch (_) { _say('تعذر تشغيل التسجيل.'); }
  }

  Future<void> _deleteVoice() async {
    await _playerInstance?.stop();
    final path = _voicePath;
    if (mounted) {
      setState(() { _voicePath = null; _uploadedVoiceUrl = null; _playingVoice = false; _voiceLength = 0; });
    }
    if (path != null) await File(path).delete().catchError((_) => File(path));
  }

  /// «على عنواني»: موقع الجهاز مرة واحدة → الحي يتكتب لوحده والعنوان على الخريطة.
  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final picked = await DeliveryLocationPicker.locate(context);
      if (!mounted || picked == null) return;
      setState(() {
        _picked = picked;
        _addressMode = _AddressMode.mine;
        if (picked.area.isNotEmpty) _area.text = picked.area;
      });
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(appSnack(message));
  }

  /// العنوان اللي هيتبعت للمندوب (بيظهر له بعد القبول بس).
  String? get _deliveryAddress {
    if (_addressMode == _AddressMode.other) {
      final typed = _address.text.trim();
      return typed.length >= 5 ? typed : null;
    }
    final picked = _picked;
    if (picked != null) {
      final suffix = ' — الموقع: ${picked.coordinates}';
      var text = picked.address.trim();
      if (text.length + suffix.length > 300) text = text.substring(0, 300 - suffix.length);
      return '$text$suffix';
    }
    return _savedAddress.length >= 5 ? _savedAddress : null;
  }

  bool get _hasWritten => _stores.any((store) => store.hasItems);
  bool get _callMe => _method == QuickOrderMethod.callMe;
  bool get _hasContent =>
      _callMe || _photos.isNotEmpty || _voicePath != null || _hasWritten;

  Future<void> _submit() async {
    if (_submitting) return;
    if (_recording) {
      _say('اضغط إيقاف التسجيل قبل إرسال الطلب.');
      return;
    }
    if (_uploadingPhoto) {
      _say('استنى لحد ما الصورة تترفع');
      return;
    }
    if (!_hasContent) {
      setState(() => _methodsOpen = true);
      _say('اختار تبعت طلبك إزاي: بصوتك أو مكتوب أو بالصور، أو «كلّمني» وإحنا نتصل بيك');
      return;
    }
    final media = _photos.isNotEmpty || _voicePath != null || _callMe;
    final stores = _stores.where((s) => s.hasItems || s.name.isNotEmpty).toList();
    if (!media && stores.any((s) => !s.hasItems)) {
      _say('اكتب الطلبات لكل محل، أو امسح المحل الفاضي');
      return;
    }
    if (_area.text.trim().isEmpty) {
      _say('اكتب الحي، أو دوس «حدد تلقائي»');
      return;
    }
    final address = _deliveryAddress;
    if (address == null) {
      _say(_addressMode == _AddressMode.other
          ? 'اكتب العنوان اللي المندوب هيجيلك عليه'
          : 'دوس «حدد موقعي» أو اختار «عنوان تاني»');
      return;
    }
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _contactCollapsed = false);
      _say('اكتب اسمك ورقم الموبايل');
      return;
    }
    final phone = _phone.text.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^01[0125][0-9]{8}$').hasMatch(phone)) {
      setState(() => _contactCollapsed = false);
      _say('اكتب رقم موبايل مصري صحيح من 11 رقم، مثل 01012345678');
      return;
    }
    setState(() => _submitting = true);
    try {
      // The ID is created once per submission, so the same request can be
      // retried without creating duplicate orders.
      final user = _currentUserId();
      final id = _pendingOrderId ??= '${user}_${DateTime.now().microsecondsSinceEpoch.toRadixString(16).padLeft(16, '0')}';
      if (_voicePath != null) {
        _uploadedVoiceUrl ??= await ImageService.uploadQuickVoice(await File(_voicePath!).readAsBytes());
      }
      await QuickOrderApi.create({
        'orderId': id,
        'customerName': _name.text.trim(),
        'area': _area.text.trim(),
        'notes': _notes.text.trim(),
        'stores': stores.isEmpty
            ? [_QuickStoreDraft.empty]
            : [for (final store in stores) store.toWorkerMap()],
        if (_photos.isNotEmpty) 'customerImages': List<String>.of(_photos),
        if (_uploadedVoiceUrl != null) 'customerVoiceUrl': _uploadedVoiceUrl,
        if (_callMe) 'callMe': true,
        'contact': {
          'userName': _name.text.trim(),
          'phone': phone,
          'address': address,
        },
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastAreaKey, _area.text.trim());
      } catch (_) {}
      if (!mounted) return;
      showAppNotice(
        title: _callMe ? 'تم إرسال طلبك' : 'تم إرسال طلبك السريع',
        message: _callMe
            ? 'المندوب هيكلمك على رقمك قريب عشان ياخد منك الطلب.'
            : 'تقدر تتابع طلبك من هنا، والمندوب هيتواصل معاك أول ما يقبله.',
      );
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        settings: RouteSettings(name: RouteKey.quickOrder(id)),
        builder: (_) => QuickOrderCustomerDetailPage(orderId: id),
      ));
    } catch (error) {
      _say('تعذر إرسال الطلب: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _currentUserId() {
    // The authenticated token is obtained by QuickOrderApi.
    // Read the uid only to create a stable, user-prefixed order ID.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw StateError('سجل دخولك أولًا');
    return uid;
  }

  // ───────────────────────── الواجهة ─────────────────────────

  bool _contactCollapsed = false;
  bool _showNotes = false;

  bool get _contactComplete =>
      _name.text.trim().isNotEmpty && _phone.text.trim().isNotEmpty;

  static String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('طلباتك على السريع')),
    body: ListView(
      key: const Key('quick-create-list'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
      children: [
        const _QuickIntro(),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('quick-to-errand'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ErrandCreatePage()),
            ),
            icon: const Icon(Icons.delivery_dining_outlined),
            label: const Text('عايز مشوار من غير مشتريات؟ مشوارك علينا'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _StepTitle(number: 1, title: 'تحب تبعت طلبك إزاي؟'),
        _methodPicker(),
        _methodPanels(),
        const SizedBox(height: AppSpacing.lg),
        const _StepTitle(number: 2, title: 'المندوب يجيلك فين؟'),
        _deliveryCard(),
        const SizedBox(height: AppSpacing.sm),
        _contactCard(),
        if (!_showNotes)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('quick-add-note'),
              onPressed: () => setState(() => _showNotes = true),
              icon: const Icon(Icons.sticky_note_2_outlined),
              label: const Text('أضف ملاحظة للمندوب'),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'ملاحظات للمندوب (اختياري)',
                hintText: 'مثال: لو الصنف مش موجود كلمني الأول',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        const _FeesNote(),
      ],
    ),
    // الزر ثابت تحت ويستخبى ورا الكيبورد بدل ما ياكل مساحة الكتابة.
    bottomNavigationBar: SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.md),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Color(0x141E1638), blurRadius: 12, offset: Offset(0, -3))],
        ),
        child: FilledButton.icon(
          key: const Key('quick-submit'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                )
              : const Icon(Icons.send_rounded),
          label: Text(_submitting ? 'جارٍ الإرسال...' : 'اطلب دلوقتي'),
        ),
      ),
    ),
  );

  // ───────── ١) طريقة الطلب: خانة بتنسدل ─────────

  static const _methodInfo = {
    QuickOrderMethod.voice: (Icons.mic_rounded, 'بصوتك', 'سجّل اللي محتاجه لحد دقيقة'),
    QuickOrderMethod.write: (Icons.edit_note_rounded, 'تكتبه', 'اكتب الأصناف والكميات'),
    QuickOrderMethod.camera: (Icons.photo_camera_rounded, 'تصوّره', 'صوّر ورقة الطلبات بالكاميرا'),
    QuickOrderMethod.gallery: (Icons.photo_library_rounded, 'تبعت صورة', 'اختار صورة من المعرض'),
    QuickOrderMethod.callMe: (Icons.phone_callback_rounded, 'كلّمني',
        'مش فاضي تكتب؟ دوس هنا والمندوب يتصل بيك ياخد طلبك'),
  };

  static const _methodHeader = {
    QuickOrderMethod.voice: 'هتبعته بصوتك',
    QuickOrderMethod.write: 'هتكتبه',
    QuickOrderMethod.camera: 'هتصوّره بالكاميرا',
    QuickOrderMethod.gallery: 'هتبعت صورة من المعرض',
    QuickOrderMethod.callMe: 'المندوب هيكلمك ياخد طلبك',
  };

  List<QuickOrderMethod> get _methods => [
        QuickOrderMethod.voice,
        QuickOrderMethod.write,
        if (kQuickPhotoOrdersEnabled) ...[QuickOrderMethod.camera, QuickOrderMethod.gallery],
        QuickOrderMethod.callMe,
      ];

  /// ملخص اللي اتضاف بالطريقة دي (عشان لو غيّر الطريقة يعرف إن طلبه محفوظ).
  String? _added(QuickOrderMethod m) => switch (m) {
        QuickOrderMethod.voice => _voicePath == null ? null : 'تسجيل ${_clock(_voiceLength)}',
        QuickOrderMethod.write => _hasWritten ? 'مكتوب' : null,
        QuickOrderMethod.camera || QuickOrderMethod.gallery =>
          _photos.isEmpty ? null : '${_photos.length} ${_photos.length == 1 ? 'صورة' : 'صور'}',
        QuickOrderMethod.callMe => _callMe ? 'هنكلمك' : null,
      };

  Widget _methodIcon(IconData icon, {bool strong = false}) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: strong ? AppColors.actionGradient : null,
          color: strong ? null : AppColors.purpleSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(icon, color: strong ? Colors.white : AppColors.purple, size: 24),
      );

  Widget _addedChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.successSoft,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success),
          const SizedBox(width: 3),
          Text(text,
              style: const TextStyle(
                  color: AppColors.success, fontSize: AppTypography.caption, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _methodPicker() {
    final selected = _method;
    final info = selected == null ? null : _methodInfo[selected]!;
    return AppCard(
      key: const Key('quick-method-card'),
      elevated: true,
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const Key('quick-method-field'),
            onTap: _submitting ? null : () => setState(() => _methodsOpen = !_methodsOpen),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(children: [
                _methodIcon(info?.$1 ?? Icons.touch_app_rounded, strong: info != null),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected == null ? 'اختار طريقة الطلب' : _methodHeader[selected]!,
                        style: const TextStyle(
                          fontSize: AppTypography.body,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        info == null ? 'بصوتك، مكتوب، بالصور، أو نكلمك إحنا' : 'دوس هنا لو عايز تغيّر الطريقة',
                        style: AppTypography.secondary.copyWith(fontSize: AppTypography.label),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _methodsOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.purple, size: 28),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_methodsOpen
                ? const SizedBox(width: double.infinity)
                : Column(children: [
                    const Divider(height: 1),
                    for (final m in _methods) _methodOption(m),
                  ]),
          ),
        ],
      ),
    );
  }

  Widget _methodOption(QuickOrderMethod m) {
    final (icon, title, subtitle) = _methodInfo[m]!;
    final added = _added(m);
    final isSelected = _method == m;
    return Material(
      color: isSelected ? AppColors.purpleSoft.withValues(alpha: 0.55) : Colors.transparent,
      child: InkWell(
        key: Key('quick-method-${m.name}'),
        onTap: () => setState(() {
          _method = m;
          _methodsOpen = false;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(children: [
            _methodIcon(icon),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: AppTypography.bodySmall, color: AppColors.ink)),
                  Text(subtitle, style: AppTypography.secondary.copyWith(fontSize: AppTypography.label)),
                ],
              ),
            ),
            if (added != null)
              _addedChip(added)
            else
              Icon(
                isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: isSelected ? AppColors.purple : AppColors.line,
              ),
          ]),
        ),
      ),
    );
  }

  /// كل الطرق بتفضل محفوظة (لو بدّل بينهم مفيش حاجة بتضيع)، والظاهر المختارة بس.
  Widget _methodPanels() {
    Widget panel(QuickOrderMethod m, Widget child) => Visibility(
          visible: _method == m && !_methodsOpen,
          maintainState: true,
          child: Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: child),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        panel(QuickOrderMethod.voice, _voicePanel()),
        panel(QuickOrderMethod.write, _writePanel()),
        if (kQuickPhotoOrdersEnabled) ...[
          panel(QuickOrderMethod.camera, _photoPanel(ImageSource.camera)),
          panel(QuickOrderMethod.gallery, _photoPanel(ImageSource.gallery)),
        ],
        panel(QuickOrderMethod.callMe, _callMePanel()),
      ],
    );
  }

  /// «كلّمني»: مفيش حاجة يكتبها العميل؛ بس يتأكد إن رقمه صح.
  Widget _callMePanel() => AppCard(
        key: const Key('quick-call-me-section'),
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(gradient: AppColors.actionGradient, shape: BoxShape.circle),
                child: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Text(
                  'سيبها علينا، إحنا هنكلمك',
                  style: TextStyle(
                      fontSize: AppTypography.titleSmall, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'مش محتاج تكتب ولا تسجّل ولا تصوّر. حدد عنوانك ودوس «اطلب دلوقتي»، '
              'وأول مندوب يقبل طلبك هيتصل بيك، تقوله محتاج إيه، يشتريه ويوصّله لحد بابك.',
              style: AppTypography.secondary.copyWith(height: 1.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _phone,
              builder: (context, value, _) {
                final phone = value.text.trim();
                return Row(children: [
                  const Icon(Icons.call_outlined, size: 18, color: AppColors.purple),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      phone.isEmpty ? 'اكتب رقمك تحت عشان المندوب يكلمك' : 'هنكلمك على: $phone',
                      key: const Key('quick-call-me-phone'),
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
                    ),
                  ),
                  TextButton(
                    key: const Key('quick-call-me-edit-phone'),
                    onPressed: _submitting ? null : () => setState(() => _contactCollapsed = false),
                    child: Text(phone.isEmpty ? 'اكتب الرقم' : 'تغيير'),
                  ),
                ]);
              },
            ),
          ],
        ),
      );

  Widget _storeNameField() => TextField(
        controller: _stores.first.nameCtrl,
        enabled: !_submitting,
        maxLength: 60,
        decoration: const InputDecoration(
          labelText: 'من محل معيّن؟ (اختياري)',
          hintText: 'سيبه فاضي لو المندوب هيختار',
          prefixIcon: Icon(Icons.storefront_outlined),
          counterText: '',
        ),
      );

  Widget _voicePanel() {
    final hasVoice = _voicePath != null && !_recording;
    return AppCard(
      key: const Key('quick-voice-section'),
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Material(
              color: Colors.transparent,
              child: Ink(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _recording ? null : AppColors.actionGradient,
                  color: _recording ? AppColors.danger : null,
                  boxShadow: [
                    BoxShadow(
                      color: (_recording ? AppColors.danger : AppColors.orange).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: InkWell(
                  key: const Key('quick-voice-record'),
                  customBorder: const CircleBorder(),
                  onTap: _submitting ? null : _toggleVoice,
                  child: Icon(
                    _recording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _recording
                        ? 'بيسجّل… دوس إيقاف لما تخلص'
                        : hasVoice
                            ? 'تسجيلك جاهز'
                            : 'دوس واتكلم',
                    style: const TextStyle(
                        fontSize: AppTypography.titleSmall, fontWeight: FontWeight.w800, color: AppColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _recording
                        ? '${_clock(_voiceSeconds)} من ${_clock(_maxVoiceSeconds)}'
                        : 'قول الأصناف والكميات، لحد دقيقة كاملة.',
                    style: AppTypography.secondary,
                  ),
                  if (_recording) ...[
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        value: _voiceSeconds / _maxVoiceSeconds,
                        minHeight: 6,
                        color: AppColors.danger,
                        backgroundColor: AppColors.dangerSoft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ]),
          if (hasVoice) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(children: [
                IconButton.filled(
                  key: const Key('quick-voice-preview'),
                  tooltip: _playingVoice ? 'إيقاف' : 'اسمع التسجيل',
                  onPressed: _submitting ? null : _previewVoice,
                  icon: Icon(_playingVoice ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    _playingVoice ? 'بيشتغل…' : 'تسجيلك • ${_clock(_voiceLength)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft),
                  ),
                ),
                TextButton(
                  key: const Key('quick-voice-redo'),
                  onPressed: _submitting ? null : _toggleVoice,
                  child: const Text('سجّل تاني'),
                ),
                IconButton(
                  tooltip: 'حذف التسجيل',
                  onPressed: _submitting ? null : _deleteVoice,
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                ),
              ]),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _storeNameField(),
          const SizedBox(height: AppSpacing.xs),
          Text('التسجيل بيتمسح بعد ما تستلم طلبك برمز التسليم.',
              style: AppTypography.secondary.copyWith(fontSize: AppTypography.caption)),
        ],
      ),
    );
  }

  Widget _writePanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final store in _stores) _storeFields(store),
          if (_stores.length < 10)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('quick-add-store'),
                onPressed: _submitting ? null : () => setState(() => _stores.add(_QuickStoreDraft())),
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('أضف محل تاني'),
              ),
            ),
        ],
      );

  Widget _storeFields(_QuickStoreDraft store) {
    final index = _stores.indexOf(store);
    return AppCard(
      key: ObjectKey(store),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: store.nameCtrl,
                enabled: !_submitting,
                maxLength: 60,
                decoration: InputDecoration(
                  labelText: _stores.length == 1 ? 'اسم المحل (اختياري)' : 'المحل ${index + 1} (اختياري)',
                  hintText: 'سيبه فاضي لو المندوب هيختار',
                  prefixIcon: const Icon(Icons.storefront_outlined),
                  counterText: '',
                ),
              ),
            ),
            if (_stores.length > 1)
              IconButton(
                tooltip: 'احذف المحل ده',
                color: AppColors.danger,
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                          _stores.remove(store);
                          store.dispose();
                        }),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: ValueKey('quick-items-$index'),
            controller: store.itemsCtrl,
            enabled: !_submitting,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'الأصناف والكميات',
              hintText: 'مثال: ٢ كيلو رز، كيس سكر، علبة زبادي',
              alignLabelWithHint: true,
              counterText: '',
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() {
                store.showGuide = !store.showGuide;
                store.guideOpened = true;
              }),
              icon: Icon(store.showGuide ? Icons.expand_less_rounded : Icons.price_check_rounded),
              label: Text(store.showGuide ? 'اقفل دليل الأسعار' : 'أو اختار من دليل الأسعار'),
            ),
          ),
          // الدليل بيتحمّل أول مرة يتفتح بس (مفيش قراءة لو العميل ما احتاجوش).
          if (store.guideOpened)
          Visibility(
            visible: store.showGuide,
            maintainState: true,
            child: QuickPricePicker(
              showFreeText: false,
              showSearch: false,
              onChanged: (items) => setState(() => store.items = items),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoTile({required Widget child, VoidCallback? onTap, Key? key}) => Material(
        key: key,
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 84, height: 84, child: child),
        ),
      );

  /// «صوّر طلبك»: الكاميرا أو المعرض، لحد 3 صور مع معاينة وتكبير وحذف.
  Widget _photoPanel(ImageSource source) {
    final camera = source == ImageSource.camera;
    final full = _photos.length >= _maxPhotos;
    return AppCard(
      key: Key(camera ? 'quick-photo-section' : 'quick-gallery-section'),
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: AppColors.purpleSoft,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: InkWell(
              key: Key(camera ? 'quick-photo-camera' : 'quick-photo-gallery'),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: _submitting || _uploadingPhoto || full ? null : () => _addPhoto(source),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
                child: Row(children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(gradient: AppColors.actionGradient, shape: BoxShape.circle),
                    child: _uploadingPhoto
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : Icon(camera ? Icons.photo_camera_rounded : Icons.photo_library_rounded,
                            color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          full
                              ? 'وصلت لأقصى عدد صور'
                              : _uploadingPhoto
                                  ? 'بنرفع الصورة…'
                                  : camera
                                      ? 'افتح الكاميرا وصوّر الورقة'
                                      : 'اختار صورة من المعرض',
                          style: const TextStyle(
                              fontSize: AppTypography.body, fontWeight: FontWeight.w800, color: AppColors.purpleDarker),
                        ),
                        Text(
                          camera ? 'صوّر بوضوح وفي إضاءة كويسة' : 'صورة ورقة طلباتك أو لقطة شاشة',
                          style: AppTypography.secondary.copyWith(fontSize: AppTypography.label),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (i, url) in _photos.indexed)
                  Stack(clipBehavior: Clip.none, children: [
                    _photoTile(
                      key: ValueKey('quick-photo-${source.name}-$i'),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (dialog) => Dialog(
                          clipBehavior: Clip.antiAlias,
                          child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
                        ),
                      ),
                      child: Image.network(url, fit: BoxFit.cover, cacheWidth: 240,
                          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
                    ),
                    PositionedDirectional(
                      top: -6,
                      end: -6,
                      child: Material(
                        color: AppColors.danger,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _submitting ? null : () => setState(() => _photos.removeAt(i)),
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ]),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${_photos.length} من $_maxPhotos صور • بتتمسح بعد ما تستلم طلبك',
            style: AppTypography.secondary.copyWith(fontSize: AppTypography.caption),
          ),
          const SizedBox(height: AppSpacing.md),
          _storeNameField(),
        ],
      ),
    );
  }

  // ───────── ٢) العنوان ─────────

  Widget _addressChoice(_AddressMode mode, IconData icon, String title, String subtitle) {
    final selected = _addressMode == mode;
    return Expanded(
      child: Material(
        color: selected ? AppColors.purpleSoft : AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: selected ? AppColors.purple : Colors.transparent, width: 1.6),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('quick-address-${mode.name}'),
          onTap: _submitting
              ? null
              : () {
                  setState(() => _addressMode = mode);
                  // «عنواني» = نحدد الموقع على الخريطة على طول.
                  if (mode == _AddressMode.mine && _picked == null) _locate();
                },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, color: selected ? AppColors.purple : AppColors.muted),
                  const Spacer(),
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 20,
                    color: selected ? AppColors.purple : AppColors.line,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xs),
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: AppTypography.bodySmall,
                        color: selected ? AppColors.purpleDarker : AppColors.ink)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.secondary.copyWith(fontSize: AppTypography.caption)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _deliveryCard() {
    final picked = _picked;
    return AppCard(
      key: const Key('quick-delivery-card'),
      elevated: true,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('quick-area'),
            controller: _area,
            maxLength: 60,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'الحي',
              hintText: 'مثال: بيلا، حي المحطة',
              prefixIcon: const Icon(Icons.location_city_rounded),
              counterText: '',
              helperText: 'الحي بس بيظهر للمندوب قبل ما يقبل.',
              suffixIcon: Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.xxs),
                child: TextButton.icon(
                  key: const Key('quick-area-auto'),
                  onPressed: _locating || _submitting ? null : _locate,
                  icon: _locating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: const Text('حدد تلقائي'),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            _addressChoice(
              _AddressMode.mine,
              Icons.home_rounded,
              'على عنواني',
              picked != null ? 'اتحدد على الخريطة' : 'نحدد موقعك على الخريطة',
            ),
            const SizedBox(width: AppSpacing.sm),
            _addressChoice(_AddressMode.other, Icons.edit_location_alt_rounded, 'عنوان تاني', 'تكتبه بنفسك'),
          ]),
          const SizedBox(height: AppSpacing.md),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _addressMode == _AddressMode.other
                ? TextField(
                    key: const Key('quick-other-address'),
                    controller: _address,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'اكتب العنوان',
                      hintText: 'الحي، الشارع، علامة مميزة',
                      prefixIcon: Icon(Icons.edit_location_alt_outlined),
                      counterText: '',
                    ),
                  )
                : _myAddressRow(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'باقي التفاصيل (الدور، الشقة…) المندوب هياخدها منك لما يوافق ويكلمك.',
            style: AppTypography.secondary.copyWith(fontSize: AppTypography.caption),
          ),
        ],
      ),
    );
  }

  Widget _myAddressRow() {
    final picked = _picked;
    final text = picked?.address ?? (_savedAddress.isNotEmpty ? _savedAddress : null);
    return Container(
      key: const Key('quick-my-address'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: picked != null ? AppColors.successSoft : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(children: [
        Icon(picked != null ? Icons.where_to_vote_rounded : Icons.place_outlined,
            color: picked != null ? AppColors.success : AppColors.muted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                picked != null
                    ? 'موقعك اتحدد على الخريطة'
                    : text != null
                        ? 'عنوانك المحفوظ'
                        : 'لسه ما حددناش موقعك',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: AppTypography.label),
              ),
              if (text != null)
                Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.secondary),
            ],
          ),
        ),
        TextButton(
          key: const Key('quick-locate'),
          onPressed: _locating || _submitting ? null : _locate,
          child: Text(picked != null ? 'تحديث' : 'حدد موقعي'),
        ),
      ]),
    );
  }

  /// الاسم والموبايل: ملخص لو محفوظين، و«تعديل» يفتح الحقول.
  Widget _contactCard() {
    if (_contactCollapsed) {
      return AppCard(
        key: const Key('quick-contact-summary'),
        margin: EdgeInsets.zero,
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: AppColors.purpleSoft, shape: BoxShape.circle),
            child: const Icon(Icons.person_outline_rounded, color: AppColors.purple),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name.text.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: AppTypography.bodySmall, color: AppColors.ink)),
                Row(children: [
                  Text(_phone.text.trim(),
                      textDirection: TextDirection.ltr,
                      style: AppTypography.secondary.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: AppSpacing.sm),
                  const _PrivacyBadge(),
                ]),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _contactCollapsed = false),
            child: const Text('تعديل'),
          ),
        ]),
      );
    }
    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'اسمك',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'رقم الموبايل',
              hintText: '01xxxxxxxxx',
              prefixIcon: Icon(Icons.phone_iphone_rounded),
              suffixIcon: Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: _PrivacyBadge(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// عنوان خطوة مرقّم: «١ تحب تبعت طلبك إزاي؟».
class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.purple, shape: BoxShape.circle),
            child: Text(
              '٠١٢٣٤٥٦٧٨٩'[number],
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: AppTypography.label),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(title, style: AppTypography.sectionTitle.copyWith(fontSize: AppTypography.titleSmall)),
          ),
        ]),
      );
}

/// شرح مختصر للخدمة وخطواتها، من غير إطالة.
class _QuickIntro extends StatelessWidget {
  const _QuickIntro();

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, String label) => Expanded(
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppTypography.caption,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        );
    return Container(
      key: const Key('quick-intro'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: AppShadows.floating,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: AppColors.actionGradient,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.bolt_rounded, size: 32, color: Colors.white),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'وصّلي ع السريع',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppTypography.headline,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: AppSpacing.xxs),
                    Text(
                      'قول أو اكتب أو صوّر اللي محتاجه، ومندوب معتمد يشتريه ويوصّله لحد بابك.',
                      style: TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontSize: AppTypography.bodySmall,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              step(Icons.record_voice_over_rounded, 'ابعت طلبك'),
              step(Icons.phone_in_talk_rounded, 'المندوب يكلمك ويتفق معاك'),
              step(Icons.receipt_long_rounded, 'تشوف الحساب النهائي'),
              step(Icons.verified_rounded, 'تستلم برمز التسليم'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge();

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'رقمك وعنوانك بيظهروا للمندوب بعد ما يقبل الطلب بس',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
          decoration: BoxDecoration(
            color: AppColors.successSoft,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.success),
              SizedBox(width: 3),
              Text(
                'محمية',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: AppTypography.caption,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
}

/// توضيح الرسوم والاتفاق على السعر (نفس قواعد الخدمة الحالية).
class _FeesNote extends StatelessWidget {
  const _FeesNote();

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('quick-fees-note'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.orangeSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.25)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.orangeDeep, size: 20),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'أجرة التوصيل بالاتفاق مع المندوب قبل الشراء، وبتوافق على الفواتير والحساب قبل الاستلام.',
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: AppTypography.label,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

class _QuickStoreDraft {
  final nameCtrl = TextEditingController();
  final itemsCtrl = TextEditingController();
  List<QuickPriceSelection> items = const [];
  bool showGuide = false;
  bool guideOpened = false;

  String get name => nameCtrl.text.trim();
  String get unlisted => itemsCtrl.text.trim();
  bool get hasItems => items.isNotEmpty || unlisted.isNotEmpty;

  /// محل فاضي (طلب بالصوت/الصور من غير محل محدد).
  static const empty = {'name': '', 'items': ''};

  Map<String, dynamic> toWorkerMap() => {
    'name': name,
    'items': unlisted,
    if (items.isNotEmpty) 'pricedItems': [for (final item in items) item.toWorkerMap()],
  };

  void dispose() {
    nameCtrl.dispose();
    itemsCtrl.dispose();
  }
}
