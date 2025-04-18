import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'SupplierBalanceHistoryPage.dart';

class SupplierInvoicesPage extends StatefulWidget {
  final String supplierId;

  const SupplierInvoicesPage({Key? key, required this.supplierId})
      : super(key: key);

  @override
  _SupplierInvoicesPageState createState() => _SupplierInvoicesPageState();
}

class _SupplierInvoicesPageState extends State<SupplierInvoicesPage> {
  final TextEditingController _balanceController = TextEditingController();
  double _enteredBalance = 0.0;

 void _saveBalance() async {
   // Check if the balance field is empty
   if (_balanceController.text.isEmpty) {
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content: Text('من فضلك أدخل الرصيد')),
     );
     return;
   }

   // Show loading indicator
   showDialog(
     context: context,
     barrierDismissible: false,
     builder: (context) => Center(
       child: CircularProgressIndicator(
         color: Colors.orange.withOpacity(0.7),
       ),
     ),
   );

   try {
     final supplierDoc = FirebaseFirestore.instance.collection('suppliers').doc(widget.supplierId);
     final supplierSnapshot = await supplierDoc.get();
     final currentBalance = supplierSnapshot['totalBalance'] ?? 0.0;
     final newBalance = currentBalance - _enteredBalance;

     // Save the balance history
     await supplierDoc.collection('balanceHistory').add({
       'enteredBalance': _enteredBalance,
       'balanceBefore': currentBalance,
       'timestamp': FieldValue.serverTimestamp(),
     });

     // Update the supplier's balance
     await supplierDoc.update({'totalBalance': newBalance});

     // Dismiss the loading indicator before showing the SnackBar
     Navigator.of(context).pop();

     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content: Text('تم الحفظ بنجاح')),
     );
   } catch (e) {
     Navigator.of(context).pop();
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content: Text('حدث خطأ: $e')),
     );
   } finally {
     _balanceController.clear();
     setState(() {
       _enteredBalance = 0.0;
     });
   }
 }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فواتير المورد'),
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
                    fontSize: 18,
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.black.withOpacity(0.7),
                    ),
                  ),
                  prefixIcon: const Icon(Icons.attach_money_rounded),
                ) ,
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
                          builder: (context) => SupplierBalanceHistoryPage(
                              supplierId: widget.supplierId),
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
                  .collection('suppliers')
                  .doc(widget.supplierId)
                  .collection('buying invoices')
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
                                Text('الوقت: $formattedTime',
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
                                            product['totalCost'].toString()) ??
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
                                              (double.tryParse(product['cost']
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
