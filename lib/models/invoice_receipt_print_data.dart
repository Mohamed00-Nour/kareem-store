/// Structured receipt payload for native table rendering on thermal printers.
class InvoiceReceiptPrintData {
  final int paperMm;
  final int escFontSize;
  final String? logoAssetPath;
  final List<String> centeredLines;
  final List<List<String>> metaTableRows;
  final List<String> bodyLines;
  final List<String> tableHeaders;
  final List<InvoiceReceiptTableRow> tableRows;
  final String? qtyTotalLine;
  final List<List<String>> summaryTableRows;
  final List<String> trailingLines;
  final String salesFooter;

  const InvoiceReceiptPrintData({
    required this.paperMm,
    required this.escFontSize,
    this.logoAssetPath,
    this.centeredLines = const [],
    this.metaTableRows = const [],
    this.bodyLines = const [],
    this.tableHeaders = const ['م', 'اسم المنتج', 'الكمية', 'السعر', 'الإجمالي'],
    this.tableRows = const [],
    this.qtyTotalLine,
    this.summaryTableRows = const [],
    this.trailingLines = const [],
    this.salesFooter = '',
  });

  Map<String, dynamic> toMethodArgs() {
    return {
      'paperMm': paperMm,
      'escFontSize': escFontSize,
      'logoAssetPath': logoAssetPath,
      'centeredLines': centeredLines,
      'metaTableRows': metaTableRows,
      'bodyLines': bodyLines,
      'tableHeaders': tableHeaders,
      'tableRows': tableRows.map((r) => r.toMap()).toList(),
      'qtyTotalLine': qtyTotalLine,
      'summaryTableRows': summaryTableRows,
      'trailingLines': trailingLines,
      'salesFooter': salesFooter,
    };
  }
}

class InvoiceReceiptTableRow {
  final String rowNum;
  final String product;
  final String qty;
  final String price;
  final String total;
  final List<String> extraLines;

  const InvoiceReceiptTableRow({
    this.rowNum = '',
    required this.product,
    required this.qty,
    required this.price,
    required this.total,
    this.extraLines = const [],
  });

  Map<String, dynamic> toMap() => {
        'rowNum': rowNum,
        'product': product,
        'qty': qty,
        'price': price,
        'total': total,
        'extraLines': extraLines,
      };
}
