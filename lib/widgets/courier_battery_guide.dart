import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Policy-only local flag. A guide is shown once per courier account, not once per build.
class CourierBatteryGuidePolicy {
  static String key(String uid) => 'courier_battery_guide_seen_$uid';

  static Future<bool> shouldShowOnce(String uid) async {
    if (uid.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final k = key(uid);
    if (prefs.getBool(k) == true) return false;
    await prefs.setBool(k, true);
    return true;
  }
}

class CourierBatteryGuide {
  const CourierBatteryGuide._();

  static const _settings = MethodChannel('com.wassally.app/device_settings');

  static Future<void> openSettings() async {
    try {
      // Direct battery-optimization exemption is restricted by Google Play.
      // Open app-specific settings instead so the courier chooses voluntarily.
      await _settings.invokeMethod<void>('batterySettings');
    } catch (_) {
      // Nothing to do if the OEM does not support this settings intent.
    }
  }

  static Future<void> show(BuildContext context, {
    Future<void> Function()? openBatterySettings,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('خلّي طلبات وصّلي توصلك بسرعة', style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800,
                )),
                const SizedBox(height: 6),
                const Text(
                  'لو بتلاحظ إن الطلبات بتتأخر والموبايل مقفول، جرّب الخطوات دي. '
                  'كل موبايل ممكن يسمي الاختيارات بشكل مختلف.',
                  style: TextStyle(height: 1.45),
                ),
                const SizedBox(height: 12),
                const _BatteryStep('شاومي / بوكو', 'التطبيقات ← وصّلي ← البطارية ← بدون قيود. وفعّل التشغيل التلقائي.'),
                const _BatteryStep('أوبو', 'إدارة التطبيقات ← وصّلي ← استهلاك البطارية، واسمح بالنشاط في الخلفية والتشغيل التلقائي.'),
                const _BatteryStep('ريلمي', 'إدارة التطبيقات ← وصّلي ← استخدام البطارية، واسمح بالتشغيل التلقائي وفي الخلفية.'),
                const _BatteryStep('هواوي', 'التطبيقات ← بدء تشغيل التطبيقات ← وصّلي، واقفل الإدارة التلقائية واسمح بالتشغيل في الخلفية.'),
                const _BatteryStep('سامسونج', 'التطبيقات ← وصّلي ← البطارية ← غير مقيّد. وشيله من التطبيقات في وضع السكون.'),
                const SizedBox(height: 8),
                const Text(
                  'الإعدادات دي بتساعد، بس وصول الإشعار برضه بيعتمد على النت وإعدادات النظام.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          await (openBatterySettings ?? openSettings)();
                        },
                        icon: const Icon(Icons.battery_charging_full_outlined, size: 18),
                        label: const Text('افتح إعدادات التطبيق'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('تمام'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BatteryStep extends StatelessWidget {
  const _BatteryStep(this.brand, this.instructions);

  final String brand;
  final String instructions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text.rich(TextSpan(children: [
      TextSpan(text: '$brand: ', style: const TextStyle(fontWeight: FontWeight.w800)),
      TextSpan(text: instructions),
    ]), style: const TextStyle(fontSize: 13, height: 1.45)),
  );
}

/// Only mounted on the verified courier dashboard, never on customer screens.
class CourierBatteryGuideEntry extends StatefulWidget {
  const CourierBatteryGuideEntry({super.key, required this.uid});
  final String uid;

  @override
  State<CourierBatteryGuideEntry> createState() => _CourierBatteryGuideEntryState();
}

class _CourierBatteryGuideEntryState extends State<CourierBatteryGuideEntry> {
  bool _firstVisit = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.uid.isEmpty) return;
      // Never open a modal over a courier's available order buttons.
      // Highlight the existing compact guidance button on the first visit.
      final firstVisit = await CourierBatteryGuidePolicy.shouldShowOnce(widget.uid);
      if (mounted && firstVisit) setState(() => _firstVisit = true);
    });
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: TextButton.icon(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: _firstVisit ? const Color(0xFF985300) : null,
      ),
      onPressed: () async {
        if (_firstVisit) setState(() => _firstVisit = false);
        await CourierBatteryGuide.show(context);
      },
      icon: const Icon(Icons.battery_alert_outlined, size: 17),
      label: Text(
        _firstVisit ? 'تنبيه: إعدادات استقبال الطلبات' : 'إعدادات استقبال الطلبات',
        style: const TextStyle(fontSize: 12),
      ),
    ),
  );
}
