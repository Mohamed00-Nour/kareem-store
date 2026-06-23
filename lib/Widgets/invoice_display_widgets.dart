import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../Services/invoice_number_utils.dart';

enum InvoiceDisplayKind { sales, purchase }

class InvoiceDateParts {
  final String date;
  final String time;

  const InvoiceDateParts({required this.date, required this.time});

  static InvoiceDateParts fromDynamic(dynamic value) {
    DateTime? dt;
    if (value is Timestamp) {
      dt = value.toDate();
    } else if (value is DateTime) {
      dt = value;
    }
    if (dt == null) {
      return const InvoiceDateParts(date: '', time: '');
    }
    final local = dt.toLocal();
    return InvoiceDateParts(
      date: '${local.year}-${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}',
      time: DateFormat('hh:mm a').format(local),
    );
  }
}

/// Bordered products table: header row plain, value cells bordered (م | اسم | كمية | سعر | إجمالي).
class InvoiceProductsTable extends StatelessWidget {
  final List<dynamic> products;
  final InvoiceDisplayKind kind;

  const InvoiceProductsTable({
    super.key,
    required this.products,
    this.kind = InvoiceDisplayKind.sales,
  });

  List<Map<String, dynamic>> get _rows => products
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  String _productName(Map<String, dynamic> row) => invoiceProductName(row);

  String _qty(Map<String, dynamic> row) => invoiceQty(row['amount']);

  String _price(Map<String, dynamic> row) {
    if (kind == InvoiceDisplayKind.purchase) {
      return invoiceAmount(row['cost'] ?? row['selectedPrice'], 2);
    }
    return invoiceAmount(row['selectedPrice'] ?? row['cost'], 2);
  }

  String _lineTotal(Map<String, dynamic> row) {
    if (kind == InvoiceDisplayKind.purchase) {
      final stored = row['totalCost'] ?? row['total'];
      if (stored != null) return invoiceAmount(stored, 2);
      final q = invoiceNum(row['amount']);
      final c = invoiceNum(row['cost'] ?? row['selectedPrice']);
      return invoiceAmount(q * c);
    }
    final stored = row['total'] ?? row['totalCost'];
    if (stored != null) return invoiceAmount(stored, 2);
    final q = invoiceNum(row['amount']);
    final p = invoiceNum(row['selectedPrice'] ?? row['cost']);
    return invoiceAmount(q * p);
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h),
        child: const Text(
          'لا توجد منتجات في هذه الفاتورة',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      );
    }

    var qtySum = 0.0;
    for (final p in _rows) {
      qtySum += invoiceNum(p['amount']);
    }

    Widget headerCell(String text, {TextAlign align = TextAlign.center}) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold),
        ),
      );
    }

    Widget valueCell(
      String text, {
      bool bold = false,
      TextAlign align = TextAlign.center,
    }) {
      return Container(
        margin: EdgeInsets.symmetric(horizontal: 2.w, vertical: 3.h),
        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade400, width: 1),
          borderRadius: BorderRadius.circular(6.r),
        ),
        alignment:
            align == TextAlign.right ? Alignment.centerRight : Alignment.center,
        child: Text(
          text,
          textAlign: align,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    }

    return Table(
      columnWidths: {
        0: const FlexColumnWidth(0.55),
        1: const FlexColumnWidth(2.6),
        2: const FlexColumnWidth(1.05),
        3: const FlexColumnWidth(1.05),
        4: const FlexColumnWidth(1.15),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: [
            headerCell('م'),
            headerCell('اسم المنتج', align: TextAlign.right),
            headerCell('الكمية'),
            headerCell('السعر'),
            headerCell('الإجمالي'),
          ],
        ),
        for (var i = 0; i < _rows.length; i++)
          TableRow(
            children: [
              valueCell('${i + 1}', bold: true),
              valueCell(_productName(_rows[i]), align: TextAlign.right),
              valueCell(_qty(_rows[i])),
              valueCell(_price(_rows[i])),
              valueCell(_lineTotal(_rows[i]), bold: true),
            ],
          ),
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            const SizedBox.shrink(),
            const SizedBox.shrink(),
            valueCell(invoiceQty(qtySum), bold: true),
            const SizedBox.shrink(),
            const SizedBox.shrink(),
          ],
        ),
      ],
    );
  }
}

