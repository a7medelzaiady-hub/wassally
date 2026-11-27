import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/image_service.dart';
import '../services/quick_order_api.dart';
import '../services/user_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_snack.dart';
import 'quick_order_create_page.dart';
import 'quick_order_customer_detail_page.dart';

/// «مشوارك علينا» = نفس الطلب السريع/الـWorker، لكن بأجرة متفق عليها مسبقًا
/// وعنواني استلام وتسليم خاصين. لا توجد قراءات Firestore إضافية للدليل.
class ErrandCreatePage extends StatefulWidget {
  const ErrandCreatePage({super.key, this.prefillFromAccount = true});

  /// تعطيل ملء بيانات Firebase في اختبارات الواجهة فقط.
  final bool prefillFromAccount;

  @override
  State<ErrandCreatePage> createState() => _ErrandCreatePageState();
}

class _ErrandType {
  final String id;
  final String label;
  final IconData icon;
  const _ErrandType(this.id, this.label, this.icon);
}

class _ErrandCreatePageState extends State<ErrandCreatePage> {
  static const _categories = [
    _ErrandType('parcel', 'توصيل غرض', Icons.inventory_2_outlined),
    _ErrandType('documents', 'استلام أوراق', Icons.description_outlined),
    _ErrandType('ready_order', 'استلام طلب جاهز', Icons.storefront_outlined),
    _ErrandType('other', 'مشوار تاني', Icons.delivery_dining_outlined),
  ];

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _area = TextEditingController();
  final _pickup = TextEditingController();
  final _destination = TextEditingController();
  final _mission = TextEditingController();
  String _type = 'parcel';
  final List<String> _photos = [];
  bool _uploading = false;
  bool _submitting = false;
  AudioRecorder? _recorder;
  Timer? _voiceTimer;
  String? _voicePath;
  String? _uploadedVoiceUrl;
  int _seconds = 0;
  bool _recording = false;
  String? _pendingOrderId;

  @override
  void initState() {
    super.initState();
    _loadLastArea();
    if (widget.prefillFromAccount) {
      _name.text = FirebaseAuth.instance.currentUser?.displayName ?? '';
      _prefill();
    }
  }

