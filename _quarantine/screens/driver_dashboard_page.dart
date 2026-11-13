import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/driver_service.dart';

class DriverDashboardPage extends StatefulWidget {
  final String driverId;
  final String driverName;
  final String driverPhone;

  const DriverDashboardPage({
    super.key,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
  });

  @override
  State<DriverDashboardPage> createState() => _DriverDashboardPageState();
}

class _DriverDashboardPageState extends State<DriverDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // إجراء اتصال هاتفي برقم العميل
  Future<void> _makeCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  // فتح المحادثة المباشرة مع العميل عبر واتساب
  Future<void> _openWhatsApp(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/20$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFF5E00),
        elevation: 0,
        title: Text(
          'لوحة توصيل وصّلي 🛵',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 4,
          labelStyle: GoogleFonts.cairo(
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'الطلبات المتاحة 📦'),
            Tab(text: 'قيد التوصيل 🚀'),
          ],
        ),
      ),
      body: Column(
        children: [
          // 🌟 شريط التقييم التراكمي الخاص بالمندوب
          _buildDriverHeaderRating(widget.driverId),

          // قائمة الطلبات التفاعلية حسب التبويب
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAvailableOrdersTab(),
                _buildActiveOrdersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // === 0. ودجت عرض متوسط تقييم المندوب ===
  Widget _buildDriverHeaderRating(String driverId) {
    return StreamBuilder<DocumentSnapshot>>(
      stream: FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? {};
        final double rating = (data['rating'] as num?)?.toDouble() ?? 5.0;
        final int count = (data['ratingCount'] as num?)?.toInt() ?? 0;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFDE68A)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD97706).withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      color: Color(0xFFFFB800), size: 26),
                  const SizedBox(width: 6),
                  Text(
                    rating.toStringAsFixed(1),
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFD97706),
                    ),
                  ),
                  Text(
                    ' ($count تقييم)',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              Text(
                'مستوى أدائك 🌟',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFB45309),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // === 1. تبويب الطلبات المتاحة للقبول ===
  Widget _buildAvailableOrdersTab() {
    return StreamBuilder<QuerySnapshot>>(
      stream: DriverService.getAvailableOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF5E00)),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 70, color: Colors.grey),
                const SizedBox(height: 12),
                Text(
                  'مفيش طلبات جديدة حالياً',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final order = docs[i].data();
            final orderId = docs[i].id;
            return _buildOrderCard(
              orderId: orderId,
              order: order,
              isAvailableTab: true,
            );
          },
        );
      },
    );
  }

  // === 2. تبويب الطلبات المستلمة والتي يقوم المندوب بتوصيلها ===
  Widget _buildActiveOrdersTab() {
    return StreamBuilder<QuerySnapshot>>(
      stream: DriverService.getMyActiveOrders(widget.driverId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF5E00)),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Text(
              'معندكش طلبات قيد التوصيل دلوقتي',
              style: GoogleFonts.cairo(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final order = docs[i].data();
            final orderId = docs[i].id;
            return _buildOrderCard(
              orderId: orderId,
              order: order,
              isAvailableTab: false,
            );
          },
        );
      },
    );
  }

  // === تصميم كارت الطلب المودرن للمندوب ===
  Widget _buildOrderCard({
    required String orderId,
    required Map<String, dynamic> order,
    required bool isAvailableTab,
  }) {
    final customerName = order['customerName'] ?? 'عميل وصّلي';
    final customerPhone = order['customerPhone'] ?? '';
    final total = order['total'] ?? 0;
    final items = (order['items'] as List?) ?? [];
    final notes = order['notes'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_pin_circle_rounded,
                      color: Color(0xFFFF5E00), size: 24),
                  const SizedBox(width: 8),
                  Text(
                    customerName,
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3EB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$total ج.م',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFFF5E00),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20),

          // قائمة الأصناف
          Text(
            'الأصناف المطلوب تحميلها (${items.length}):',
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          ...items.map((it) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.circle,
                        size: 6, color: Color(0xFFFF5E00)),
                    const SizedBox(width: 6),
                    Text(
                      '${it['name']} × ${it['qty']}',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              )),

          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'ملاحظات العميل: $notes',
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // أزرار التحكم والتفاعل للمندوب
          if (isAvailableTab)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await DriverService.acceptOrder(
                    orderId: orderId,
                    driverId: widget.driverId,
                    driverName: widget.driverName,
                    driverPhone: widget.driverPhone,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم استلام الطلب بنجاح! توجه للتحميل 🚀'),
                      ),
                    );
                    _tabController
                        .animateTo(1); // الانتقال لتبويب قيد التوصيل
                  }
                },
                icon:
                    const Icon(Icons.two_wheeler_rounded, color: Colors.white),
                label: Text(
                  'قبول واستلام الطلب 🚀',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5E00),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            )
          else ...[
            Row(
              children: [
                if (customerPhone.isNotEmpty) ...[
                  IconButton(
                    onPressed: () => _makeCall(customerPhone),
                    icon: const Icon(Icons.phone_active_rounded,
                        color: Colors.green),
                    tooltip: 'اتصال',
                  ),
                  IconButton(
                    onPressed: () => _openWhatsApp(customerPhone),
                    icon: const Icon(Icons.chat_bubble_rounded,
                        color: Color(0xFF25D366)),
                    tooltip: 'واتساب',
                  ),
                ],
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () async {
                    await DriverService.completeOrder(orderId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم تأكيد تسليم الطلب للعميل ✅'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check_circle_rounded,
                      color: Colors.white),
                  label: Text(
                    'تأكيد التسليم ✅',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
