import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' hide TextDirection;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../Services/supplier_invoice_balance_sync_service.dart';
import 'SupplierListPage.dart';
import 'SupplierInvoicesPage.dart';

class SuppliersPage extends StatelessWidget {
  const SuppliersPage({Key? key}) : super(key: key);

  void _addNewSupplier(BuildContext context) {
    final nameCtrl = TextEditingController();
    final balanceCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: const Text('إضافة مورد جديد'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  enabled: !isSaving,
                  decoration: const InputDecoration(labelText: 'اسم المورد'),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: balanceCtrl,
                  enabled: !isSaving,
                  decoration:
                      const InputDecoration(labelText: 'الرصيد الافتتاحي'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                ),
                if (isSaving) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 8),
                  const Text(
                    'جاري الحفظ...',
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.7)),
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('يرجى إدخال اسم المورد')),
                          );
                          return;
                        }

                        setDialogState(() => isSaving = true);
                        try {
                          final opening =
                              double.tryParse(balanceCtrl.text.trim()) ?? 0.0;
                          // Opening balance = amount we owe the supplier → له (positive).
                          final totalBalance =
                              opening == 0 ? 0.0 : opening.abs();
                          final ref = await FirebaseFirestore.instance
                              .collection('suppliers')
                              .add({
                            'name': name,
                            'totalBalance': totalBalance,
                          });
                          await ref.update({'id': ref.id});
                          if (opening != 0) {
                            await FirebaseFirestore.instance
                                .collection('supplier_vouchers')
                                .add({
                              'supplierId': ref.id,
                              'supplierName': name,
                              'direction': 'له',
                              'amount': opening.abs(),
                              'description': 'رصيد افتتاحي',
                              'date': Timestamp.now(),
                              'timestamp': FieldValue.serverTimestamp(),
                            });
                            await ref.collection('balanceHistory').add({
                              'enteredBalance': opening.abs(),
                              'balanceBefore': 0.0,
                              'type': 'opening',
                              'direction': 'له',
                              'timestamp': FieldValue.serverTimestamp(),
                            });
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('تم إضافة المورد بنجاح')),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() => isSaving = false);
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('حدث خطأ أثناء الحفظ: $e')),
                            );
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('حفظ', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOpeningBalances(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _SupplierOpeningBalancesPage(),
      ),
    );
  }

  void _showRemainingFromDeferred(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _SupplierDeferredPage(),
      ),
    );
  }

  void _showRemainingReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _SupplierRemainingReportPage(),
      ),
    );
  }

  void _showBalanceReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _SupplierBalanceReportPage(),
      ),
    );
  }

  void _checkSupplierBalances(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _SupplierBalanceCheckPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _MenuItem(
        label: 'اضافة مورد جديد',
        icon: Icons.add,
        iconColor: Colors.green,
        onTap: () => _addNewSupplier(context),
      ),
      _MenuItem(
        label: 'الأرصدة الافتتاحيه والمبالغ النقدية للموردين',
        imagePath: null,
        customIcon: const Icon(Icons.settings, color: Colors.grey),
        onTap: () => _showOpeningBalances(context),
      ),
      _MenuItem(
        label: 'المبالغ المتبقية للموردين من الفواتير الآجل',
        icon: Icons.people,
        iconColor: Colors.brown,
        onTap: () => _showRemainingFromDeferred(context),
      ),
      _MenuItem(
        label: 'المبالغ المتبقية للموردين - تقرير',
        icon: Icons.receipt_long,
        iconColor: Colors.black54,
        onTap: () => _showRemainingReport(context),
      ),
      _MenuItem(
        label: 'الموردين المتبقي عندهم أرصدة - تقرير',
        icon: Icons.receipt_long,
        iconColor: Colors.black54,
        onTap: () => _showBalanceReport(context),
      ),
      _MenuItem(
        label: 'فحص ارصدة الموردين',
        icon: Icons.receipt_long,
        iconColor: Colors.black54,
        onTap: () => _checkSupplierBalances(context),
      ),
      _MenuItem(
        label: 'عرض الموردين',
        icon: Icons.search,
        iconColor: Colors.black54,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SupplierListPage()),
        ),
      ),
    ];

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: const Text(
            'الموردين',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: Colors.grey.shade300),
          itemBuilder: (context, index) {
            final item = items[index];
            return InkWell(
              onTap: item.onTap,
              child: Container(
                color: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    item.customIcon ??
                        Icon(item.icon, color: item.iconColor, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MenuItem {
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final Widget? customIcon;
  final String? imagePath;
  final VoidCallback onTap;

  const _MenuItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.iconColor,
    this.customIcon,
    this.imagePath,
  });
}

// ─── Opening Balances Page ───────────────────────────────────────────────────

class _SupplierOpeningBalancesPage extends StatefulWidget {
  const _SupplierOpeningBalancesPage();

  @override
  State<_SupplierOpeningBalancesPage> createState() =>
      _SupplierOpeningBalancesPageState();
}

class _SupplierOpeningBalancesPageState
    extends State<_SupplierOpeningBalancesPage> {
  String _search = '';
  bool _generating = false;

  void _showReportChoiceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'اختر نوع التقرير',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.blue),
                title: const Text('تقرير الأرصدة الافتتاحية والمبالغ النقدية'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generatePdf();
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('تقرير سند الصرف'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generateVoucherPdf('عليه', 'تقرير سند الصرف');
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.green),
                title: const Text('تقرير سند القبض'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generateVoucherPdf('له', 'تقرير سند القبض');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generateVoucherPdf(String direction, String reportTitle) async {
    // Ask for voucher number first
    final voucherCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Text(reportTitle),
          content: TextField(
            controller: voucherCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'رقم السند',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('طباعة'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || voucherCtrl.text.trim().isEmpty) return;
    final voucherNumber = int.tryParse(voucherCtrl.text.trim());
    if (voucherNumber == null) return;

    setState(() => _generating = true);
    try {
      final amiriRegularData = await rootBundle.load('fonts/Amiri-Regular.ttf');
      final amiriBoldData = await rootBundle.load('fonts/Amiri-Bold.ttf');
      final amiriRegular = pw.Font.ttf(amiriRegularData.buffer.asByteData());
      final amiriBold = pw.Font.ttf(amiriBoldData.buffer.asByteData());

      final now = DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy').format(now);
      final timeStr = DateFormat('hh:mm:ss a').format(now);

      // Fetch the specific voucher
      final snap = await FirebaseFirestore.instance
          .collection('supplier_vouchers')
          .where('direction', isEqualTo: direction)
          .where('voucherNumber', isEqualTo: voucherNumber)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('لم يتم العثور على سند برقم $voucherNumber')),
          );
        }
        return;
      }

      final data = snap.docs.first.data();
      final voucherDate = (data['date'] is Timestamp)
          ? DateFormat('yyyy/MM/dd')
              .format((data['date'] as Timestamp).toDate())
          : data['date']?.toString() ?? '';
      final supplierName = (data['supplierName'] ?? '').toString();
      final amount = (data['amount'] ?? 0.0).toDouble();
      final description = (data['description'] ?? '').toString();
      final vNum = data['voucherNumber']?.toString() ?? '';

      pw.TextStyle s(
              {bool bold = false,
              PdfColor color = PdfColors.black,
              double fontSize = 11}) =>
          pw.TextStyle(
            font: bold ? amiriBold : amiriRegular,
            fontSize: fontSize,
            color: color,
          );

      pw.TableRow row3(String arabic, String english, String value) =>
          pw.TableRow(
            children: [
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: pw.Text(english, style: s()),
              ),
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: pw.Text(value,
                    textDirection: pw.TextDirection.rtl,
                    textAlign: pw.TextAlign.center,
                    style: s(bold: true)),
              ),
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: pw.Text(arabic,
                    textDirection: pw.TextDirection.rtl,
                    textAlign: pw.TextAlign.right,
                    style: s(bold: true)),
              ),
            ],
          );

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Header: date/time
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Date: $dateStr', style: s(fontSize: 9)),
                        pw.Text('Time: $timeStr', style: s(fontSize: 9)),
                      ],
                    ),
                    pw.SizedBox(),
                  ],
                ),
                pw.SizedBox(height: 20),

                // Title row
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('#$vNum#', style: s(fontSize: 12)),
                    pw.Text(
                      reportTitle,
                      textDirection: pw.TextDirection.rtl,
                      style: s(bold: true, fontSize: 16),
                    ),
                    pw.Text('ج.م', style: s(fontSize: 12)),
                  ],
                ),
                pw.SizedBox(height: 16),

                // Receipt table
                pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.black, width: 0.7),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2), // English label
                    1: const pw.FlexColumnWidth(3), // Value
                    2: const pw.FlexColumnWidth(2), // Arabic label
                  },
                  children: [
                    row3('رقم السند', 'No.', vNum),
                    row3('التاريخ', 'Date', voucherDate),
                    row3(
                        'تم تسليم السيد/الساده', 'Pay To Mr/Mrs', supplierName),
                    row3('مبلغ وقدره', 'Amount',
                        'فقط ${amount.toStringAsFixed(2)} ج.م لا غير'),
                    row3('وذلك مقابل', 'For', description),
                  ],
                ),

                pw.SizedBox(height: 60),

                // Signature row
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('المدير',
                            textDirection: pw.TextDirection.rtl,
                            style: s(bold: true)),
                        pw.SizedBox(height: 30),
                        pw.Container(
                            width: 120, height: 1, color: PdfColors.black),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('المستلم',
                            textDirection: pw.TextDirection.rtl,
                            style: s(bold: true)),
                        pw.SizedBox(height: 30),
                        pw.Container(
                            width: 120, height: 1, color: PdfColors.black),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final safeTitle = direction == 'عليه' ? 'sarf' : 'qabdh';
      final file = File(
          '${dir.path}/voucher_${safeTitle}_${vNum}_${dateStr.replaceAll('/', '-')}.pdf');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: ui.TextDirection.rtl,
            child: AlertDialog(
              title: Text(reportTitle),
              content: const Text('تم إنشاء السند. ماذا تريد أن تفعل؟'),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('مشاركة'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Share.shareXFiles(
                      [XFile(file.path)],
                      text: reportTitle,
                    );
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await OpenFilex.open(file.path);
                  },
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء السند: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generatePdf() async {
    setState(() => _generating = true);
    try {
      final amiriRegularData = await rootBundle.load('fonts/Amiri-Regular.ttf');
      final amiriBoldData = await rootBundle.load('fonts/Amiri-Bold.ttf');
      final amiriRegular = pw.Font.ttf(amiriRegularData.buffer.asByteData());
      final amiriBold = pw.Font.ttf(amiriBoldData.buffer.asByteData());

      final now = DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy').format(now);
      final timeStr = DateFormat('hh:mm:ss a').format(now);

      final snap = await FirebaseFirestore.instance
          .collection('suppliers')
          .orderBy('name')
          .get();

      final rows = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final name = (doc['name'] ?? '').toString();
        final balance = (doc['totalBalance'] ?? 0.0).toDouble();
        final lahu = balance > 0 ? balance : 0.0;
        final alayhi = balance < 0 ? balance.abs() : 0.0;
        rows.add({'name': name, 'lahu': lahu, 'alayhi': alayhi});
      }

      final grandLahu =
          rows.fold<double>(0.0, (s, r) => s + (r['lahu'] as double));
      final grandAlayhi =
          rows.fold<double>(0.0, (s, r) => s + (r['alayhi'] as double));

      pw.TextStyle cell(
              {bool bold = false,
              PdfColor color = PdfColors.black,
              double fontSize = 10}) =>
          pw.TextStyle(
            font: bold ? amiriBold : amiriRegular,
            fontSize: fontSize,
            color: color,
          );

      pw.Widget headerCell(String text) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: pw.Text(
              text,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: cell(bold: true, fontSize: 9),
            ),
          );

      pw.Widget dataCell(String text, {bool red = false, bool bold = false}) =>
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: pw.Text(
              text,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: cell(
                  bold: bold, color: red ? PdfColors.red : PdfColors.black),
            ),
          );

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Date: $dateStr', style: cell(fontSize: 9)),
                        pw.Text('Time: $timeStr', style: cell(fontSize: 9)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Center(
                  child: pw.Text(
                    'الأرصدة الافتتاحية والمبالغ النقدية للموردين',
                    textDirection: pw.TextDirection.rtl,
                    style: cell(bold: true, fontSize: 14),
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FlexColumnWidth(3),
                    2: const pw.FlexColumnWidth(2),
                    3: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        headerCell('#'),
                        headerCell('اسم المورد'),
                        headerCell('له'),
                        headerCell('عليه'),
                      ],
                    ),
                    for (int i = 0; i < rows.length; i++)
                      pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: i.isEven ? PdfColors.white : PdfColors.grey50,
                        ),
                        children: [
                          dataCell('${i + 1}'),
                          dataCell(rows[i]['name'] as String),
                          dataCell(
                              (rows[i]['lahu'] as double).toStringAsFixed(2),
                              red: (rows[i]['lahu'] as double) > 0),
                          dataCell(
                              (rows[i]['alayhi'] as double).toStringAsFixed(2)),
                        ],
                      ),
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey100),
                      children: [
                        dataCell(''),
                        dataCell('الإجمالي', bold: true, red: true),
                        dataCell(grandLahu.toStringAsFixed(2),
                            bold: true, red: true),
                        dataCell(grandAlayhi.toStringAsFixed(2), bold: true),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final fileName = 'opening_balances_${dateStr.replaceAll('/', '-')}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: ui.TextDirection.rtl,
            child: AlertDialog(
              title: const Text('تقرير الأرصدة الافتتاحية'),
              content: const Text('تم إنشاء التقرير. ماذا تريد أن تفعل؟'),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('مشاركة'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Share.shareXFiles(
                      [XFile(file.path)],
                      text: 'الأرصدة الافتتاحية والمبالغ النقدية للموردين',
                    );
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await OpenFilex.open(file.path);
                  },
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء التقرير: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showAddAmountDialog(BuildContext context, String supplierId,
      String supplierName, double currentBalance) async {
    // Get next voucher number
    final voucherSnap = await FirebaseFirestore.instance
        .collection('supplier_vouchers')
        .orderBy('voucherNumber', descending: true)
        .limit(1)
        .get();
    final nextVoucher = voucherSnap.docs.isNotEmpty
        ? (voucherSnap.docs.first['voucherNumber'] as int) + 1
        : 1;

    String direction = 'عليه'; // 'له' or 'عليه'
    String paymentMethod = 'نقداً'; // 'نقداً', 'بطاقة', 'شيك'
    DateTime selectedDate = DateTime.now();
    final amountCtrl = TextEditingController(text: '0');
    final descCtrl = TextEditingController();
    final voucherCtrl = TextEditingController(text: nextVoucher.toString());
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return Directionality(
            textDirection: ui.TextDirection.rtl,
            child: Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title
                      const Text(
                        'اضف مبلغ للمورد',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        supplierName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16,
                            color: Colors.red,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),

                      // له / عليه
                      Container(
                        color: Colors.grey.shade100,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Row(children: [
                              Radio<String>(
                                value: 'عليه',
                                groupValue: direction,
                                activeColor: Colors.green,
                                onChanged: isSaving
                                    ? null
                                    : (v) => setDlg(() => direction = v!),
                              ),
                              const Text('عليه',
                                  style: TextStyle(fontSize: 15)),
                            ]),
                            Row(children: [
                              Radio<String>(
                                value: 'له',
                                groupValue: direction,
                                activeColor: Colors.green,
                                onChanged: isSaving
                                    ? null
                                    : (v) => setDlg(() => direction = v!),
                              ),
                              const Text('له', style: TextStyle(fontSize: 15)),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // رقم السند
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: voucherCtrl,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              enabled: !isSaving,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text('رقم السند',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // البيان
                      TextField(
                        controller: descCtrl,
                        textAlign: TextAlign.right,
                        enabled: !isSaving,
                        decoration: InputDecoration(
                          hintText: 'البيان : تفاصيل السند',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 12),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // التاريخ
                      InkWell(
                        onTap: isSaving
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setDlg(() => selectedDate = picked);
                                }
                              },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text('التاريخ',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(fontSize: 15)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // طريقة الدفع
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Wrap(
                          alignment: WrapAlignment.spaceEvenly,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Radio<String>(
                                value: 'شيك',
                                groupValue: paymentMethod,
                                activeColor: Colors.green,
                                onChanged: isSaving
                                    ? null
                                    : (v) => setDlg(() => paymentMethod = v!),
                              ),
                              const Text('شيك'),
                            ]),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Radio<String>(
                                value: 'بطاقة',
                                groupValue: paymentMethod,
                                activeColor: Colors.green,
                                onChanged: isSaving
                                    ? null
                                    : (v) => setDlg(() => paymentMethod = v!),
                              ),
                              const Text('بطاقة'),
                            ]),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Radio<String>(
                                value: 'نقداً',
                                groupValue: paymentMethod,
                                activeColor: Colors.green,
                                onChanged: isSaving
                                    ? null
                                    : (v) => setDlg(() => paymentMethod = v!),
                              ),
                              const Text('نقداً'),
                            ]),
                            const Text('طريقة الدفع',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // المبلغ
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: amountCtrl,
                              textAlign: TextAlign.center,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              enabled: !isSaving,
                              style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: isSaving
                                    ? Colors.grey.shade200
                                    : Colors.yellow.shade200,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text('المبلغ',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          TextButton(
                            onPressed:
                                isSaving ? null : () => Navigator.pop(ctx),
                            child: const Text('تراجع',
                                style: TextStyle(
                                    color: Colors.pink, fontSize: 15)),
                          ),
                          TextButton(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    final amount =
                                        double.tryParse(amountCtrl.text) ?? 0.0;
                                    if (amount == 0) return;

                                    setDlg(() => isSaving = true);

                                    try {
                                      final isOwedToSupplier =
                                          direction == 'له';
                                      double delta =
                                          isOwedToSupplier ? amount : -amount;

                                      // Get current supplier balance
                                      DocumentSnapshot supplierDoc =
                                          await FirebaseFirestore.instance
                                              .collection('suppliers')
                                              .doc(supplierId)
                                              .get();

                                      double latestBalance = 0.0;
                                      if (supplierDoc.exists) {
                                        latestBalance =
                                            (supplierDoc['totalBalance'] ?? 0.0)
                                                .toDouble();
                                      } else {
                                        latestBalance = currentBalance;
                                      }

                                      double newBalance = latestBalance + delta;

                                      // Update supplier balance
                                      await FirebaseFirestore.instance
                                          .collection('suppliers')
                                          .doc(supplierId)
                                          .update({'totalBalance': newBalance});

                                      final vNumber =
                                          int.tryParse(voucherCtrl.text) ??
                                              nextVoucher;

                                      // Record voucher
                                      await FirebaseFirestore.instance
                                          .collection('supplier_vouchers')
                                          .add({
                                        'supplierId': supplierId,
                                        'supplierName': supplierName,
                                        'voucherNumber': vNumber,
                                        'direction': direction,
                                        'amount': amount,
                                        'description': descCtrl.text,
                                        'date': selectedDate,
                                        'paymentMethod': paymentMethod,
                                        'timestamp':
                                            FieldValue.serverTimestamp(),
                                      });

                                      // Construct notes for the balance history
                                      String noteStr = 'سند $direction';
                                      noteStr += ' رقم $vNumber';
                                      final dText = descCtrl.text.trim();
                                      if (dText.isNotEmpty) {
                                        noteStr += ' ($dText)';
                                      }

                                      // Add to balanceHistory
                                      await FirebaseFirestore.instance
                                          .collection('suppliers')
                                          .doc(supplierId)
                                          .collection('balanceHistory')
                                          .add({
                                        'enteredBalance': amount,
                                        'balanceBefore': latestBalance,
                                        'type': 'voucher',
                                        'direction': direction,
                                        'notes': noteStr,
                                        'timestamp': selectedDate,
                                      });

                                      // Update the box collection
                                      DocumentReference boxDocRef =
                                          FirebaseFirestore.instance
                                              .collection('box')
                                              .doc('mainBox');

                                      await FirebaseFirestore.instance
                                          .runTransaction((transaction) async {
                                        DocumentSnapshot boxSnapshot =
                                            await transaction.get(boxDocRef);

                                        if (boxSnapshot.exists) {
                                          double currentBoxValue =
                                              (boxSnapshot['value'] ?? 0.0)
                                                  .toDouble();
                                          transaction.update(boxDocRef, {
                                            'value': isOwedToSupplier
                                                ? currentBoxValue - amount
                                                : currentBoxValue + amount
                                          });
                                        } else {
                                          transaction.set(boxDocRef, {
                                            'value':
                                                isOwedToSupplier ? -amount : amount
                                          });
                                        }
                                      });

                                      // Add change to the box subcollection
                                      await boxDocRef
                                          .collection('changes')
                                          .add({
                                        'date': FieldValue.serverTimestamp(),
                                        'value': amount,
                                        'type': isOwedToSupplier
                                            ? 'decrement'
                                            : 'addition',
                                        'name': supplierName,
                                        'notes': noteStr,
                                        'invoiceNumber': null,
                                      });

                                      await SupplierInvoiceBalanceSyncService
                                          .syncForSupplier(supplierId);

                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'تم إضافة المبلغ بنجاح')),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  'حدث خطأ أثناء الإضافة: $e')),
                                        );
                                      }
                                    } finally {
                                      if (ctx.mounted) {
                                        setDlg(() => isSaving = false);
                                      }
                                    }
                                  },
                            child: isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.pink),
                                    ),
                                  )
                                : const Text('اضافة المبلغ',
                                    style: TextStyle(
                                        color: Colors.pink, fontSize: 15)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'الأرصدة الافتتاحية والمبالغ النقدية للموردين',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        body: Column(
          children: [
            // Search + تقرير
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade300,
                          foregroundColor: Colors.black),
                      onPressed: _generating ? null : _showReportChoiceDialog,
                      child: _generating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('تقرير'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        hintText: 'بحث',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                ],
              ),
            ),

            // Table header
            Container(
              color: Colors.grey.shade200,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: const Row(
                children: [
                  Expanded(
                      child: Text('عليه',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                      child: Text('له',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 2,
                      child: Text('بيانات المورد',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
            ),

            // List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('suppliers')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final suppliers = snapshot.data!.docs.where((d) {
                    if (_search.isEmpty) return true;
                    return (d['name'] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(_search.toLowerCase());
                  }).toList();

                  return ListView.separated(
                    itemCount: suppliers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final doc = suppliers[index];
                      final name = (doc['name'] ?? '').toString();
                      final balance = (doc['totalBalance'] ?? 0.0).toDouble();
                      final lahu = balance < 0 ? balance.abs() : 0.0;
                      final alayhi = balance > 0 ? balance : 0.0;

                      return InkWell(
                        onTap: () => _showAddAmountDialog(
                            context, doc.id, name, balance),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              // عليه
                              Expanded(
                                child: Container(
                                  alignment: Alignment.center,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  color: Colors.grey.shade200,
                                  child: Text(
                                    alayhi.toStringAsFixed(2),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // له
                              Expanded(
                                child: Container(
                                  alignment: Alignment.center,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  color: Colors.brown.shade100,
                                  child: Text(
                                    lahu.toStringAsFixed(2),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Name + number
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(name,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(
                                      '${index + 1}',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Deferred Invoices Page ──────────────────────────────────────────────────

class _SupplierDeferredPage extends StatefulWidget {
  const _SupplierDeferredPage();

  @override
  State<_SupplierDeferredPage> createState() => _SupplierDeferredPageState();
}

class _SupplierDeferredPageState extends State<_SupplierDeferredPage> {
  String _search = '';
  bool _generating = false;

  void _showReportChoiceDialog(
      List<MapEntry<String, double>> allEntries, double grandTotal) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'اختر نوع التقرير',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.orange),
                title: const Text('تقرير المبالغ المتبقية من الفواتير الآجل'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generatePdf(allEntries, grandTotal);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('تقرير سند الصرف'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generateVoucherPdf('عليه', 'تقرير سند الصرف');
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.green),
                title: const Text('تقرير سند القبض'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generateVoucherPdf('له', 'تقرير سند القبض');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generateVoucherPdf(String direction, String reportTitle) async {
    // Ask for voucher number first
    final voucherCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Text(reportTitle),
          content: TextField(
            controller: voucherCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'رقم السند',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('طباعة'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || voucherCtrl.text.trim().isEmpty) return;
    final voucherNumber = int.tryParse(voucherCtrl.text.trim());
    if (voucherNumber == null) return;

    setState(() => _generating = true);
    try {
      final amiriRegularData = await rootBundle.load('fonts/Amiri-Regular.ttf');
      final amiriBoldData = await rootBundle.load('fonts/Amiri-Bold.ttf');
      final amiriRegular = pw.Font.ttf(amiriRegularData.buffer.asByteData());
      final amiriBold = pw.Font.ttf(amiriBoldData.buffer.asByteData());

      final now = DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy').format(now);
      final timeStr = DateFormat('hh:mm:ss a').format(now);

      // Fetch the specific voucher
      final snap = await FirebaseFirestore.instance
          .collection('supplier_vouchers')
          .where('direction', isEqualTo: direction)
          .where('voucherNumber', isEqualTo: voucherNumber)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('لم يتم العثور على سند برقم $voucherNumber')),
          );
        }
        return;
      }

      final data = snap.docs.first.data();
      final voucherDate = (data['date'] is Timestamp)
          ? DateFormat('yyyy/MM/dd')
              .format((data['date'] as Timestamp).toDate())
          : data['date']?.toString() ?? '';
      final supplierName = (data['supplierName'] ?? '').toString();
      final amount = (data['amount'] ?? 0.0).toDouble();
      final description = (data['description'] ?? '').toString();
      final vNum = data['voucherNumber']?.toString() ?? '';

      pw.TextStyle s(
              {bool bold = false,
              PdfColor color = PdfColors.black,
              double fontSize = 11}) =>
          pw.TextStyle(
            font: bold ? amiriBold : amiriRegular,
            fontSize: fontSize,
            color: color,
          );

      pw.TableRow row3(String arabic, String english, String value) =>
          pw.TableRow(
            children: [
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: pw.Text(english, style: s()),
              ),
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: pw.Text(value,
                    textDirection: pw.TextDirection.rtl,
                    textAlign: pw.TextAlign.center,
                    style: s(bold: true)),
              ),
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: pw.Text(arabic,
                    textDirection: pw.TextDirection.rtl,
                    textAlign: pw.TextAlign.right,
                    style: s(bold: true)),
              ),
            ],
          );

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Header: date/time only
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Date: $dateStr', style: s(fontSize: 9)),
                        pw.Text('Time: $timeStr', style: s(fontSize: 9)),
                      ],
                    ),
                    pw.SizedBox(),
                  ],
                ),
                pw.SizedBox(height: 20),

                // Title row with voucher# and currency
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('#$vNum#', style: s(fontSize: 12)),
                    pw.Text(
                      reportTitle,
                      textDirection: pw.TextDirection.rtl,
                      style: s(bold: true, fontSize: 16),
                    ),
                    pw.Text('ج.م', style: s(fontSize: 12)),
                  ],
                ),
                pw.SizedBox(height: 16),

                // Receipt table
                pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.black, width: 0.7),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2), // English label
                    1: const pw.FlexColumnWidth(3), // Value
                    2: const pw.FlexColumnWidth(2), // Arabic label
                  },
                  children: [
                    row3('رقم السند', 'No.', vNum),
                    row3('التاريخ', 'Date', voucherDate),
                    row3(
                        'تم تسليم السيد/الساده', 'Pay To Mr/Mrs', supplierName),
                    row3('مبلغ وقدره', 'Amount',
                        'فقط ${amount.toStringAsFixed(2)} ج.م لا غير'),
                    row3('وذلك مقابل', 'For', description),
                  ],
                ),

                pw.SizedBox(height: 60),

                // Signature row
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('المدير',
                            textDirection: pw.TextDirection.rtl,
                            style: s(bold: true)),
                        pw.SizedBox(height: 30),
                        pw.Container(
                            width: 120, height: 1, color: PdfColors.black),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('المستلم',
                            textDirection: pw.TextDirection.rtl,
                            style: s(bold: true)),
                        pw.SizedBox(height: 30),
                        pw.Container(
                            width: 120, height: 1, color: PdfColors.black),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final safeTitle = direction == 'عليه' ? 'sarf' : 'qabdh';
      final file = File(
          '${dir.path}/voucher_${safeTitle}_${vNum}_${dateStr.replaceAll('/', '-')}.pdf');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: ui.TextDirection.rtl,
            child: AlertDialog(
              title: Text(reportTitle),
              content: const Text('تم إنشاء السند. ماذا تريد أن تفعل؟'),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('مشاركة'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Share.shareXFiles(
                      [XFile(file.path)],
                      text: reportTitle,
                    );
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await OpenFilex.open(file.path);
                  },
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء السند: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _navigateToSupplierInvoices(
      BuildContext context, String supplierName) async {
    final snap = await FirebaseFirestore.instance
        .collection('suppliers')
        .where('name', isEqualTo: supplierName)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return;
    final supplierId = snap.docs.first.id;
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SupplierInvoicesPage(supplierId: supplierId),
        ),
      );
    }
  }

  Future<void> _generatePdf(
      List<MapEntry<String, double>> entries, double grandTotal) async {
    setState(() => _generating = true);
    try {
      final amiriRegularData = await rootBundle.load('fonts/Amiri-Regular.ttf');
      final amiriBoldData = await rootBundle.load('fonts/Amiri-Bold.ttf');
      final amiriRegular = pw.Font.ttf(amiriRegularData.buffer.asByteData());
      final amiriBold = pw.Font.ttf(amiriBoldData.buffer.asByteData());

      final now = DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy').format(now);
      final timeStr = DateFormat('hh:mm:ss a').format(now);

      pw.TextStyle cell(
              {bool bold = false,
              PdfColor color = PdfColors.black,
              double fontSize = 10}) =>
          pw.TextStyle(
            font: bold ? amiriBold : amiriRegular,
            fontSize: fontSize,
            color: color,
          );

      pw.Widget headerCell(String text) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: pw.Text(
              text,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: cell(bold: true, fontSize: 9),
            ),
          );

      pw.Widget dataCell(String text, {bool red = false, bool bold = false}) =>
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: pw.Text(
              text,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: cell(
                  bold: bold, color: red ? PdfColors.red : PdfColors.black),
            ),
          );

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Date: $dateStr', style: cell(fontSize: 9)),
                        pw.Text('Time: $timeStr', style: cell(fontSize: 9)),
                      ],
                    ),
                    pw.Text('MicroPOS',
                        style: cell(
                            bold: true, fontSize: 12, color: PdfColors.blue)),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Center(
                  child: pw.Text(
                    'المبالغ المتبقية من الفواتير الآجل',
                    textDirection: pw.TextDirection.rtl,
                    style: cell(bold: true, fontSize: 14),
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FlexColumnWidth(3),
                    2: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        headerCell('#'),
                        headerCell('اسم المورد'),
                        headerCell('المبلغ المتبقي'),
                      ],
                    ),
                    for (int i = 0; i < entries.length; i++)
                      pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: i.isEven ? PdfColors.white : PdfColors.grey50,
                        ),
                        children: [
                          dataCell('${i + 1}'),
                          dataCell(entries[i].key),
                          dataCell(entries[i].value.toStringAsFixed(2),
                              red: true),
                        ],
                      ),
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey100),
                      children: [
                        dataCell(''),
                        dataCell('الإجمالي', bold: true, red: true),
                        dataCell(grandTotal.toStringAsFixed(2),
                            bold: true, red: true),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/deferred_balances_${dateStr.replaceAll('/', '-')}.pdf');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: ui.TextDirection.rtl,
            child: AlertDialog(
              title: const Text('تقرير المبالغ المتبقية من الفواتير الآجل'),
              content: const Text('تم إنشاء التقرير. ماذا تريد أن تفعل؟'),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('مشاركة'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Share.shareXFiles(
                      [XFile(file.path)],
                      text: 'المبالغ المتبقية من الفواتير الآجل',
                    );
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await OpenFilex.open(file.path);
                  },
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء التقرير: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'المبالغ المتبقية من الفواتير الآجل',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('buying invoices')
              .where('balance', isGreaterThan: 0)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final invoices = snapshot.data!.docs;
            if (invoices.isEmpty) {
              return const Center(child: Text('لا توجد فواتير آجلة متبقية'));
            }

            // Group by supplierName
            final Map<String, double> totals = {};
            for (final inv in invoices) {
              final data = inv.data() as Map<String, dynamic>;
              final supplier = (data['supplierName'] ?? '').toString();
              final balance = (data['balance'] ?? 0.0).toDouble();
              totals[supplier] = (totals[supplier] ?? 0.0) + balance;
            }

            // All entries for grand total and PDF
            final allEntries = totals.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final double grandTotal =
                allEntries.fold(0.0, (s, e) => s + e.value);

            // Filtered entries for display
            final filtered = _search.isEmpty
                ? allEntries
                : allEntries
                    .where((e) =>
                        e.key.toLowerCase().contains(_search.toLowerCase()))
                    .toList();

            return Column(
              children: [
                // Search + تقرير row
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade300,
                              foregroundColor: Colors.black),
                          onPressed: _generating
                              ? null
                              : () => _showReportChoiceDialog(
                                  allEntries, grandTotal),
                          icon: _generating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.picture_as_pdf, size: 18),
                          label: const Text('تقرير'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            hintText: 'بحث',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                          ),
                          onChanged: (v) => setState(() => _search = v),
                        ),
                      ),
                    ],
                  ),
                ),

                // Grand total banner
                Container(
                  color: Colors.orange.shade100,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(grandTotal.toStringAsFixed(2),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.red)),
                      const Text('الإجمالي',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),

                // List
                Expanded(
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = filtered[index];
                      return ListTile(
                        onTap: () =>
                            _navigateToSupplierInvoices(context, e.key),
                        title: Text(
                          e.key,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        trailing: Text(
                          e.value.toStringAsFixed(2),
                          style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                        leading: const Icon(Icons.arrow_back_ios,
                            size: 16, color: Colors.grey),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Remaining Amounts Report ────────────────────────────────────────────────

class _SupplierRemainingReportPage extends StatefulWidget {
  const _SupplierRemainingReportPage();

  @override
  State<_SupplierRemainingReportPage> createState() =>
      _SupplierRemainingReportPageState();
}

class _SupplierRemainingReportPageState
    extends State<_SupplierRemainingReportPage> {
  bool _generating = false;

  Future<void> _generatePdf(
    List<QueryDocumentSnapshot> suppliers,
    Map<String, double> invoiceBalances,
  ) async {
    setState(() => _generating = true);
    try {
      final amiriRegularData = await rootBundle.load('fonts/Amiri-Regular.ttf');
      final amiriBoldData = await rootBundle.load('fonts/Amiri-Bold.ttf');
      final amiriRegular = pw.Font.ttf(amiriRegularData.buffer.asByteData());
      final amiriBold = pw.Font.ttf(amiriBoldData.buffer.asByteData());

      final now = DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy').format(now);
      final timeStr = DateFormat('hh:mm:ss a').format(now);

      // Build rows
      final rows = <Map<String, dynamic>>[];
      for (final doc in suppliers) {
        final name = (doc['name'] ?? '').toString();
        final totalBalance = (doc['totalBalance'] ?? 0.0).toDouble();
        if (totalBalance == 0.0) continue;
        final invBal = invoiceBalances[name] ?? 0.0;
        final openCashBal = totalBalance - invBal;
        rows.add({
          'name': name,
          'invoice': invBal,
          'openCash': openCashBal,
          'total': totalBalance,
        });
      }

      final grandInvoice =
          rows.fold<double>(0.0, (s, r) => s + (r['invoice'] as double));
      final grandOpenCash =
          rows.fold<double>(0.0, (s, r) => s + (r['openCash'] as double));
      final grandTotal =
          rows.fold<double>(0.0, (s, r) => s + (r['total'] as double));

      // Cell style helpers
      pw.TextStyle cell(
              {bool bold = false,
              PdfColor color = PdfColors.black,
              double fontSize = 10}) =>
          pw.TextStyle(
            font: bold ? amiriBold : amiriRegular,
            fontSize: fontSize,
            color: color,
          );

      pw.Widget headerCell(String text) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: pw.Text(
              text,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: cell(bold: true, fontSize: 9),
            ),
          );

      pw.Widget dataCell(String text, {bool red = false, bool bold = false}) =>
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: pw.Text(
              text,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: cell(
                  bold: bold, color: red ? PdfColors.red : PdfColors.black),
            ),
          );

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // ── Header ──
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    // Left: date/time
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Date: $dateStr', style: cell(fontSize: 9)),
                        pw.Text('Time: $timeStr', style: cell(fontSize: 9)),
                      ],
                    ),
                    // Right: brand
                  ],
                ),
                pw.SizedBox(height: 16),
                // ── Title ──
                pw.Center(
                  child: pw.Text(
                    'تقرير بالمتبقي للموردين',
                    textDirection: pw.TextDirection.rtl,
                    style: cell(bold: true, fontSize: 14),
                  ),
                ),
                pw.SizedBox(height: 12),
                // ── Table ──
                pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1), // #
                    1: const pw.FlexColumnWidth(3), // الاسم
                    2: const pw.FlexColumnWidth(3), // الباقي من الفواتير
                    3: const pw.FlexColumnWidth(3), // الباقي من الرصيد
                    4: const pw.FlexColumnWidth(2), // الإجمالي
                  },
                  children: [
                    // Header row
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        headerCell('#'),
                        headerCell('الاسم'),
                        headerCell('الباقي من الفواتير الاجل'),
                        headerCell('الباقي من الرصيد الافتتاحي والنقد'),
                        headerCell('الإجمالي'),
                      ],
                    ),
                    // Data rows
                    for (int i = 0; i < rows.length; i++)
                      pw.TableRow(
                        children: [
                          dataCell('${i + 1}'),
                          dataCell(rows[i]['name'] as String),
                          dataCell((rows[i]['invoice'] as double)
                              .toStringAsFixed(2)),
                          dataCell((rows[i]['openCash'] as double)
                              .toStringAsFixed(2)),
                          dataCell(
                              (rows[i]['total'] as double).toStringAsFixed(2)),
                        ],
                      ),
                    // Totals row
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey100),
                      children: [
                        dataCell(''),
                        dataCell('الإجمالي', bold: true, red: true),
                        dataCell(grandInvoice.toStringAsFixed(2),
                            bold: true, red: true),
                        dataCell(grandOpenCash.toStringAsFixed(2),
                            bold: true, red: true),
                        dataCell(grandTotal.toStringAsFixed(2),
                            bold: true, red: true),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/supplier_remaining_report_$dateStr.pdf'
          .replaceAll('/', '-'));
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'تقرير المبالغ المتبقية للموردين',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء التقرير: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'المبالغ المتبقية للموردين - تقرير',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream:
              FirebaseFirestore.instance.collection('suppliers').snapshots(),
          builder: (context, suppSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('buying invoices')
                  .where('balance', isGreaterThan: 0)
                  .snapshots(),
              builder: (context, invSnap) {
                if (!suppSnap.hasData || !invSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Build invoice balances map by supplierName
                final Map<String, double> invoiceBalances = {};
                for (final doc in invSnap.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final sName = (data['supplierName'] ?? '').toString();
                  final bal = (data['balance'] ?? 0.0).toDouble();
                  invoiceBalances[sName] =
                      (invoiceBalances[sName] ?? 0.0) + bal;
                }

                final suppliers = suppSnap.data!.docs
                    .where((d) => (d['totalBalance'] ?? 0.0) != 0.0)
                    .toList()
                  ..sort((a, b) => (b['totalBalance'] as num)
                      .compareTo(a['totalBalance'] as num));

                if (suppliers.isEmpty) {
                  return const Center(
                      child: Text('لا توجد أرصدة متبقية للموردين'));
                }

                double grandTotal = suppliers.fold(
                    0.0, (s, d) => s + (d['totalBalance'] ?? 0.0).toDouble());

                return Stack(
                  children: [
                    Column(
                      children: [
                        Container(
                          color: Colors.orange.shade100,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(grandTotal.toStringAsFixed(2),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.red)),
                              const Text('الإجمالي',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: suppliers.length,
                            itemBuilder: (context, index) {
                              final doc = suppliers[index];
                              final balance =
                                  (doc['totalBalance'] ?? 0.0).toDouble();
                              return ListTile(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SupplierInvoicesPage(
                                        supplierId: doc.id),
                                  ),
                                ),
                                title: Text(doc['name'] ?? '',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                trailing: Text(
                                  balance.toStringAsFixed(2),
                                  style: TextStyle(
                                    color:
                                        balance > 0 ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_generating)
                      Container(
                        color: Colors.black38,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ─── Suppliers With Balance Report ──────────────────────────────────────────

class _SupplierBalanceReportPage extends StatelessWidget {
  const _SupplierBalanceReportPage();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'الموردين المتبقي عندهم أرصدة',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('suppliers')
              .where('totalBalance', isGreaterThan: 0)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final suppliers = snapshot.data!.docs;
            if (suppliers.isEmpty) {
              return const Center(child: Text('لا يوجد موردين لديهم أرصدة'));
            }
            return ListView.builder(
              itemCount: suppliers.length,
              itemBuilder: (context, index) {
                final doc = suppliers[index];
                final balance = (doc['totalBalance'] ?? 0.0).toDouble();
                return ListTile(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SupplierInvoicesPage(supplierId: doc.id),
                    ),
                  ),
                  title: Text(doc['name'] ?? '',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Text(
                    balance.toStringAsFixed(2),
                    style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ─── Check Supplier Balances ─────────────────────────────────────────────────

class _SupplierBalanceCheckPage extends StatefulWidget {
  const _SupplierBalanceCheckPage();

  @override
  State<_SupplierBalanceCheckPage> createState() =>
      _SupplierBalanceCheckPageState();
}

class _SupplierBalanceCheckPageState extends State<_SupplierBalanceCheckPage> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'فحص ارصدة الموردين',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: TextField(
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  hintText: 'ابحث عن مورد',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('suppliers')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snapshot.data!.docs.where((d) {
                    if (_search.isEmpty) return true;
                    return (d['name'] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(_search.toLowerCase());
                  }).toList();

                  return ListView.builder(
                    itemCount: all.length,
                    itemBuilder: (context, index) {
                      final doc = all[index];
                      final balance = (doc['totalBalance'] ?? 0.0).toDouble();
                      return ListTile(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                SupplierInvoicesPage(supplierId: doc.id),
                          ),
                        ),
                        title: Text(doc['name'] ?? '',
                            textAlign: TextAlign.right,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Text(
                          balance.toStringAsFixed(2),
                          style: TextStyle(
                            color: balance > 0
                                ? Colors.red
                                : balance < 0
                                    ? Colors.orange
                                    : Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
