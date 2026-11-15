import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CourierOrdersScreen extends StatelessWidget {
  const CourierOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلبات التوصيل المتاحة')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('status', whereIn: ['processing', 'out_for_delivery'])
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;

          if (docs.isEmpty) return const Center(child: Text('لا توجد طلبات تحتاج توصيل حالياً.'));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final orderId = docs[index].id;
              final status = data['status'];

              return Card(
                margin: const EdgeInsets.all(10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('العنوان: ${data['address']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('رقم العميل: ${data['phone']}'),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (status == 'processing')
                            ElevatedButton(
                              onPressed: () {
                                FirebaseFirestore.instance.collection('orders').doc(orderId).update({
                                  'status': 'out_for_delivery',
                                });
                              },
                              child: const Text('استلام الطلب للبدء'),
                            ),
                          if (status == 'out_for_delivery')
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                              onPressed: () {
                                FirebaseFirestore.instance.collection('orders').doc(orderId).update({
                                  'status': 'completed',
                                });
                              },
                              child: const Text('تم التسليم للعميل', style: TextStyle(color: Colors.white)),
                            ),
                        ],
                      ),
                    ],
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