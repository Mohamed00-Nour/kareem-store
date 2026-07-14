import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;

class SupplierBalanceHistoryPage extends StatelessWidget {
  final String supplierId;

  const SupplierBalanceHistoryPage({Key? key, required this.supplierId}) : super(key: key);

  String _descriptionForEntry(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final notes = (data['notes'] ?? data['description'] ?? '').toString().trim();

    if (type == 'opening') {
      return 'رصيد افتتاحي';
    }

    String description = '';
    if (type == 'voucher') {
      description = 'سند';
    } else {
      description = 'سداد نقدي';
    }

    if (notes.isNotEmpty) {
      description += ' ($notes)';
    }
    return description;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تاريخ الرصيد'),
        backgroundColor: Colors.black.withOpacity(0.7),
        foregroundColor: Colors.white,
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
            return const Center(child: CircularProgressIndicator());
          }

          final history = snapshot.data!.docs;

          if (history.isEmpty) {
            return const Center(
              child: Text(
                'لا يوجد سجلات لتاريخ الرصيد',
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          return Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('البيان')),
                    DataColumn(label: Text('الرصيد المدخل')),
                    DataColumn(label: Text('الرصيد قبل')),
                    DataColumn(label: Text('التاريخ')),
                  ],
                  rows: history.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final ts = data['timestamp'];
                    final DateTime timestamp = ts is Timestamp
                        ? ts.toDate()
                        : (ts is DateTime ? ts : DateTime.now());
                    final formattedDate = DateFormat('yyyy-MM-dd').format(timestamp);
                    final description = _descriptionForEntry(data);

                    return DataRow(cells: [
                      DataCell(Text(description)),
                      DataCell(Text((data['enteredBalance'] as num?)?.toStringAsFixed(2) ?? '0.00')),
                      DataCell(Text((data['balanceBefore'] as num?)?.toStringAsFixed(2) ?? '0.00')),
                      DataCell(Text(formattedDate)),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}