/// Footer: الرصيد السابق، إجمالي، المدفوع، المتبقي (balance after invoice).
class InvoiceTotalsFooter extends StatelessWidget {
  final Map<String, dynamic> invoice;

  const InvoiceTotalsFooter({super.key, required this.invoice});

  Future<double> _fetchBalance() async {
    final isBuying = invoiceIsSupplierPurchase(invoice);
    if (isBuying) {
      if (invoice.containsKey('currentSupplierBalance') &&
          invoice['currentSupplierBalance'] != null) {
        return invoiceNum(invoice['currentSupplierBalance']);
      }
      final supplierName = invoice['supplierName']?.toString() ?? '';
      final supplierId = invoice['supplierId']?.toString() ?? '';
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
      return totalBalance ?? invoiceNum(invoice['balance']);
    } else {
      if (invoice.containsKey('currentClientBalance') &&
          invoice['currentClientBalance'] != null) {
        return invoiceNum(invoice['currentClientBalance']);
      }
      final clientName = invoice['clientName']?.toString() ?? '';
      final clientId = invoice['clientId']?.toString() ?? '';
      double? clientBalance;
      try {
        if (clientId.isNotEmpty) {
          final snap = await FirebaseFirestore.instance
              .collection('clients')
              .doc(clientId)
              .get();
          if (snap.exists) {
            clientBalance = (snap.data()?['balance'] as num?)?.toDouble();
          }
        }
        if (clientBalance == null && clientName.isNotEmpty) {
          final query = await FirebaseFirestore.instance
              .collection('clients')
              .where('clientName', isEqualTo: clientName)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            clientBalance =
                (query.docs.first.data()['balance'] as num?)?.toDouble();
          }
        }
      } catch (_) {}
      return clientBalance ?? invoiceNum(invoice['balance']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = invoiceNum(invoice['totalSum']);
    final paid = invoiceNum(invoice['paidAmount']);
    final remainingLabel = invoiceIsSupplierPurchase(invoice)
        ? 'المتبقي للمورد'
        : 'المتبقي عليكم';

    return FutureBuilder<double>(
      future: _fetchBalance(),
      initialData: invoiceIsSupplierPurchase(invoice)
          ? invoiceSupplierRemainingOwed(invoice)
          : invoiceClientRemainingOwed(invoice),
      builder: (context, snapshot) {
        final remaining = snapshot.data ?? 0.0;
        final unpaid = total - paid;
        final isReturn = invoiceIsReturn(invoice);
        final dynamicPrevious = isReturn ? remaining + unpaid : remaining - unpaid;

        return Padding(
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
                        'الرصيد السابق: ${invoiceAmount(dynamicPrevious)}',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 20.w),
                      Text(
                        'إجمالي الفاتورة: ${invoiceAmount(total)}',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'المدفوع: ${invoiceAmount(paid)}',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  Text(
                    'المتبقي من الفاتورة: ${invoiceAmount(total - paid)}',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  Text(
                    '$remainingLabel: ${invoiceAmount(remaining)}',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Standard invoice card body (header + optional actions + table + totals).
class InvoiceDisplayCard extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final InvoiceDisplayKind kind;
  final Widget? actions;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  const InvoiceDisplayCard({
    super.key,
    required this.invoice,
    this.kind = InvoiceDisplayKind.sales,
    this.actions,
    this.margin = const EdgeInsets.all(10),
    this.padding = const EdgeInsets.all(10),
  });

  @override
  Widget build(BuildContext context) {
    final when = InvoiceDateParts.fromDynamic(invoice['date']);
    final products = invoice['products'] as List<dynamic>? ?? [];

    return Card(
      margin: margin,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'رقم الفاتورة: #${invoice['invoiceNumber']}',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (actions != null)
                  Flexible(child: actions!),
              ],
            ),
            SizedBox(height: 5.h),
            if (when.date.isNotEmpty)
              Text(
                'التاريخ: ${when.date}',
                style: TextStyle(fontSize: 14.sp),
              ),
            if (when.time.isNotEmpty)
              Text(
                '${when.time} :الوقت',
                style: TextStyle(fontSize: 14.sp),
              ),
            SizedBox(height: 10.h),
            InvoiceProductsTable(products: products, kind: kind),
            InvoiceTotalsFooter(invoice: invoice),
          ],
        ),
      ),
    );
  }
}
