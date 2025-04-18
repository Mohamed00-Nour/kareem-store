import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

class ClientInvoicesPage extends StatefulWidget {
  final String clientId;

  const ClientInvoicesPage({Key? key, required this.clientId})
      : super(key: key);

  @override
  _ClientInvoicesPageState createState() => _ClientInvoicesPageState();
}

class _ClientInvoicesPageState extends State<ClientInvoicesPage> {
  final TextEditingController _balanceController = TextEditingController();
  double _enteredBalance = 0.0;

  void _saveBalance() async {
    final clientDoc =
        FirebaseFirestore.instance.collection('clients').doc(widget.clientId);
    final clientSnapshot = await clientDoc.get();
    final currentBalance = clientSnapshot['balance'] ?? 0.0;
    final newBalance = currentBalance - _enteredBalance;

    // Save the balance history
    await clientDoc.collection('balanceHistory').add({
      'enteredBalance': _enteredBalance,
      'balanceBefore': currentBalance,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Update the client's balance
    await clientDoc.update({'balance': newBalance});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم الحفظ بنجاح')),
    );

    _balanceController.clear();
    setState(() {
      _enteredBalance = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فواتير العميل'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              children: [
                TextField(
                  controller: _balanceController,
                  keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.black.withOpacity(0.7)),
                  ),
                  filled: true,
                  fillColor: Colors.grey.withOpacity(0.1),
                  labelText: 'أدخل الرصيد',
                  labelStyle: TextStyle(
                    color: Colors.black.withOpacity(0.7),
                    fontSize: 16,
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.black.withOpacity(0.7),
                    ),
                  ),
                  prefixIcon: const Icon(Icons.attach_money_rounded),
                ),
                  onChanged: (value) {
                    setState(() {
                      _enteredBalance = double.tryParse(value) ?? 0.0;
                    });
                  },
                ),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          backgroundColor: Colors.black.withOpacity(0.7)),
                      onPressed: _saveBalance,
                      child: Text(
                        'حفظ',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.white.withOpacity(1),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          backgroundColor: Colors.black.withOpacity(0.7)),
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) =>
                              BalanceHistoryPage(clientId: widget.clientId),
                        ));
                      },
                      child: Text(
                        'عرض تاريخ الرصيد',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.white.withOpacity(1),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('clients')
                  .doc(widget.clientId)
                  .collection('invoices')
                  .orderBy('date', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(
                      child: CircularProgressIndicator(
                          color: Colors.orange.withOpacity(0.7)));
                }

                final invoices = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: invoices.length,
                  itemBuilder: (context, index) {
                    final invoiceRef = invoices[index].reference;
                    return FutureBuilder<DocumentSnapshot>(
                      future: invoiceRef.get(),
                      builder: (context, invoiceSnapshot) {
                        if (!invoiceSnapshot.hasData) {
                          return Center(
                              child: CircularProgressIndicator(
                                  color: Colors.orange.withOpacity(0.7)));
                        }

                        final invoice = invoiceSnapshot.data!;
                        DateTime invoiceDate =
                            invoice['date'].toDate().toLocal();
                        String formattedDate =
                            invoiceDate.toString().split(' ')[0];
                        String formattedTime =
                            DateFormat('hh:mm a').format(invoiceDate);

                        return Card(
                          margin: const EdgeInsets.all(10.0),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    'رقم الفاتورة: #${invoice['invoiceNumber']}',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 5),
                                Text('التاريخ: $formattedDate',
                                    style: const TextStyle(fontSize: 14)),
                                Text('$formattedTime :الوقت ',
                                    style: const TextStyle(fontSize: 14)),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: const [
                                    Text('المنتج',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold)),
                                    Text('الكمية',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold)),
                                    Text('السعر',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold)),
                                    Text('الإجمالي',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: invoice['products'].length,
                                  itemBuilder: (context, index) {
                                    final product = invoice['products'][index];
                                    final total = double.tryParse(
                                            product['total'].toString()) ??
                                        0.0;

                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 3.0),
                                      elevation: 2,
                                      color: Colors.orange.withOpacity(0.8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8.0),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceAround,
                                          children: [
                                            Text(product['product'],
                                                style: const TextStyle(
                                                    fontSize: 12)),
                                            Text(product['amount'],
                                                style: const TextStyle(
                                                    fontSize: 12)),
                                            Text(
                                              (double.tryParse(product[
                                                              'selectedPrice']
                                                          .toString()) ??
                                                      0.0)
                                                  .toStringAsFixed(2),
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                            Text(total.toStringAsFixed(2),
                                                style: const TextStyle(
                                                    fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'إجمالي الفاتورة: ${(double.tryParse(invoice['totalSum'].toString()) ?? 0.0).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            'المدفوع: ${(double.tryParse(invoice['paidAmount'].toString()) ?? 0.0).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                            ),
                                          ),
                                          Text(
                                            'المتبقي: ${((double.tryParse(invoice['totalSum'].toString()) ?? 0.0) - (double.tryParse(invoice['paidAmount'].toString()) ?? 0.0)).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class BalanceHistoryPage extends StatelessWidget {
  final String clientId;

  const BalanceHistoryPage({Key? key, required this.clientId})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تاريخ الرصيد'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('clients')
            .doc(clientId)
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
              final formattedDate =
                  DateFormat('yyyy-MM-dd').format(timestamp);

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
