import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Full invoice layout captured as PNG for WhatsApp / sharing.
class InvoiceReceiptCard extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final double width;
  final String storeName;
  final String storeAddress;
  final String storePhone;

  const InvoiceReceiptCard({
    super.key,
    required this.invoice,
    this.width = 360,
    this.storeName = 'أبو مجدي للحدايد والعدد والديكور والخشب والحلايا',
    this.storeAddress = 'كفر الزيات - طنطا - الغربية',
    this.storePhone = '01010573888',
  });

  @override
  Widget build(BuildContext context) {
    final products =
        List<Map<String, dynamic>>.from(invoice['products'] ?? []);
    final previousBalance = _num(invoice['previousBalance']);
    final totalSum = _num(invoice['totalSum']);
    final paid = _num(invoice['paidAmount']);
    final balance = _num(invoice['balance']);
    final when = _parseDateTime(invoice['date']);
    final typeLabel = _paymentTypeLabel(invoice['paymentMethod']);
    final qtySum = products.fold<double>(
      0,
      (s, p) => s + _num(p['amount']),
    );

    return Container(
      width: width,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (storeName.trim().isNotEmpty)
            Center(
              child: Text(
                storeName.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (storeAddress.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Center(
              child: Text(
                storeAddress.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
          if (storePhone.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Center(
              child: Text(
                storePhone.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'فاتورة مبيعات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 12),
          _metaRow('النوع : $typeLabel', 'الرقم : ${invoice['invoiceNumber']}'),
          _metaRow('التاريخ : ${when.date}', 'الوقت : ${when.time}'),
          const Divider(height: 12),
          Center(
            child: Text(
              'اسم العميل : ${invoice['clientName']?.toString() ?? ''}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          _tableHeader(),
          const Divider(height: 8),
          ...products.map((p) => _productRow(p)),
          const Divider(height: 8),
          Center(
            child: Text(
              _formatQty(qtySum),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
          const Divider(height: 10),
          _totalRow('الرصيد السابق', _formatMoney(previousBalance)),
          _totalRow('إجمالي ف.', _formatMoney(totalSum), bold: true),
          _totalRow('المدفوع', _formatMoney(paid)),
          _totalRow(
            'الرصيد الحالي (عليكم)',
            _formatMoney(balance),
            bold: true,
          ),
          if ((invoice['notes']?.toString() ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'ملاحظات: ${invoice['notes']}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaRow(String right, String left) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(right, style: const TextStyle(fontSize: 12)),
          Text(left, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return const Row(
      children: [
        Expanded(
          flex: 2,
          child: Text('الإجمالي',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        ),
        Expanded(
          flex: 2,
          child: Text('السعر',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        ),
        Expanded(
          child: Text('الكمية',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        ),
        Expanded(
          flex: 4,
          child: Text('المنتج',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        ),
      ],
    );
  }

  Widget _productRow(Map<String, dynamic> p) {
    final name = p['product']?.toString() ?? '';
    final qty = _formatQty(_num(p['amount']));
    final price = _formatMoneyCompact(_num(p['selectedPrice']));
    final total = _formatMoneyCompact(_num(p['total']));

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(total,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10)),
          ),
          Expanded(
            flex: 2,
            child: Text(price,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10)),
          ),
          Expanded(
            child: Text(qty,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10)),
          ),
          Expanded(
            flex: 4,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatMoneyCompact(double value) {
    if (value == value.roundToDouble()) {
      return NumberFormat('#,##0', 'en_US').format(value);
    }
    return _money.format(value);
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label :',
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static final _money = NumberFormat('#,##0.00', 'en_US');

  static String _formatMoney(double value) => _money.format(value);

  static String _formatQty(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static String _paymentTypeLabel(dynamic method) {
    final m = method?.toString().trim() ?? '';
    if (m.isEmpty) return 'نقد';
    if (m.contains('آجل') || m.contains('اجل')) return 'اجل';
    if (m.contains('نقد')) return 'نقد';
    if (m.contains('بطاق')) return 'بطاقه';
    return m;
  }

  static _InvoiceWhen _parseDateTime(dynamic date) {
    DateTime? dt;
    if (date is Timestamp) {
      dt = date.toDate().toLocal();
    } else if (date is DateTime) {
      dt = date.toLocal();
    }
    if (dt == null) return const _InvoiceWhen(date: '', time: '');
    final d = dt;
    return _InvoiceWhen(
      date:
          '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}',
      time:
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}',
    );
  }
}

class _InvoiceWhen {
  final String date;
  final String time;

  const _InvoiceWhen({required this.date, required this.time});
}
