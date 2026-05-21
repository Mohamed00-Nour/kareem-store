import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../Widgets/invoice_display_widgets.dart';

class BuyingInvoiceDetailPage extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final GlobalKey _globalKey = GlobalKey();

  BuyingInvoiceDetailPage({super.key, required this.invoice});

  Future<void> _captureAndShareScreenshot() async {
    try {
      final boundary = _globalKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      final imagePath = '${directory.path}/invoice.png';
      final file = File(imagePath);
      await file.writeAsBytes(pngBytes);

      await Share.shareFiles(
        [file.path],
        text: 'إليك فاتورتك من معرض  كريم حماد للحدايد والبويات',
      );
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = invoice['products'] as List<dynamic>? ?? [];
    final when = InvoiceDateParts.fromDynamic(invoice['date']);
    final supplierName = invoice['supplierName']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'رقم الفاتورة #${invoice['invoiceNumber']}',
          style: TextStyle(fontSize: 20.sp, color: Colors.white),
        ),
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
                        width: 200.w,
                        height: 100.h,
                        fit: BoxFit.fill,
                      ),
                    ),
                    SizedBox(height: 5.h),
                    Center(
                      child: Text(
                        'فاتورة مشتريات',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.black.withOpacity(0.7),
                        ),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'رقم الفاتورة: ',
                                    style: TextStyle(
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '#${invoice['invoiceNumber']}',
                                    style: TextStyle(fontSize: 13.sp),
                                  ),
                                ],
                              ),
                            ),
                            if (when.time.isNotEmpty) ...[
                              SizedBox(height: 5.h),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: when.time,
                                      style: TextStyle(fontSize: 13.sp),
                                    ),
                                    TextSpan(
                                      text: ' :الوقت',
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
                                    style: TextStyle(
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextSpan(
                                    text: supplierName,
                                    style: TextStyle(fontSize: 13.sp),
                                  ),
                                ],
                              ),
                            ),
                            if (when.date.isNotEmpty) ...[
                              SizedBox(height: 5.h),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'التاريخ: ',
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(
                                      text: when.date,
                                      style: TextStyle(fontSize: 13.sp),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 10.h),
                    InvoiceProductsTable(
                      products: products,
                      kind: InvoiceDisplayKind.purchase,
                    ),
                    InvoiceTotalsFooter(invoice: invoice),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16.h),
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
