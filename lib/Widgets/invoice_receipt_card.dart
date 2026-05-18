import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Full invoice layout captured as PNG for WhatsApp / sharing.
class InvoiceReceiptCard extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final double width;

  const InvoiceReceiptCard({
    super.key,
    required this.invoice,
    this.width = 400,
  });

  @override
  Widget build(BuildContext context) {
    final products =
        List<Map<String, dynamic>>.from(invoice['products'] ?? []);
    final previousBalance = _num(invoice['previousBalance']);
    final totalSum = _num(invoice['totalSum']);
    final paid = _num(invoice['paidAmount']);
    final balance = _num(invoice['balance']);
    final discount = _num(invoice['invoiceDiscount']);
    final dateLabel = _formatDateTime(invoice['date']);

    return Container(
      width: width,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              'Kareem Store',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'فاتورة مبيعات',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 24),
          _infoRow('رقم الفاتورة', '#${invoice['invoiceNumber']}'),
          _infoRow('العميل', invoice['clientName']?.toString() ?? ''),
          _infoRow('التاريخ', dateLabel),
          if ((invoice['paymentMethod']?.toString() ?? '').isNotEmpty)
            _infoRow('طريقة الدفع', invoice['paymentMethod'].toString()),
          const SizedBox(height: 8),
          Row(
            children: const [
              Expanded(
                flex: 3,
                child: Text('المنتج',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              Expanded(
                child: Text('الكمية',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              Expanded(
                child: Text('السعر',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              Expanded(
                child: Text('الإجمالي',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...products.map((p) => _productRow(p)),
          const Divider(height: 20),
          if (discount > 0)
            _totalRow('الخصم', '-${discount.toStringAsFixed(2)} ج.م'),
          _totalRow('الرصيد السابق', '${previousBalance.toStringAsFixed(2)} ج.م'),
          _totalRow('إجمالي الفاتورة', '${totalSum.toStringAsFixed(2)} ج.م',
              bold: true),
          _totalRow('المدفوع', '${paid.toStringAsFixed(2)} ج.م',
              color: Colors.green.shade700),
          _totalRow('المتبقي على العميل', '${balance.toStringAsFixed(2)} ج.م',
              color: Colors.red.shade700, bold: true),
          if ((invoice['notes']?.toString() ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'ملاحظات: ${invoice['notes']}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'شكراً لتعاملكم معنا',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productRow(Map<String, dynamic> p) {
    final name = p['product']?.toString() ?? '';
    final qty = p['amount']?.toString() ?? '0';
    final price = _num(p['selectedPrice']).toStringAsFixed(2);
    final total = _num(p['total']).toStringAsFixed(2);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.75),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(name, style: const TextStyle(fontSize: 11)),
          ),
          Expanded(
            child: Text(qty,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11)),
          ),
          Expanded(
            child: Text(price,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11)),
          ),
          Expanded(
            child: Text(total,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13)),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.left, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: color,
              )),
          Text(value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: color,
              )),
        ],
      ),
    );
  }

  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static String _formatDateTime(dynamic date) {
    if (date == null) return '';
    try {
      DateTime dt;
      if (date is Timestamp) {
        dt = date.toDate().toLocal();
      } else if (date is DateTime) {
        dt = date.toLocal();
      } else {
        return date.toString();
      }
      return DateFormat('dd/MM/yyyy hh:mm a').format(dt);
    } catch (_) {
      return date.toString();
    }
  }
}
