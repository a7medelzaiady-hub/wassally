import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/driver_service.dart';

class RateDriverDialog extends StatefulWidget {
  final String orderId;
  final String driverId;
  final String driverName;

  const RateDriverDialog({
    super.key,
    required this.orderId,
    required this.driverId,
    required this.driverName,
  });

  @override
  State<RateDriverDialog> createState() => _RateDriverDialogState();
}

class _RateDriverDialogState extends State<RateDriverDialog> {
  double _rating = 5.0;
  final TextEditingController _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        'تقييم مندوب التوصيل 🛵',
        textAlign: TextAlign.center,
        style: GoogleFonts.cairo(fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'كيف كانت تجربتك مع المندوب ${widget.driverName}؟',
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),

          // اختيار النجوم للتقييم
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starValue = index + 1.0;
              return IconButton(
                onPressed: () => setState(() => _rating = starValue),
                icon: Icon(
                  starValue <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: const Color(0xFFFFB800),
                  size: 36,
                ),
              );
            }),
          ),
          const SizedBox(height: 12),

          // مربع ملاحظة اختياري
          TextField(
            controller: _commentCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'اكتب كلمة للمندوب (اختياري)...',
              hintStyle: GoogleFonts.cairo(fontSize: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('تخطي', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _submitting
              ? null
              : () async {
                  setState(() => _submitting = true);
                  try {
                    await DriverService.rateDriver(
                      orderId: widget.orderId,
                      driverId: widget.driverId,
                      rating: _rating,
                      comment: _commentCtrl.text.trim(),
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('شكراً لتقييمك! ❤️')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() => _submitting = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('حصل خطأ أثناء التقييم: $e')),
                      );
                    }
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF5E00),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text('إرسال التقييم 🌟', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ],
    );
  }
}
