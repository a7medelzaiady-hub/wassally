import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminOrdersScreen extends StatelessWidget {
  const AdminOrdersScreen({super.key});

  void _updateStatus(String orderId, String newStatus) {
    FirebaseFirestore.instance.collection('orders').doc(orderId).update({
      'status': newStatus,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة التحكم - إدارة الطلبات')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;

          if (docs.isEmpty) return const Center(child: Text('لا توجد طلبات حصرية.'));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final orderId = docs[index].id;
              final status = data['status'] ?? 'new';

              return Card(
                margin: const EdgeInsets.all(10),
                child: ListTile(
                  title: Text('طلب من: ${data['userName'] ?? 'عميل'} (${data['phone']})'),
                  subtitle: Text('العنوان: ${data['address']}\nالإجمالي: ${data['total'] ?? data['subtotal']} ج.م'),
                  trailing: DropdownButton<String>(
                    value: status,
                    items: const [
                      DropdownMenuItem(value: 'new', child: Text('جديد')),
                      DropdownMenuItem(value: 'processing', child: Text('جاري التحضير')),
                      DropdownMenuItem(value: 'out_for_delivery', child: Text('خرج للتوصيل')),
                      DropdownMenuItem(value: 'completed', child: Text('تم التسليم')),
                      DropdownMenuItem(value: 'cancelled', child: Text('ملغي')),
                    ],
                    onChanged: (val) {
                      if (val != null) _updateStatus(orderId, val);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}