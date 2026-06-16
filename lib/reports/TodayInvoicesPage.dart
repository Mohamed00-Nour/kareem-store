import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../Widgets/app_responsive.dart';
import '../Screeens/Invoices/InvoiceDetailPage.dart';
import '../Services/daily_invoices_pdf_service.dart';
import '../Services/invoice_print_service.dart';
import '../Services/invoice_print_ui.dart';
import '../Services/sales_invoices_fetch_service.dart';
import '../Widgets/date_range_selector.dart';
import '../Widgets/sales_invoice_card.dart';

class TodayInvoicesPage extends StatefulWidget {
  const TodayInvoicesPage({super.key});

  @override
  State<TodayInvoicesPage> createState() => _TodayInvoicesPageState();
}

class _TodayInvoicesPageState extends State<TodayInvoicesPage> {
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = true;
  bool _exportingPdf = false;
  bool _printingAll = false;
  List<Map<String, dynamic>> _invoices = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = _startDate;
    _loadInvoices();
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: dateRangePickerTheme,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _resetToToday() {
    final now = DateTime.now();
    setState(() {
      _startDate = DateTime(now.year, now.month, now.day);
      _endDate = _startDate;
    });
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    if (_startDate == null || _endDate == null) return;
    setState(() => _loading = true);
    try {
      final invoices = await SalesInvoicesFetchService.fetchByDateRange(
        start: _startDate!,
        end: _endDate!,
      );
      SalesInvoicesFetchService.sortNewestFirst(invoices);
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    }
  }

  DateTime get _rangeStart =>
      DateTime(_startDate!.year, _startDate!.month, _startDate!.day);

  DateTime get _rangeEnd =>
      DateTime(_endDate!.year, _endDate!.month, _endDate!.day);

  bool get _isTodayOnly {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _rangeStart == today && _rangeEnd == today;
  }

  String get _periodLabel {
    if (_isTodayOnly) {
      return '${_rangeStart.day}/${_rangeStart.month}/${_rangeStart.year}';
    }
    if (_rangeStart == _rangeEnd) {
      return '${_rangeStart.day}/${_rangeStart.month}/${_rangeStart.year}';
    }
    return '${_rangeStart.day}/${_rangeStart.month}/${_rangeStart.year}'
        ' — ${_rangeEnd.day}/${_rangeEnd.month}/${_rangeEnd.year}';
  }

