import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/image_service.dart';

/// Edit the voice attached to an OPEN quick order.
/// Returns a new Cloudinary URL, "" to remove it, or null when cancelled.
/// Media changes are persisted by the caller through the authenticated Worker.
class QuickVoiceEditSheet extends StatefulWidget {
  const QuickVoiceEditSheet({super.key, required this.currentUrl});

  final String currentUrl;

  @override
  State<QuickVoiceEditSheet> createState() => _QuickVoiceEditSheetState();
}

class _QuickVoiceEditSheetState extends State<QuickVoiceEditSheet> {
  static const maxSeconds = 60;

  final _recorder = AudioRecorder();
  final _player = audio.AudioPlayer();
  Timer? _timer;
  String? _path;
  bool _recording = false;
  bool _playing = false;
  bool _busy = false;
  bool _changed = false;
  bool _removed = false;
  int _seconds = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _player.dispose();
    final path = _path;
    if (path != null) File(path).delete().catchError((_) => File(path));
    super.dispose();
  }

  String get _time => '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';

  void _say(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _toggleRecord() async {
    if (_busy) return;
    if (_recording) {
      try {
        final newPath = await _recorder.stop();
        _timer?.cancel();
        if (newPath == null || !await File(newPath).exists()) {
          throw StateError('ملف التسجيل غير موجود');
        }
        final previous = _path;
        if (mounted) setState(() {
          _recording = false;
          _path = newPath;
          _changed = true;
          _removed = false;
        });
        if (previous != null && previous != newPath) {
          await File(previous).delete().catchError((_) => File(previous));
        }
      } catch (_) {
        if (mounted) setState(() => _recording = false);
        _say('تعذر حفظ التسجيل، حاول مرة تانية.');
      }
      return;
    }

    try {
      if (!await _recorder.hasPermission()) {
        _say('اسمح باستخدام الميكروفون لتسجيل طلبك.');
        return;
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/quick-edit-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _player.stop();
      await _recorder.start(const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 32000,
        sampleRate: 22050,
        numChannels: 1,
      ), path: path);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _playing = false;
        _seconds = 0;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_recording) { timer.cancel(); return; }
        if (_seconds + 1 >= maxSeconds) {
          setState(() => _seconds = maxSeconds);
          timer.cancel();
          _toggleRecord();
          return;
        }
        setState(() => _seconds++);
      });
    } catch (_) {
      _say('تعذر بدء التسجيل الصوتي.');
    }
  }

  Future<void> _preview() async {
    if (_busy || _recording || _removed) return;
    try {
      if (_playing) {
        await _player.stop();
        if (mounted) setState(() => _playing = false);
      } else {
        await _player.stop();
        if (_path != null) {
          await _player.setSource(audio.DeviceFileSource(_path!));
        } else if (widget.currentUrl.isNotEmpty) {
          await _player.setSource(audio.UrlSource(widget.currentUrl));
        } else {
          return;
        }
        await _player.resume();
        if (mounted) setState(() => _playing = true);
      }
    } catch (_) { _say('تعذر تشغيل التسجيل.'); }
  }

  Future<void> _remove() async {
    if (_busy || _recording) return;
    await _player.stop();
    final previous = _path;
    if (mounted) setState(() {
      _path = null;
      _playing = false;
      _changed = true;
      _removed = true;
    });
    if (previous != null) await File(previous).delete().catchError((_) => File(previous));
  }

  Future<void> _save() async {
    if (_busy || _recording || !_changed) return;
    setState(() => _busy = true);
    try {
      if (_removed) {
        if (mounted) Navigator.of(context).pop('');
        return;
      }
      final path = _path;
      if (path == null) throw StateError('سجّل رسالة جديدة الأول.');
      final url = await ImageService.uploadQuickVoice(await File(path).readAsBytes());
      if (mounted) Navigator.of(context).pop(url);
    } catch (error) {
      _say(error is StateError ? error.message : 'تعذر رفع التسجيل. جرّب مرة تانية.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVoice = !_removed && (_path != null || widget.currentUrl.isNotEmpty);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20, 18, 20, 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('تعديل تسجيل طلبك', style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800,
          )),
          const SizedBox(height: 6),
          const Text('سجّل رسالة جديدة لحد دقيقة كاملة، أو اسمع التسجيل الحالي، أو احذفه. التعديل متاح قبل ما المندوب يقبل الطلب.'),
          const SizedBox(height: 12),
          Text('مدة التسجيل: $_time / 01:00',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('quick-edit-voice-record'),
            onPressed: _busy ? null : _toggleRecord,
            icon: Icon(_recording ? Icons.stop_circle : Icons.mic),
            label: Text(_recording ? 'إيقاف التسجيل' : 'تسجيل جديد / تعديل'),
          ),
          if (hasVoice && !_recording) ...[
            OutlinedButton.icon(
              key: const Key('quick-edit-voice-preview'),
              onPressed: _busy ? null : _preview,
              icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
              label: Text(_playing ? 'إيقاف الصوت' : 'اسمع التسجيل'),
            ),
            TextButton.icon(
              key: const Key('quick-edit-voice-delete'),
              onPressed: _busy ? null : _remove,
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف التسجيل'),
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            )),
            Expanded(child: FilledButton(
              key: const Key('quick-edit-voice-save'),
              onPressed: _busy || _recording || !_changed ? null : _save,
              child: Text(_busy ? 'جارٍ الرفع...' : 'حفظ التعديل'),
            )),
          ]),
        ]),
      ),
    );
  }
}
