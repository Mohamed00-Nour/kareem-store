import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../repositories/payment_breakdown_repository.dart';
import '../local_db/models/payment_breakdown_local.dart';

class PaymentsReportPage extends StatefulWidget {
  const PaymentsReportPage({super.key});

  @override
  State<PaymentsReportPage> createState() => _PaymentsReportPageState();
}

class _PaymentsReportPageState extends State<PaymentsReportPage> {
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String _selectedFilter = 'اليوم';

  List<PaymentBreakdownLocal> _entries = [];
  double _totalWallet = 0.0;
  double _totalCash = 0.0;
  double _totalInstapay = 0.0;
  double _totalBankTransfer = 0.0;
  double _grandTotal = 0.0;
  StreamSubscription? _paymentsBoxSubscription;
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    _paymentsBoxSubscription =
        PaymentBreakdownRepository.instance.box.watch().listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 40), () {
        if (mounted) _loadData();
      });
    });
    _applyFilter('اليوم');
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _paymentsBoxSubscription?.cancel();
    super.dispose();
  }

  void _applyFilter(String filter) {
    final now = DateTime.now();
    setState(() {
      _selectedFilter = filter;
      if (filter == 'اليوم') {
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day);
      } else if (filter == 'الأسبوع') {
        _startDate = now.subtract(const Duration(days: 7));
        _endDate = now;
      } else if (filter == 'الشهر') {
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = now;
      } else if (filter == 'الكل') {
        _startDate = DateTime(2020, 1, 1);
        _endDate = DateTime(2099, 12, 31);
      }
    });
    _loadData();
  }

  void _loadData() {
    if (!mounted) return;
    final list = PaymentBreakdownRepository.instance
        .getByDateRange(_startDate, _endDate)
      ..sort((a, b) {
        final dateOrder = b.date.compareTo(a.date);
        return dateOrder != 0 ? dateOrder : b.timestamp.compareTo(a.timestamp);
      });

    double w = 0.0, c = 0.0, i = 0.0, b = 0.0;
    for (final item in list) {
      w += item.wallet;
      c += item.cash;
      i += item.instapay;
      b += item.bankTransfer;
    }

    setState(() {
      _entries = list;
      _totalWallet = w;
      _totalCash = c;
      _totalInstapay = i;
      _totalBankTransfer = b;
      _grandTotal = w + c + i + b;
    });
  }

  Future<void> _pickCustomDateRange() async {
    final firstDate = DateTime(2020, 1, 1);
    final lastDate = DateTime(2099, 12, 31);

    DateTime start = _startDate.isBefore(firstDate)
        ? firstDate
        : (_startDate.isAfter(lastDate) ? lastDate : _startDate);
    DateTime end = _endDate.isBefore(firstDate)
        ? firstDate
        : (_endDate.isAfter(lastDate) ? lastDate : _endDate);

    if (start.isAfter(end)) {
      start = end;
    }

    final range = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: DateTimeRange(start: start, end: end),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.orange.shade800,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (range != null) {
      setState(() {
        _selectedFilter = 'مخصص';
        _startDate = range.start;
        _endDate = range.end;
      });
      _loadData();
    }
  }

  Future<void> _editEntry(PaymentBreakdownLocal entry) async {
    final clientCtrl = TextEditingController(text: entry.clientName);
    final walletCtrl = TextEditingController(
        text: entry.wallet > 0 ? entry.wallet.toStringAsFixed(2) : '');
    final cashCtrl = TextEditingController(
        text: entry.cash > 0 ? entry.cash.toStringAsFixed(2) : '');
    final instapayCtrl = TextEditingController(
        text: entry.instapay > 0 ? entry.instapay.toStringAsFixed(2) : '');
    final bankCtrl = TextEditingController(
        text: entry.bankTransfer > 0
            ? entry.bankTransfer.toStringAsFixed(2)
            : '');
    final notesCtrl = TextEditingController(text: entry.notes);

    double? parseAmount(TextEditingController controller) {
      final text = controller.text.trim();
      if (text.isEmpty) return 0.0;
      final value = double.tryParse(text.replaceAll(',', '.'));
      return value != null && value >= 0 ? value : null;
    }

    final updated = await showDialog<PaymentBreakdownLocal>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget amountField(
              String label,
              TextEditingController controller,
              Color color,
            ) {
              return TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  labelText: label,
                  labelStyle: TextStyle(color: color),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              );
            }

            return Directionality(
              textDirection: ui.TextDirection.rtl,
              child: AlertDialog(
                title: const Text('تعديل تفاصيل المدفوعات'),
                content: SingleChildScrollView(
                  child: SizedBox(
                    width: 420.w,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: clientCtrl,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            labelText: 'اسم العميل',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        SizedBox(height: 12.h),
                        Row(
                          children: [
                            Expanded(
                              child: amountField(
                                  'محفظة', walletCtrl, Colors.orange.shade800),
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: amountField(
                                  'نقدي', cashCtrl, Colors.green.shade800),
                            ),
                          ],
                        ),
                        SizedBox(height: 10.h),
                        Row(
                          children: [
                            Expanded(
                              child: amountField('أنستاباي', instapayCtrl,
                                  Colors.purple.shade800),
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: amountField(
                                  'تحويل بنكي', bankCtrl, Colors.blue.shade800),
                            ),
                          ],
                        ),
                        SizedBox(height: 10.h),
                        TextField(
                          controller: notesCtrl,
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظات',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        if (error != null) ...[
                          SizedBox(height: 8.h),
                          Text(error!,
                              style: const TextStyle(color: Colors.red)),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final wallet = parseAmount(walletCtrl);
                      final cash = parseAmount(cashCtrl);
                      final instapay = parseAmount(instapayCtrl);
                      final bankTransfer = parseAmount(bankCtrl);
                      if (clientCtrl.text.trim().isEmpty) {
                        setDialogState(() => error = 'يرجى إدخال اسم العميل');
                        return;
                      }
                      if (wallet == null ||
                          cash == null ||
                          instapay == null ||
                          bankTransfer == null) {
                        setDialogState(() => error = 'يوجد مبلغ غير صحيح');
                        return;
                      }
                      if (wallet + cash + instapay + bankTransfer <= 0) {
                        setDialogState(() =>
                            error = 'أدخل مبلغاً في طريقة دفع واحدة على الأقل');
                        return;
                      }
                      Navigator.pop(
                        dialogContext,
                        PaymentBreakdownLocal(
                          id: entry.id,
                          date: entry.date,
                          wallet: wallet,
                          cash: cash,
                          instapay: instapay,
                          bankTransfer: bankTransfer,
                          notes: notesCtrl.text.trim(),
                          timestamp: DateTime.now(),
                          invoiceId: entry.invoiceId,
                          invoiceNumber: entry.invoiceNumber,
                          clientName: clientCtrl.text.trim(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    clientCtrl.dispose();
    walletCtrl.dispose();
    cashCtrl.dispose();
    instapayCtrl.dispose();
    bankCtrl.dispose();
    notesCtrl.dispose();

    if (updated == null) return;
    await PaymentBreakdownRepository.instance.updateBreakdown(updated);
    if (!mounted) return;
    _loadData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تعديل تفاصيل المدفوعات')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('hh:mm a');

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xffeeeced),
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: Text(
            'تقرير المدفوعات',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Column(
          children: [
            // ── Filter Chips Bar ──
            Container(
              padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
              color: Colors.white,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('اليوم'),
                    SizedBox(width: 8.w),
                    _buildFilterChip('الأسبوع'),
                    SizedBox(width: 8.w),
                    _buildFilterChip('الشهر'),
                    SizedBox(width: 8.w),
                    _buildFilterChip('الكل'),
                    SizedBox(width: 8.w),
                    ActionChip(
                      avatar: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        _selectedFilter == 'مخصص'
                            ? '${dateFormat.format(_startDate)} ➔ ${dateFormat.format(_endDate)}'
                            : 'تاريخ مخصص',
                        style: TextStyle(fontSize: 12.sp),
                      ),
                      backgroundColor: _selectedFilter == 'مخصص'
                          ? Colors.orange.shade100
                          : Colors.grey.shade200,
                      onPressed: _pickCustomDateRange,
                    ),
                  ],
                ),
              ),
            ),

            // ── Summary Cards Section ──
            Padding(
              padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 6.h),
              child: Column(
                children: [
                  // Top row: Wallet, Cash, Instapay, Bank Transfer
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 10.w,
                    mainAxisSpacing: 10.h,
                    childAspectRatio: 2.3,
                    children: [
                      _buildSummaryCard(
                        title: 'محفظة',
                        amount: _totalWallet,
                        color: Colors.orange.shade700,
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                      _buildSummaryCard(
                        title: 'نقدي',
                        amount: _totalCash,
                        color: Colors.green.shade700,
                        icon: Icons.payments_outlined,
                      ),
                      _buildSummaryCard(
                        title: 'أنستاباي',
                        amount: _totalInstapay,
                        color: Colors.purple.shade700,
                        icon: Icons.flash_on_outlined,
                      ),
                      _buildSummaryCard(
                        title: 'تحويل بنكي',
                        amount: _totalBankTransfer,
                        color: Colors.blue.shade700,
                        icon: Icons.account_balance_outlined,
                      ),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  // Grand Total Banner
                  Container(
                    width: double.infinity,
                    padding:
                        EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.orange.shade800,
                          Colors.orange.shade600
                        ],
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                      ),
                      borderRadius: BorderRadius.circular(12.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.monetization_on_outlined,
                                color: Colors.white, size: 24.sp),
                            SizedBox(width: 8.w),
                            Text(
                              'إجمالي المدفوعات',
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${_grandTotal.toStringAsFixed(2)} ج.م',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Entries List ──
            Expanded(
              child: _entries.isEmpty
                  ? Center(
                      child: Text(
                        'لا توجد عمليات مدفوعات مسجلة لهذه الفترة',
                        style: TextStyle(
                            fontSize: 14.sp, color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.builder(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        final total = entry.wallet +
                            entry.cash +
                            entry.instapay +
                            entry.bankTransfer;

                        return Card(
                          margin: EdgeInsets.only(bottom: 8.h),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.r)),
                          child: Padding(
                            padding: EdgeInsets.all(12.w),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${dateFormat.format(entry.date)}  •  ${timeFormat.format(entry.date)}',
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${total.toStringAsFixed(2)} ج.م',
                                          style: TextStyle(
                                            fontSize: 15.sp,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange.shade800,
                                          ),
                                        ),
                                        SizedBox(width: 4.w),
                                        IconButton(
                                          tooltip: 'تعديل',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => _editEntry(entry),
                                          icon: Icon(Icons.edit_outlined,
                                              color: Colors.grey.shade700,
                                              size: 20.sp),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4.h),
                                Row(
                                  children: [
                                    Icon(Icons.person_outline,
                                        size: 17.sp,
                                        color: Colors.orange.shade800),
                                    SizedBox(width: 5.w),
                                    Expanded(
                                      child: Text(
                                        entry.clientName.trim().isNotEmpty
                                            ? entry.clientName
                                            : 'غير مرتبط بعميل',
                                        style: TextStyle(
                                          fontSize: 13.sp,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              entry.clientName.trim().isNotEmpty
                                                  ? Colors.black87
                                                  : Colors.grey.shade600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (entry.invoiceNumber.isNotEmpty)
                                      Text(
                                        'فاتورة #${entry.invoiceNumber}',
                                        style: TextStyle(
                                          fontSize: 11.sp,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                                if (entry.notes.isNotEmpty) ...[
                                  SizedBox(height: 4.h),
                                  Text(
                                    entry.notes,
                                    style: TextStyle(
                                        fontSize: 12.sp,
                                        color: Colors.grey.shade600),
                                  ),
                                ],
                                SizedBox(height: 8.h),
                                Wrap(
                                  spacing: 6.w,
                                  runSpacing: 6.h,
                                  children: [
                                    if (entry.wallet > 0)
                                      _buildChannelBadge(
                                          'محفظة', entry.wallet, Colors.orange),
                                    if (entry.cash > 0)
                                      _buildChannelBadge(
                                          'نقدي', entry.cash, Colors.green),
                                    if (entry.instapay > 0)
                                      _buildChannelBadge('أنستاباي',
                                          entry.instapay, Colors.purple),
                                    if (entry.bankTransfer > 0)
                                      _buildChannelBadge('تحويل بنكي',
                                          entry.bankTransfer, Colors.blue),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: Colors.orange.shade800,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12.sp,
      ),
      onSelected: (_) => _applyFilter(label),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6.w),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20.sp),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  '${amount.toStringAsFixed(2)} ج.م',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelBadge(String label, double amount, MaterialColor color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        '$label: ${amount.toStringAsFixed(2)} ج.م',
        style: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.bold,
          color: color.shade800,
        ),
      ),
    );
  }
}
