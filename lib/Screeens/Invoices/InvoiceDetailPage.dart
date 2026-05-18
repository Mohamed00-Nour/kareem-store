import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../Services/invoice_print_ui.dart';
import '../../Services/whatsapp_invoice_share_service.dart';

class InvoiceDetailPage extends StatelessWidget {
  final Map<String, dynamic> invoice;

  InvoiceDetailPage({super.key, required this.invoice});

  void _sendInvoiceToClient(BuildContext context) {
    WhatsappInvoiceShareService.showShareOptions(
      context,
      invoice: invoice,
    );
  }

  @override
  Widget build(BuildContext context) {
    DateTime invoiceDate = invoice['date'].toDate().toLocal();
    String formattedDate = invoiceDate.toString().split(' ')[0];
    String formattedTime = DateFormat('hh:mm a').format(invoiceDate);
    final previousBalance = invoice.containsKey('previousBalance')
        ? (double.tryParse(invoice['previousBalance'].toString()) ?? 0.0)
        : 0.0;
    return Scaffold(
      appBar: AppBar(
        title: Text('رقم الفاتورة #${invoice['invoiceNumber']}', style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
                color: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 15.w, vertical: 15.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/images/boxes_11365317.png',
                        width: 200.w,
                        height: 80.h,
                        fit: BoxFit.fill,
                      ),
                    ),
                    SizedBox(height: 5.h),
                    Center(
                      child: Text('فاتورة مبيعات' , style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.black.withOpacity(0.7),
                      ),),
                    ),
                    SizedBox(height: 5.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'رقم الفاتورة: ',
                                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold),
                                  ),
                                  TextSpan(
                                    text: '#${invoice['invoiceNumber']}',
                                    style: TextStyle(fontSize: 13.sp),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 5.h),
                            Text.rich(
                              TextSpan(
                                children: [

                                  TextSpan(
                                    text: formattedTime,
                                    style: TextStyle(fontSize: 13.sp),
                                  ),
                                  TextSpan(
                                    text: ' :الوقت',
                                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'اسم العميل: ',
                                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold),
                                  ),
                                  TextSpan(
                                    text: invoice['clientName'],
                                    style: TextStyle(fontSize: 13.sp),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 5.h),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'التاريخ: ',
                                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold),
                                  ),
                                  TextSpan(
                                    text: formattedDate,
                                    style: TextStyle(fontSize: 13.sp),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 5.w),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text('المنتج', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.black.withOpacity(0.7))),
                          Text('الكمية', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.black.withOpacity(0.7))),
                          Text('السعر', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.black.withOpacity(0.7))),
                          Text('الاجمالي', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.black.withOpacity(0.7))),
                        ],
                      ),
                    ),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: ScrollPhysics(),
                      itemCount: invoice['products'].length,
                      itemBuilder: (context, index) {
                        final product = invoice['products'][index];
                        final total = product['total'];
                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 3.h),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.h),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      for (int i = 0; i < product['product'].length; i += 15)
                                        TextSpan(
                                          text: product['product'].substring(
                                              i,
                                              i + 15 > product['product'].length
                                                  ? product['product'].length
                                                  : i + 15) +
                                              (i + 15 < product['product'].length ? '\n' : ''),
                                          style: TextStyle(fontSize: 12.sp),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(double.parse(product['amount']).toStringAsFixed(2), style: TextStyle(fontSize: 12.sp)),
                                Text(product['selectedPrice'].toStringAsFixed(2), style: TextStyle(fontSize: 12.sp)),
                                Text(total.toStringAsFixed(2), style: TextStyle(fontSize: 12.sp)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'الرصيد السابق: ${previousBalance.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 20.w),
                                  Text(
                                    'إجمالي الفاتورة: ${invoice['totalSum'].toStringAsFixed(2)}',
                                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Text(
                                'المدفوغ: ${invoice['paidAmount'].toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold , color: Colors.green),
                              ),
                              Text(
                                'المتبقي: ${invoice['balance'].toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold , color: Colors.redAccent),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    backgroundColor: Colors.blue.shade700,
                  ),
                  onPressed: () {
                    InvoicePrintUi.printInvoice(
                      context,
                      invoice,
                      clientId: invoice['clientName']?.toString(),
                    );
                  },
                  icon: Icon(Icons.print, color: Colors.white, size: 20.sp),
                  label: Text(
                    'طباعة',
                    style: TextStyle(
                      fontSize: 18.sp,
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    backgroundColor: Colors.deepPurple.shade400,
                  ),
                  onPressed: () {
                    InvoicePrintUi.previewInvoice(
                      context,
                      invoice,
                      clientId: invoice['clientName']?.toString(),
                    );
                  },
                  icon: Icon(Icons.receipt_long, color: Colors.white, size: 20.sp),
                  label: Text(
                    'معاينة (مؤقت)',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    backgroundColor: Colors.green.shade700,
                  ),
                  onPressed: () => _sendInvoiceToClient(context),
                  icon: Icon(Icons.chat, color: Colors.white, size: 20.sp),
                  label: Text(
                    'إرسال الفاتورة',
                    style: TextStyle(
                      fontSize: 18.sp,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}