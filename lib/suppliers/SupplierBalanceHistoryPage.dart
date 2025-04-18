import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SupplierBalanceHistoryPage extends StatelessWidget {
  final String supplierId;

  const SupplierBalanceHistoryPage({Key? key, required this.supplierId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تاريخ الرصيد'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('suppliers')
            .doc(supplierId)
            .collection('balanceHistory')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          final history = snapshot.data!.docs;

          return DataTable(
            columns: const [
              DataColumn(label: Text('الرصيد المدخل')),
              DataColumn(label: Text('الرصيد قبل')),
              DataColumn(label: Text('التاريخ')),
            ],
            rows: history.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final timestamp = (data['timestamp'] as Timestamp).toDate();
              final formattedDate = DateFormat('yyyy-MM-dd').format(timestamp);

              return DataRow(cells: [
                DataCell(Text(data['enteredBalance'].toString())),
                DataCell(Text(data['balanceBefore'].toString())),
                DataCell(Text(formattedDate)),
              ]);
            }).toList(),
          );
        },
      ),
    );
  }
}