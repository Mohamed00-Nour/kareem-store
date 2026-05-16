import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'dart:ui' as ui;

class BuyingInvoiceDetailPage extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final GlobalKey _globalKey = GlobalKey();

  BuyingInvoiceDetailPage({super.key, required this.invoice});

  Future<void> _captureAndShareScreenshot() async {
    try {
      RenderRepaintBoundary boundary = _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      final imagePath = '${directory.path}/invoice.png';
      final file = File(imagePath);
      await file.writeAsBytes(pngBytes);

      await Share.shareFiles([file.path], text: 'إليك فاتورتك من معرض  كريم حماد للحدايد والبويات');
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    DateTime invoiceDate = invoice['date'].toDate().toLocal();
    String formattedDate = invoiceDate.toString().split(' ')[0];
    String formattedTime = DateFormat('hh:mm a').format(invoiceDate);
    return Scaffold(
      appBar: AppBar(
        title: Text('رقم الفاتورة #${invoice['invoiceNumber']}', style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            RepaintBoundary(
              key: _globalKey,
              child: Container(
                color: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 15.w, vertical: 15.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/images/boxes_11365317.png',
                        width: 200.w, // Adjust the width as needed
                        height: 100.h, // Adjust the height as needed
                        fit: BoxFit.fill, // Adjust the fit as needed
                      ),
                    ),
                    SizedBox(height: 5.h),
                    Center(
                      child: Text('فاتورة مشتريات' , style: TextStyle(
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
                                    text: 'اسم المورد: ',
                                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold),
                                  ),
                                  ...(() {
                                    final supplierName = invoice['supplierName'] ?? '';
                                    List<TextSpan> textSpans = [];
                                    for (int i = 0; i < supplierName.length; i += 15) {
                                      textSpans.add(
                                        TextSpan(
                                          text: supplierName.substring(
                                            i,
                                            i + 15 > supplierName.length ? supplierName.length : i + 15
                                          ) + (i + 15 < supplierName.length ? '\n' : ''),
                                          style: TextStyle(fontSize: 13.sp),
                                        ),
                                      );
                                    }
                                    return textSpans;
                                  })(),
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
                    SizedBox(height: 8.w),
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
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: invoice['products'].length,
                      itemBuilder: (context, index) {
                        final product = invoice['products'][index];
                        final total = (double.tryParse(product['totalCost']?.toString() ?? '0') ?? 0.0).toStringAsFixed(2);
                        final productName = product['product'] ?? '';
                        final amount = (double.tryParse(product['amount']?.toString() ?? '0') ?? 0.0).toStringAsFixed(2);
                        final cost = (double.tryParse(product['cost']?.toString() ?? '0') ?? 0.0).toStringAsFixed(2);// Ensure cost is not null and convert to String
            
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
                                      for (int i = 0; i < productName.length; i += 15)
                                        TextSpan(
                                          text: productName.substring(
                                              i,
                                              i + 15 > productName.length
                                                  ? productName.length
                                                  : i + 15) +
                                              (i + 15 < productName.length ? '\n' : ''),
                                          style: TextStyle(fontSize: 12.sp),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(amount, style: TextStyle(fontSize: 12.sp)),
                                Text(cost, style: TextStyle(fontSize: 12.sp)),
                                Text(total, style: TextStyle(fontSize: 12.sp)),
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
                                    'الرصيد السابق: ${(invoice.containsKey('previousBalance') ? (double.tryParse(invoice['previousBalance'].toString()) ?? 0.0) : 0.0).toStringAsFixed(2)}',
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
                                'المدفوع: ${invoice['paidAmount'].toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                              Text(
                                'المتبقي: ${invoice['balance'].toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.redAccent),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  backgroundColor: Colors.black.withOpacity(0.7),
                ),
                onPressed: _captureAndShareScreenshot,
                child: Text(
                  'إرسال الفاتورة',
                  style: TextStyle(
                    fontSize: 20.sp,
                    color: Colors.white.withOpacity(1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}