  Future<void> _loadLastArea() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      if (_area.text.isEmpty) _area.text = prefs.getString('quick_last_area') ?? '';
    } catch (_) {}
  }

  Future<void> _prefill() async {
    try {
      final p = await UserService.load();
      if (!mounted) return;
      if (p.name.trim().isNotEmpty) _name.text = p.name;
      if (_phone.text.isEmpty) _phone.text = p.phone;
      if (_destination.text.isEmpty) _destination.text = p.address;
      setState(() {});
    } catch (_) {
      // يمكن إدخال البيانات يدويًا بدون تعطيل الخدمة.
    }
  }

  @override
  void dispose() {
    _voiceTimer?.cancel();
    _recorder?.dispose();
    if (_voicePath != null) File(_voicePath!).delete().catchError((_) => File(_voicePath!));
    for (final controller in [_name, _phone, _area, _pickup, _destination, _mission]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _say(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(appSnack(message));
  }

  Future<void> _addPhoto(ImageSource source) async {
    if (_uploading || _submitting || _photos.length >= 3) return;
    setState(() => _uploading = true);
    try {
      final url = await ImageService.pickAndUploadQuickRequest(source: source);
      if (url != null && mounted) setState(() => _photos.add(url));
    } catch (_) {
      _say('تعذر رفع الصورة. جرّب تاني.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _toggleVoice() async {
    if (_submitting) return;
    if (_recording) {
      await _stopVoice();
      return;
    }
    try {
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission()) {
        _say('اسمح للتطبيق باستخدام الميكروفون.');
        return;
      }
      final directory = await getTemporaryDirectory();
      final path = directory.path + '/errand-' +
          DateTime.now().microsecondsSinceEpoch.toString() + '.m4a';
      await recorder.start(
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
        _seconds = 0;
      });
      _voiceTimer?.cancel();
      _voiceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_recording) {
          timer.cancel();
          return;
        }
        if (_seconds >= 59) {
          timer.cancel();
          _stopVoice();
        } else {
          setState(() => _seconds++);
        }
      });
    } catch (_) {
      _say('تعذر بدء التسجيل.');
    }
  }

  Future<void> _stopVoice() async {
    _voiceTimer?.cancel();
    try {
      final path = await _recorder?.stop();
      if (!mounted) return;
      if (path == null || !await File(path).exists()) {
        throw StateError('التسجيل لم يُحفظ');
      }
      final old = _voicePath;
      setState(() {
        _voicePath = path;
        _uploadedVoiceUrl = null;
        _recording = false;
        _seconds = 60 > _seconds ? _seconds + 1 : 60;
      });
      if (old != null && old != path) {
        await File(old).delete().catchError((_) => File(old));
      }
    } catch (_) {
      if (mounted) setState(() => _recording = false);
      _say('تعذر حفظ التسجيل.');
    }
  }

  Future<void> _deleteVoice() async {
    if (_recording) return;
    final path = _voicePath;
    setState(() {
      _voicePath = null;
      _uploadedVoiceUrl = null;
      _seconds = 0;
    });
    if (path != null) await File(path).delete().catchError((_) => File(path));
  }

  Future<void> _submit() async {
    if (_submitting || _uploading || _recording) return;
    final name = _name.text.trim();
    final phone = _phone.text.replaceAll(RegExp(r'[\\s-]'), '');
    final area = _area.text.trim();
    final pickup = _pickup.text.trim();
    final destination = _destination.text.trim();
    final mission = _mission.text.trim();
    if (name.isEmpty || name.length > 80 ||
        !RegExp(r'^01[0125][0-9]{8}$').hasMatch(phone)) {
      _say('اكتب اسمك ورقم موبايل مصري صحيح.');
      return;
    }
    if (area.isEmpty || area.length > 60) {
      _say('اكتب الحي أو المنطقة.');
      return;
    }
    if (pickup.length < 5 || pickup.length > 300 ||
        destination.length < 5 || destination.length > 300) {
      _say('اكتب عنوان الاستلام والتسليم بوضوح.');
      return;
    }
    if (mission.length < 10 || mission.length > 500) {
      _say('اكتب تفاصيل المشوار من 10 إلى 500 حرف.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) throw StateError('سجّل دخولك أولًا.');
      final id = _pendingOrderId ??= uid + '_' +
          DateTime.now().microsecondsSinceEpoch.toRadixString(16).padLeft(16, '0');
      if (_voicePath != null) {
        _uploadedVoiceUrl ??=
            await ImageService.uploadQuickVoice(await File(_voicePath!).readAsBytes());
      }
      await QuickOrderApi.create({
        'orderId': id,
        'kind': 'errand',
        'errandType': _type,
        'customerName': name,
        'area': area,
        'notes': '',
        'stores': [{'name': '', 'items': mission}],
        if (_photos.isNotEmpty) 'customerImages': List<String>.of(_photos),
        if (_uploadedVoiceUrl != null) 'customerVoiceUrl': _uploadedVoiceUrl,
        'contact': {
          'userName': name,
          'phone': phone,
          'pickupAddress': pickup,
          'address': destination,
        },
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('quick_last_area', area);
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => QuickOrderCustomerDetailPage(orderId: id),
      ));
    } catch (e) {
      _say(e is StateError ? e.message : 'تعذر إرسال المشوار. حاول تاني.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _field(TextEditingController controller, String label,
      {Key? key, String? hint, int lines = 1, TextInputType? keyboardType}) {
    return TextField(
      key: key,
      controller: controller,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 1,
      keyboardType: keyboardType,
      textInputAction: lines == 1 ? TextInputAction.next : TextInputAction.newline,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _box(List<Widget> children) => Container(
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('مشوارك علينا')),
      body: ListView(
        key: const Key('errand-create-list'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          const Text('عندك مشوار ومش فاضي؟ ابعته لوصّلي والمندوب يخلّصهولك!',
              style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.purple,
              )),
          const SizedBox(height: 12),
          _box([
            const Text('نوع المشوار', style: AppTypography.sectionTitle),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 6,
              children: [
                for (final type in _categories)
                  ChoiceChip(
                    key: ValueKey('errand-type-' + type.id),
                    avatar: Icon(type.icon, size: 18, color: AppColors.purple),
                    label: Text(type.label),
                    selected: _type == type.id,
                    onSelected: (_) => setState(() => _type = type.id),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              key: const Key('errand-to-shopping'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const QuickOrderCreatePage()),
              ),
              icon: const Icon(Icons.shopping_basket_outlined),
              label: const Text('عايز تشتري حاجات؟ افتح «وصّلي ع السريع»'),
            ),
          ]),
          _box([
            const Text('استلام وتسليم', style: AppTypography.sectionTitle),
            const SizedBox(height: 10),
            _field(_area, 'الحي أو المنطقة', key: const Key('errand-area')),
            const SizedBox(height: 10),
            _field(_pickup, 'استلم منين؟', key: const Key('errand-pickup'),
                hint: 'العنوان واسم المكان أو علامة مميزة', lines: 2),
            const SizedBox(height: 10),
            _field(_destination, 'سلّم فين؟', key: const Key('errand-destination'),
                hint: 'عنوان التسليم بالتفصيل', lines: 2),
          ]),
          _box([
            const Text('المندوب هيعمل إيه؟', style: AppTypography.sectionTitle),
            const SizedBox(height: 8),
            _field(_mission, 'تفاصيل المشوار', key: const Key('errand-mission'),
                hint: 'مثال: استلم كيس طلبات جاهز من المحل ووصّله للعنوان', lines: 3),
            const SizedBox(height: 6),
            const Text('لخصوصيتك، اكتب العناوين والأرقام في خاناتها فقط.',
                style: AppTypography.secondary),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                key: const Key('errand-camera'),
                onPressed: _uploading ? null : () => _addPhoto(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('صوّر'),
              ),
              OutlinedButton.icon(
                key: const Key('errand-gallery'),
                onPressed: _uploading ? null : () => _addPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('صورة'),
              ),
              OutlinedButton.icon(
                key: const Key('errand-voice'),
                onPressed: _toggleVoice,
                icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none),
                label: Text(_recording ? 'إيقاف التسجيل' :
                    _voicePath != null ? 'تسجيل محفوظ' : 'سجّل صوت (دقيقة)'),
              ),
            ]),
            if (_recording) Text('التسجيل: ' + _seconds.toString() + ' / 60 ثانية'),
            if (_voicePath != null)
              TextButton.icon(
                key: const Key('errand-voice-delete'),
                onPressed: _deleteVoice,
                icon: const Icon(Icons.delete_outline),
                label: const Text('احذف التسجيل أو سجّل من جديد'),
              ),
            if (_uploading) const LinearProgressIndicator(),
            if (_photos.isNotEmpty) SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(_photos[i], width: 68, height: 68, fit: BoxFit.cover),
                  ),
                  PositionedDirectional(
                    top: 0, end: 0,
                    child: IconButton.filledTonal(
                      tooltip: 'احذف الصورة',
                      iconSize: 18,
                      onPressed: () => setState(() => _photos.removeAt(i)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
          _box([
            const Text('بيانات التواصل', style: AppTypography.sectionTitle),
            const SizedBox(height: 10),
            _field(_name, 'اسمك', key: const Key('errand-name')),
            const SizedBox(height: 10),
            _field(_phone, 'رقم موبايلك', key: const Key('errand-phone'),
                keyboardType: TextInputType.phone),
          ]),
          _box([
            const Text('الأجرة تتحدد بعد ما المندوب يقبل المشوار ويتفق معاك.',
                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.purple)),
            const SizedBox(height: 4),
            const Text('المندوب يعرض السعر، وإنت توافق عليه قبل ما يبدأ. الدفع كاش عند التسليم برمز وصّلي.',
                style: AppTypography.secondary),
            const Text('لا ترسل مقتنيات ثمينة أو ممنوعة أو معاملات تتطلب تفويضًا رسميًا.',
                style: AppTypography.secondary),
          ]),
        ],
      ),
      bottomNavigationBar: keyboardOpen ? null : SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: FilledButton.icon(
            key: const Key('errand-submit'),
            onPressed: _submitting || _uploading || _recording ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: AppColors.purple,
            ),
            icon: _submitting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.delivery_dining_outlined),
            label: Text(_submitting ? 'جارٍ إرسال المشوار...' : 'اطلب مندوب'),
          ),
        ),
      ),
    );
  }
}