  Future<void> _openInvoiceDetails(Map<String, dynamic> invoice) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceDetailPage(invoice: invoice),
      ),
    );
    if (changed == true) {
      _loadInvoices();
    }
  }

  Future<void> _printSingle(Map<String, dynamic> invoice) async {
    final clientName = invoice['clientName']?.toString();
    await InvoicePrintUi.printInvoice(
      context,
      invoice,
      clientId: clientName,
    );
  }

  Future<void> _showPdfActionsDialog(File file, String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: Directionality.of(context),
        child: AlertDialog(
          title: const Text('تصدير PDF'),
          content: Text(message),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('مشاركة'),
              onPressed: () async {
                Navigator.pop(ctx);
                await Share.shareXFiles([XFile(file.path)]);
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('فتح'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87,
                foregroundColor: Colors.white,
              ),
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

  Future<void> _exportSinglePdf(Map<String, dynamic> invoice) async {
    final invoiceNumber = invoice['invoiceNumber']?.toString() ?? '';
    try {
      final date = SalesInvoicesFetchService.invoiceDate(invoice);
      final day = date != null
          ? DateTime(date.year, date.month, date.day)
          : _rangeStart;
      final file = await DailyInvoicesPdfService.generate(
        invoices: [invoice],
        from: day,
        to: day,
      );
      if (!mounted) return;
      await _showPdfActionsDialog(
        file,
        'تم إنشاء PDF لفاتورة #$invoiceNumber',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التصدير: $e')),
        );
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_invoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد فواتير للتصدير')),
      );
      return;
    }

    setState(() => _exportingPdf = true);
    try {
      final file = await DailyInvoicesPdfService.generate(
        invoices: _invoices,
        from: _rangeStart,
        to: _rangeEnd,
      );

      if (!mounted) return;
      await _showPdfActionsDialog(
        file,
        'تم إنشاء ملف PDF (${_invoices.length} فاتورة — صفحة لكل فاتورة)',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التصدير: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _printAllInvoices() async {
    if (_invoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد فواتير للطباعة')),
      );
      return;
    }

    setState(() => _printingAll = true);
    if (!mounted) return;

    BuildContext? loadingDialogContext;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        loadingDialogContext = dialogCtx;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xffead1ac),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.orange),
                SizedBox(height: 16.h),
                Text(
                  'جاري طباعة الفواتير...',
                  style:
                      TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      },
    );

    var printed = 0;
    String? failMessage;
    for (final invoice in _invoices) {
      final clientName = invoice['clientName']?.toString();
      final result = await InvoicePrintService.printSalesInvoice(
        invoice,
        clientId: clientName,
      );
      if (result.success) {
        printed++;
      } else {
        failMessage = result.messageAr.isNotEmpty
            ? result.messageAr
            : 'فشلت طباعة فاتورة #${invoice['invoiceNumber']}';
        break;
      }
    }

    final loadingCtx = loadingDialogContext;
    if (loadingCtx != null && loadingCtx.mounted) {
      Navigator.of(loadingCtx).pop();
    }
    if (!mounted) return;
    setState(() => _printingAll = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(failMessage != null
            ? '$failMessage (تمت طباعة $printed من ${_invoices.length})'
            : 'تمت طباعة $printed فاتورة'),
        duration: Duration(seconds: failMessage != null ? 8 : 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xffeeeced),
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: Text(
            _isTodayOnly ? 'فواتير اليوم' : 'فواتير المبيعات',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            if (_invoices.isNotEmpty) ...[
              IconButton(
                icon: _exportingPdf
                    ? SizedBox(
                        width: 22.w,
                        height: 22.h,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf, color: Colors.white),
                tooltip: 'تصدير PDF للفترة',
                onPressed: _exportingPdf || _printingAll ? null : _exportPdf,
              ),
              IconButton(
                icon: const Icon(Icons.print, color: Colors.white),
                tooltip: 'طباعة الكل',
                onPressed: _exportingPdf || _printingAll ? null : _printAllInvoices,
              ),
            ],
          ],
        ),
        body: RefreshIndicator(
          color: Colors.orange,
          onRefresh: _loadInvoices,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DateRangeSelector(
                        startDate: _startDate,
                        endDate: _endDate,
                        onPickStart: () => _pickDate(true),
                        onPickEnd: () => _pickDate(false),
                      ),
                      SizedBox(height: 10.h),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _loading ? null : _resetToToday,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange.shade800,
                                side: BorderSide(color: Colors.orange.shade700),
                                padding: EdgeInsets.symmetric(vertical: 10.h),
                              ),
                              child: Text('اليوم',
                                  style: TextStyle(
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.withOpacity(0.85),
                                foregroundColor: Colors.black.withOpacity(0.8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r)),
                                padding: EdgeInsets.symmetric(vertical: 10.h),
                              ),
                              onPressed: (_startDate != null &&
                                      _endDate != null &&
                                      !_loading)
                                  ? _loadInvoices
                                  : null,
                              child: _loading
                                  ? SizedBox(
                                      width: 18.w,
                                      height: 18.h,
                                      child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black54),
                                    )
                                  : Text('عرض',
                                      style: TextStyle(
                                          fontSize: 14.sp,
                                          fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10.h),
                      Text(
                        _isTodayOnly
                            ? 'اليوم — $_periodLabel — ${_invoices.length} فاتورة'
                            : 'الفترة — $_periodLabel — ${_invoices.length} فاتورة',
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                      child: CircularProgressIndicator(color: Colors.orange)),
                )
              else if (_invoices.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      _isTodayOnly
                          ? 'لا توجد فواتير اليوم'
                          : 'لا توجد فواتير في هذه الفترة',
                      style: TextStyle(
                        fontSize: 15.sp,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: AppResponsive.gridColumns(context),
                      crossAxisSpacing: 10.w,
                      mainAxisSpacing: 10.h,
                      childAspectRatio: 0.72,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final invoice = _invoices[index];
                        return SalesInvoiceCard(
                          invoice: invoice,
                          onTap: () => _openInvoiceDetails(invoice),
                          onPrint: () => _printSingle(invoice),
                          onExportPdf: () => _exportSinglePdf(invoice),
                        );
                      },
                      childCount: _invoices.length,
                    ),
                  ),
                ),
              SliverToBoxAdapter(child: SizedBox(height: 16.h)),
            ],
          ),
        ),
      ),
    );
  }
}
