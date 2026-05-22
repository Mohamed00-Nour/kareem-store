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
    final clientBalance = previousBalance + totalSum - paid;
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
          Center(
            child: Image.asset(
              'assets/Magdy store.png',
              width: width * 0.38,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'أبو مجدي للحدايد والعدد والديكور والخشب والحلايا',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 2),
          const Center(
            child: Text(
              'كفر الزيات - طنطا - الغربية',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'فاتورة مبيعات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'كريم حماد: 01068462105 - 01207968495',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11),
            ),
          ),
          const Center(
            child: Text(
              'مجدي حماد: 01010573888 - 01201820045',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11),
            ),
          ),
          const SizedBox(height: 8),
          _metaTable(typeLabel, invoice['invoiceNumber']?.toString() ?? '', when),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'اسم العميل : ${invoice['clientName']?.toString() ?? ''}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          _productsTable(products, qtySum),
          const SizedBox(height: 8),
          _summaryTable(previousBalance, totalSum, paid, clientBalance),
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

  Widget _productsTable(List<Map<String, dynamic>> products, double qtySum) {
    final headers = ['الإجمالي', 'السعر', 'الكمية', 'اسم المنتج', 'م'];
    final headerCells = headers
        .map(
          (h) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Text(
              h,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        )
        .toList();

    final productRows = products.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final p = entry.value;
      final name = p['product']?.toString() ?? '';
      final qty = _formatQty(_num(p['amount']));
      final price = _formatMoneyCompact(_num(p['selectedPrice']));
      final total = _formatMoneyCompact(_num(p['total']));
      final cells = [total, price, qty, name, '$index'];
      return TableRow(
        children: cells.map((val) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              val,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10),
            ),
          );
        }).toList(),
      );
    }).toList();

    Widget _cell(String text, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: bold ? 11 : 10,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );

    final totalRow = TableRow(
      decoration: const BoxDecoration(color: Color(0xFFFDF0E6)),
      children: [
        _cell(''),
        _cell(''),
        _cell(_formatQty(qtySum), bold: true),
        _cell('إجمالي الكميات', bold: true),
        _cell(''),
      ],
    );

    return Table(
      border: TableBorder.all(color: Colors.grey.shade400),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(3.5),
        4: FlexColumnWidth(0.8),
      },
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFFDF0E6)),
          children: headerCells,
        ),
        ...productRows,
        totalRow,
      ],
    );
  }

  static String _formatMoneyCompact(double value) {
    if (value == value.roundToDouble()) {
      return NumberFormat('#,##0', 'en_US').format(value);
    }
    return _money.format(value);
  }

  Widget _metaTable(String typeLabel, String invoiceNo, _InvoiceWhen when) {
    return Table(
      border: TableBorder.all(color: Colors.grey.shade400),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFFDF0E6)),
          children: [
            _metaCell('النوع: $typeLabel'),
            _metaCell('الرقم: $invoiceNo'),
          ],
        ),
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFFDF0E6)),
          children: [
            _metaCell('التاريخ: ${when.date}'),
            _metaCell('الوقت: ${when.time}'),
          ],
        ),
      ],
    );
  }

  Widget _metaCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _summaryTable(
      double previousBalance, double totalSum, double paid, double balance) {
    return Table(
      border: TableBorder.all(color: Colors.grey.shade400),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(2),
      },
      children: [
        _summaryTableRow('الرصيد السابق', _formatMoney(previousBalance)),
        _summaryTableRow('إجمالي ف.', _formatMoney(totalSum), bold: true),
        _summaryTableRow('المدفوع', _formatMoney(paid)),
        _summaryTableRow(
            'الرصيد الحالي (عليكم)', _formatMoney(balance), bold: true),
      ],
    );
  }

  TableRow _summaryTableRow(String label, String value, {bool bold = false}) {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFFDF0E6)),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ),
      ],
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
