import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../Services/invoice_print_ui.dart';
import '../Services/sales_invoices_fetch_service.dart';

/// Compact invoice card for grid lists (sales report / today invoices).
class SalesInvoiceCard extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final VoidCallback onTap;
  final VoidCallback onPrint;
  final VoidCallback onExportPdf;

  const SalesInvoiceCard({
    super.key,
    required this.invoice,
    required this.onTap,
    required this.onPrint,
    required this.onExportPdf,
  });

  @override
  Widget build(BuildContext context) {
    final date = SalesInvoicesFetchService.invoiceDate(invoice);
    final dateStr = date != null
        ? DateFormat('dd/MM/yyyy hh:mm a').format(date.toLocal())
        : '';
    final client = invoice['clientName']?.toString() ?? '';
    final number = invoice['invoiceNumber']?.toString() ?? '';
    final total = (invoice['totalSum'] as num?)?.toDouble() ?? 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(10.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'فاتورة #$number',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 4.h),
              Text(
                client,
                style: TextStyle(fontSize: 12.sp, color: Colors.black87),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (dateStr.isNotEmpty) ...[
                SizedBox(height: 4.h),
                Text(
                  dateStr,
                  style: TextStyle(fontSize: 10.sp, color: Colors.black54),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const Spacer(),
              Text(
                '${total.toStringAsFixed(2)} ج.م',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
              SizedBox(height: 4.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(Icons.picture_as_pdf,
                        size: 20, color: Colors.red.shade700),
                    tooltip: 'تصدير PDF',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
                    onPressed: onExportPdf,
                  ),
                  IconButton(
                    icon: const Icon(Icons.print_outlined, size: 20),
                    tooltip: 'طباعة',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
                    onPressed: onPrint,
                  ),
                  InvoicePrintUi.temporaryPreviewIconButton(
                    context,
                    invoice,
                    clientId: client.isNotEmpty ? client : null,
                  ),
                  IconButton(
                    icon: Icon(Icons.visibility_outlined,
                        size: 20, color: Colors.orange.shade800),
                    tooltip: 'التفاصيل',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
                    onPressed: onTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
