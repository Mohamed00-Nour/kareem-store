import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../Screeens/AddProductPage.dart';
import '../Widgets/invoice_display_widgets.dart';
import '../Services/invoice_number_utils.dart';

class BuyingInvoiceDetailPage extends StatefulWidget {
  final Map<String, dynamic> invoice;

  const BuyingInvoiceDetailPage({super.key, required this.invoice});

  @override
  State<BuyingInvoiceDetailPage> createState() => _BuyingInvoiceDetailPageState();
}

class _BuyingInvoiceDetailPageState extends State<BuyingInvoiceDetailPage> {
  final GlobalKey _globalKey = GlobalKey();
  double? _currentSupplierBalance;
  bool _isLoadingBalance = true;

  @override
  void initState() {
    super.initState();
    _fetchSupplierBalance();
  }

  Future<void> _fetchSupplierBalance() async {
    final supplierName = widget.invoice['supplierName']?.toString() ?? '';
    final supplierId = widget.invoice['supplierId']?.toString() ?? '';
    double? totalBalance;
    try {
      if (supplierId.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('suppliers')
            .doc(supplierId)
            .get();
        if (snap.exists) {
          totalBalance = (snap.data()?['totalBalance'] as num?)?.toDouble();
        }
      }
      if (totalBalance == null && supplierName.isNotEmpty) {
        final query = await FirebaseFirestore.instance
            .collection('suppliers')
            .where('name', isEqualTo: supplierName)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          totalBalance =
              (query.docs.first.data()['totalBalance'] as num?)?.toDouble();
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _currentSupplierBalance = totalBalance;
        _isLoadingBalance = false;
      });
    }
  }

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
        text: 'إليك فاتورتك من معرض كريم حماد للحدايد والبويات',
      );
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Inject current supplier balance if resolved
    final invoiceData = Map<String, dynamic>.from(widget.invoice);
    if (_currentSupplierBalance != null) {
      invoiceData['currentSupplierBalance'] = _currentSupplierBalance;
    }

    final products = invoiceData['products'] as List<dynamic>? ?? [];
    final when = InvoiceDateParts.fromDynamic(invoiceData['date']);
    final supplierName = invoiceData['supplierName']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'رقم الفاتورة #${invoiceData['invoiceNumber']}',
          style: TextStyle(fontSize: 20.sp, color: Colors.white),
        ),
        backgroundColor: Colors.black.withOpacity(0.7),
        actions: [
          // ── Edit button ──
          IconButton(
            icon: Icon(Icons.edit_outlined, color: Colors.white, size: 22.sp),
            tooltip: 'تعديل الفاتورة',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddProductPage(invoiceToEdit: widget.invoice),
                ),
              );
            },
          ),
        ],
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
                                    text: '#${invoiceData['invoiceNumber']}',
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
                    InvoiceTotalsFooter(invoice: invoiceData),
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
                onPressed: _isLoadingBalance ? null : _captureAndShareScreenshot,
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
