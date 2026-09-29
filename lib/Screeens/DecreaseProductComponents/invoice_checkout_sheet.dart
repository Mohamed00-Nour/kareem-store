import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../Services/invoice_number_utils.dart';

class CheckoutSelectionResult {
  final String clientName;
  final double paidAmount;
  final String paymentMethod;
  final String notes;
  final double invoiceDiscount;
  final bool discountIsPercent;
  final double walletAmount;
  final double cashAmount;
  final double instapayAmount;
  final double bankTransferAmount;

  CheckoutSelectionResult({
    required this.clientName,
    required this.paidAmount,
    required this.paymentMethod,
    required this.notes,
    required this.invoiceDiscount,
    required this.discountIsPercent,
    this.walletAmount = 0.0,
    this.cashAmount = 0.0,
    this.instapayAmount = 0.0,
    this.bankTransferAmount = 0.0,
  });
}

String? validateInvoiceCheckoutPayment({
  required double paidAmount,
  required double invoiceTotal,
  required String paymentMethod,
  required bool isReturnInvoice,
}) {
  const tolerance = 0.001;
  final isCash = paymentMethod == 'نقداً';
  final isDeferredSale = !isReturnInvoice && paymentMethod == 'آجل';

  if (paidAmount < -tolerance) {
    return 'المبلغ المدفوع لا يمكن أن يكون سالب';
  }

  if (isReturnInvoice) {
    if (paidAmount - invoiceTotal > tolerance) {
      return 'المبلغ المدفوع أكبر من الإجمالي';
    }
    if (isCash && paidAmount + tolerance < invoiceTotal) {
      return 'المبلغ المدفوع أصغر من الإجمالي';
    }
    return null;
  }

  if (paidAmount + tolerance < invoiceTotal && !isDeferredSale) {
    return 'المبلغ المدفوع أصغر من الإجمالي، اختر آجل للحفظ';
  }
  if (paidAmount - invoiceTotal > tolerance && !isCash && !isDeferredSale) {
    return 'المبلغ المدفوع أكبر من الإجمالي، اختر نقداً أو آجل للحفظ';
  }
  return null;
}

Future<CheckoutSelectionResult?> showInvoiceCheckoutSheet({
  required BuildContext context,
  required bool isEditing,
  required String paymentMethod,
  required double invoiceDiscount,
  required String clientName,
  required double clientBalance,
  required String notes,
  required double originalPaidAmount,
  required double totalSum,
  required List<String> clients,
  required bool isReturnInvoice,
  required bool isQuote,
  required bool isSaving,
  required Future<bool> Function(String) clientExists,
  required Future<double> Function(String) fetchClientBalance,
  double initialWalletAmount = 0.0,
  double initialCashAmount = 0.0,
  double initialInstapayAmount = 0.0,
  double initialBankTransferAmount = 0.0,
}) {
  return showModalBottomSheet<CheckoutSelectionResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
    builder: (ctx) {
      return _InvoiceCheckoutSheetContent(
        isEditing: isEditing,
        paymentMethod: paymentMethod,
        invoiceDiscount: invoiceDiscount,
        clientName: clientName,
        clientBalance: clientBalance,
        notes: notes,
        originalPaidAmount: originalPaidAmount,
        totalSum: totalSum,
        clients: clients,
        isReturnInvoice: isReturnInvoice,
        isQuote: isQuote,
        isSaving: isSaving,
        clientExists: clientExists,
        fetchClientBalance: fetchClientBalance,
        initialWalletAmount: initialWalletAmount,
        initialCashAmount: initialCashAmount,
        initialInstapayAmount: initialInstapayAmount,
        initialBankTransferAmount: initialBankTransferAmount,
      );
    },
  );
}

class _InvoiceCheckoutSheetContent extends StatefulWidget {
  final bool isEditing;
  final String paymentMethod;
  final double invoiceDiscount;
  final String clientName;
  final double clientBalance;
  final String notes;
  final double originalPaidAmount;
  final double totalSum;
  final List<String> clients;
  final bool isReturnInvoice;
  final bool isQuote;
  final bool isSaving;
  final Future<bool> Function(String) clientExists;
  final Future<double> Function(String) fetchClientBalance;
  final double initialWalletAmount;
  final double initialCashAmount;
  final double initialInstapayAmount;
  final double initialBankTransferAmount;

  const _InvoiceCheckoutSheetContent({
    required this.isEditing,
    required this.paymentMethod,
    required this.invoiceDiscount,
    required this.clientName,
    required this.clientBalance,
    required this.notes,
    required this.originalPaidAmount,
    required this.totalSum,
    required this.clients,
    required this.isReturnInvoice,
    required this.isQuote,
    required this.isSaving,
    required this.clientExists,
    required this.fetchClientBalance,
    required this.initialWalletAmount,
    required this.initialCashAmount,
    required this.initialInstapayAmount,
    required this.initialBankTransferAmount,
  });

  @override
  State<_InvoiceCheckoutSheetContent> createState() =>
      _InvoiceCheckoutSheetContentState();
}

class _InvoiceCheckoutSheetContentState
    extends State<_InvoiceCheckoutSheetContent> {
  late String paymentMethod;
  late double invoiceDiscount;
  late bool discountIsPercent;
  late String checkoutClient;
  late String notes;
  double? checkoutClientBalance;
  bool loadingCheckoutClientBalance = false;
  bool checkoutClientNotFound = false;
  late String lastManualPaid;
  late TextEditingController paidCtrl;
  late TextEditingController discountCtrl;
  late TextEditingController notesCtrl;
  late TextEditingController walletCtrl;
  late TextEditingController cashCtrl;
  late TextEditingController instapayCtrl;
  late TextEditingController bankTransferCtrl;

  @override
  void initState() {
    super.initState();
    paymentMethod = widget.isEditing ? widget.paymentMethod : 'نقداً';
    invoiceDiscount = widget.isEditing ? widget.invoiceDiscount : 0.0;
    discountIsPercent = !widget.isEditing;
    checkoutClient = widget.clientName;
    notes = widget.isEditing ? widget.notes : '';
    checkoutClientBalance = checkoutClient.trim().isNotEmpty &&
            checkoutClient.trim() == widget.clientName.trim()
        ? widget.clientBalance
        : null;

    paidCtrl = TextEditingController(
        text: widget.isEditing && widget.originalPaidAmount > 0
            ? widget.originalPaidAmount.toStringAsFixed(2)
            : '');
    discountCtrl = TextEditingController(
        text: widget.isEditing && widget.invoiceDiscount > 0
            ? widget.invoiceDiscount.toStringAsFixed(2)
            : '');
    notesCtrl = TextEditingController(text: notes);
    String initialBreakdownText(double value) =>
        value > 0 ? value.toStringAsFixed(2) : '';
    walletCtrl = TextEditingController(
        text: initialBreakdownText(widget.initialWalletAmount));
    cashCtrl = TextEditingController(
        text: initialBreakdownText(widget.initialCashAmount));
    instapayCtrl = TextEditingController(
        text: initialBreakdownText(widget.initialInstapayAmount));
    bankTransferCtrl = TextEditingController(
        text: initialBreakdownText(widget.initialBankTransferAmount));
    lastManualPaid = widget.isEditing && widget.originalPaidAmount > 0
        ? widget.originalPaidAmount.toStringAsFixed(2)
        : '';
  }

  @override
  void dispose() {
    paidCtrl.dispose();
    discountCtrl.dispose();
    notesCtrl.dispose();
    walletCtrl.dispose();
    cashCtrl.dispose();
    instapayCtrl.dispose();
    bankTransferCtrl.dispose();
    super.dispose();
  }

  void _selectAllField(TextEditingController controller) {
    final text = controller.text;
    if (text.isEmpty) return;
    controller.selection =
        TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  String invoiceAmount(double amount) => amount.toStringAsFixed(2);

  double? _parseBreakdownAmount(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return 0.0;
    final value = invoiceTryParseAmount(text);
    if (value == null || value < -0.001) return null;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        return StatefulBuilder(builder: (context, setSheet) {
          Future<void> loadCheckoutClientBalance(String clientName) async {
            if (clientName.trim().isEmpty) {
              setSheet(() {
                checkoutClientBalance = null;
                loadingCheckoutClientBalance = false;
                checkoutClientNotFound = false;
              });
              return;
            }
            setSheet(() {
              loadingCheckoutClientBalance = true;
              checkoutClientBalance = null;
              checkoutClientNotFound = false;
            });
            final name = clientName.trim();
            final exists = await widget.clientExists(name);
            final bal = exists ? await widget.fetchClientBalance(name) : 0.0;
            setSheet(() {
              checkoutClientNotFound = !exists;
              checkoutClientBalance = exists ? bal : null;
              loadingCheckoutClientBalance = false;
            });
          }

          if (checkoutClient.trim().isNotEmpty &&
              checkoutClientBalance == null &&
              !loadingCheckoutClientBalance) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadCheckoutClientBalance(checkoutClient);
            });
          }

          double totalSum = widget.totalSum;
          double effectiveDiscountAmt = discountIsPercent
              ? totalSum * invoiceDiscount / 100
              : invoiceDiscount;
          double totalAfterDiscount = totalSum - effectiveDiscountAmt;
          double paid = invoiceTryParseAmount(paidCtrl.text) ?? 0.0;
          double remaining = paid - totalAfterDiscount;
          final bool isCash = paymentMethod == 'نقداً';
          final paymentValidationMessage = validateInvoiceCheckoutPayment(
            paidAmount: paid,
            invoiceTotal: totalAfterDiscount,
            paymentMethod: paymentMethod,
            isReturnInvoice: widget.isReturnInvoice,
          );
          final breakdownAmounts = [
            _parseBreakdownAmount(walletCtrl),
            _parseBreakdownAmount(cashCtrl),
            _parseBreakdownAmount(instapayCtrl),
            _parseBreakdownAmount(bankTransferCtrl),
          ];
          final hasInvalidBreakdown =
              breakdownAmounts.any((amount) => amount == null);
          final breakdownTotal = breakdownAmounts.whereType<double>().fold(
                0.0,
                (total, amount) => total + amount,
              );

          void syncPaidForPaymentMethod() {
            if (paymentMethod == 'نقداً') {
              paidCtrl.text = '';
            } else {
              paidCtrl.text = lastManualPaid;
            }
          }

          Widget paymentBreakdownField({
            required Key fieldKey,
            required TextEditingController controller,
            required String label,
            required IconData icon,
            required Color color,
          }) {
            final valueIsInvalid = _parseBreakdownAmount(controller) == null;
            return TextField(
              key: fieldKey,
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              onTap: () => _selectAllField(controller),
              onChanged: (_) => setSheet(() {}),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(
                  fontSize: 12.sp,
                  color: valueIsInvalid ? Colors.red.shade700 : color,
                  fontWeight: FontWeight.w600,
                ),
                hintText: '0.00',
                hintStyle: TextStyle(fontSize: 12.sp, color: Colors.grey),
                prefixIcon: Icon(
                  valueIsInvalid ? Icons.error_outline : icon,
                  color: valueIsInvalid ? Colors.red.shade700 : color,
                  size: 20.sp,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.r),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.r),
                  borderSide: BorderSide(
                    color: valueIsInvalid
                        ? Colors.red.shade400
                        : Colors.grey.shade300,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.r),
                  borderSide: BorderSide(
                    color: valueIsInvalid ? Colors.red.shade700 : color,
                    width: 1.5,
                  ),
                ),
                contentPadding:
                    EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
              ),
            );
          }

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16.w,
                right: 16.w,
                top: 16.h,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'طريقة الدفع',
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(height: 6.h),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6.w,
                      runSpacing: 6.h,
                      children: ['نقداً', 'آجل', 'بطاقه', 'ش']
                          .map(
                            (method) => ChoiceChip(
                              label: Text(
                                method,
                                style: TextStyle(fontSize: 11.sp),
                              ),
                              selected: paymentMethod == method,
                              selectedColor: Colors.green.shade100,
                              checkmarkColor: Colors.green.shade800,
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) => setSheet(() {
                                paymentMethod = method;
                                syncPaidForPaymentMethod();
                              }),
                            ),
                          )
                          .toList(),
                    ),
                    SizedBox(height: 10.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('الإجمالي',
                            style: TextStyle(
                                fontSize: 13.sp, fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Container(
                            margin: EdgeInsets.only(right: 12.w),
                            padding: EdgeInsets.symmetric(
                                vertical: 10.h, horizontal: 12.w),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Text(
                              totalAfterDiscount.toStringAsFixed(2),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('المدفوع',
                            style: TextStyle(
                                fontSize: 13.sp, fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Row(children: [
                            SizedBox(width: 12.w),
                            Expanded(
                              child: TextField(
                                key: const Key('invoice-paid-amount-field'),
                                controller: paidCtrl,
                                textAlign: TextAlign.center,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                style: TextStyle(fontSize: 16.sp),
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8.r)),
                                  contentPadding: EdgeInsets.symmetric(
                                      vertical: 10.h, horizontal: 8.w),
                                  suffixIcon: isCash && paid == 0
                                      ? Icon(Icons.warning_amber_rounded,
                                          color: Colors.red, size: 20.sp)
                                      : null,
                                ),
                                onTap: () => _selectAllField(paidCtrl),
                                onChanged: (v) {
                                  lastManualPaid = v;
                                  setSheet(() {});
                                },
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ),
                    if (paymentValidationMessage != null)
                      Padding(
                        padding: EdgeInsets.only(top: 6.h),
                        child: Text(
                          paymentValidationMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    SizedBox(height: 8.h),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'الباقي',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 6.h),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  vertical: 10.h,
                                  horizontal: 10.w,
                                ),
                                decoration: BoxDecoration(
                                  color: remaining >= 0
                                      ? Colors.green.shade50
                                      : Colors.red.shade50,
                                  border: Border.all(
                                    color: remaining >= 0
                                        ? Colors.green.shade300
                                        : Colors.red.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8.r),
                                ),
                                child: Text(
                                  remaining.toStringAsFixed(1),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.bold,
                                    color: remaining >= 0
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'الخصم',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8.r),
                                    onTap: () => setSheet(() {
                                      discountIsPercent = !discountIsPercent;
                                    }),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8.w,
                                        vertical: 3.h,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade100,
                                        borderRadius:
                                            BorderRadius.circular(8.r),
                                      ),
                                      child: Text(
                                        discountIsPercent ? '%' : 'ج.م',
                                        style: TextStyle(
                                          fontSize: 11.sp,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 6.h),
                              TextField(
                                controller: discountCtrl,
                                textAlign: TextAlign.center,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  suffixText: discountIsPercent ? '%' : 'ج.م',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 8.h,
                                    horizontal: 6.w,
                                  ),
                                ),
                                onTap: () => _selectAllField(discountCtrl),
                                onChanged: (v) => setSheet(() {
                                  invoiceDiscount = double.tryParse(v) ?? 0.0;
                                }),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 14.h),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('حفظ الفاتورة لحساب عميل',
                          style: TextStyle(
                              fontSize: 13.sp, fontWeight: FontWeight.bold)),
                    ),
                    SizedBox(height: 8.h),
                    Row(children: [
                      Icon(Icons.barcode_reader,
                          size: 38.sp, color: Colors.black87),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Autocomplete<String>(
                          initialValue: TextEditingValue(text: checkoutClient),
                          optionsBuilder: (val) {
                            if (val.text.isEmpty)
                              return const Iterable<String>.empty();
                            return widget.clients.where((c) => c
                                .toLowerCase()
                                .contains(val.text.toLowerCase()));
                          },
                          fieldViewBuilder: (context2, ctrl2, focus, onSubmit) {
                            return TextField(
                              controller: ctrl2,
                              focusNode: focus,
                              textAlign: TextAlign.right,
                              onTap: () => _selectAllField(ctrl2),
                              onChanged: (v) {
                                checkoutClient = v;
                                setSheet(() {
                                  checkoutClientBalance = null;
                                  loadingCheckoutClientBalance = false;
                                  checkoutClientNotFound = false;
                                });
                                if (v.trim().isNotEmpty) {
                                  loadCheckoutClientBalance(v);
                                }
                              },
                              decoration: InputDecoration(
                                hintText: 'ابحث عن عميل أو اكتب اسم',
                                hintStyle: TextStyle(fontSize: 12.sp),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.r)),
                                contentPadding: EdgeInsets.symmetric(
                                    vertical: 10.h, horizontal: 12.w),
                                suffixIcon: checkoutClient.isEmpty
                                    ? Icon(Icons.warning_amber_rounded,
                                        color: Colors.red, size: 20.sp)
                                    : null,
                              ),
                            );
                          },
                          onSelected: (c) {
                            checkoutClient = c;
                            setSheet(() => checkoutClientNotFound = false);
                            loadCheckoutClientBalance(c);
                          },
                        ),
                      ),
                    ]),
                    if (checkoutClientNotFound) ...[
                      SizedBox(height: 8.h),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10.r),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Text(
                          'هذا العميل غير موجود',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                    if (checkoutClient.trim().isNotEmpty &&
                        !checkoutClientNotFound) ...[
                      SizedBox(height: 10.h),
                      Builder(
                        builder: (_) {
                          final balanceBefore = checkoutClientBalance ?? 0.0;
                          final invoiceUnpaid = totalAfterDiscount - paid;
                          final balanceAfter = widget.isReturnInvoice
                              ? balanceBefore - invoiceUnpaid
                              : balanceBefore + invoiceUnpaid;
                          final afterLabel = widget.isReturnInvoice
                              ? 'الرصيد بعد المرتجع (المتبقي عليكم)'
                              : 'الرصيد بعد الفاتورة (المتبقي عليكم)';
                          TextStyle balanceStyle(double amount) => TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold,
                                color: amount > 0
                                    ? Colors.red.shade700
                                    : Colors.black87,
                              );
                          return Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                                horizontal: 12.w, vertical: 10.h),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10.r),
                              border: Border.all(
                                  color: Colors.orange.withOpacity(0.4)),
                            ),
                            child: loadingCheckoutClientBalance
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 18.w,
                                        height: 18.w,
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      SizedBox(width: 8.w),
                                      Text(
                                        'جاري تحميل الرصيد...',
                                        style: TextStyle(fontSize: 13.sp),
                                      ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'الرصيد قبل الفاتورة: ${invoiceAmount(balanceBefore)} ج.م',
                                        textAlign: TextAlign.center,
                                        style: balanceStyle(balanceBefore),
                                      ),
                                      SizedBox(height: 6.h),
                                      Text(
                                        '$afterLabel: ${invoiceAmount(balanceAfter)} ج.م',
                                        textAlign: TextAlign.center,
                                        style: balanceStyle(balanceAfter)
                                            .copyWith(fontSize: 14.sp),
                                      ),
                                    ],
                                  ),
                          );
                        },
                      ),
                    ],
                    SizedBox(height: 10.h),
                    TextField(
                      controller: notesCtrl,
                      textAlign: TextAlign.right,
                      onTap: () => _selectAllField(notesCtrl),
                      onChanged: (v) => notes = v,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'بيانات إضافية للفاتورة',
                        hintStyle:
                            TextStyle(fontSize: 12.sp, color: Colors.grey),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.r)),
                        contentPadding: EdgeInsets.symmetric(
                            vertical: 10.h, horizontal: 12.w),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12.r),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 20.sp,
                                color: Colors.orange.shade800,
                              ),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: Text(
                                  'توزيع المدفوعات',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              Text(
                                'اختياري',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            'سجّل طريقة استلام المبلغ لعرضها في استعلامات المدفوعات.',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          SizedBox(height: 12.h),
                          Row(
                            children: [
                              Expanded(
                                child: paymentBreakdownField(
                                  fieldKey: const Key(
                                    'invoice-breakdown-wallet-field',
                                  ),
                                  controller: walletCtrl,
                                  label: 'محفظة',
                                  icon: Icons.phone_android,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: paymentBreakdownField(
                                  fieldKey: const Key(
                                    'invoice-breakdown-cash-field',
                                  ),
                                  controller: cashCtrl,
                                  label: 'نقدي',
                                  icon: Icons.payments_outlined,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 10.h),
                          Row(
                            children: [
                              Expanded(
                                child: paymentBreakdownField(
                                  fieldKey: const Key(
                                    'invoice-breakdown-instapay-field',
                                  ),
                                  controller: instapayCtrl,
                                  label: 'إنستاباي',
                                  icon: Icons.flash_on_outlined,
                                  color: Colors.purple.shade700,
                                ),
                              ),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: paymentBreakdownField(
                                  fieldKey: const Key(
                                    'invoice-breakdown-bank-field',
                                  ),
                                  controller: bankTransferCtrl,
                                  label: 'تحويل بنكي',
                                  icon: Icons.account_balance_outlined,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12.h),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10.w,
                              vertical: 8.h,
                            ),
                            decoration: BoxDecoration(
                              color: hasInvalidBreakdown
                                  ? Colors.red.shade50
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10.r),
                              border: Border.all(
                                color: hasInvalidBreakdown
                                    ? Colors.red.shade300
                                    : Colors.orange.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'إجمالي التوزيع',
                                        style: TextStyle(
                                          fontSize: 11.sp,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        hasInvalidBreakdown
                                            ? 'راجع القيم المدخلة'
                                            : '${invoiceAmount(breakdownTotal)} ج.م',
                                        style: TextStyle(
                                          fontSize: 16.sp,
                                          fontWeight: FontWeight.bold,
                                          color: hasInvalidBreakdown
                                              ? Colors.red.shade700
                                              : Colors.orange.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                OutlinedButton.icon(
                                  key: const Key(
                                    'apply-payment-breakdown-total',
                                  ),
                                  onPressed: hasInvalidBreakdown
                                      ? null
                                      : () {
                                          final value = invoiceAmount(
                                            breakdownTotal,
                                          );
                                          paidCtrl.text = value;
                                          paidCtrl.selection =
                                              TextSelection.collapsed(
                                                  offset: value.length);
                                          lastManualPaid = value;
                                          setSheet(() {});
                                        },
                                  icon: Icon(Icons.check_circle_outline,
                                      size: 18.sp),
                                  label: Text(
                                    'اعتماده كمدفوع',
                                    style: TextStyle(fontSize: 11.sp),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.orange.shade900,
                                    side: BorderSide(
                                      color: Colors.orange.shade400,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10.w,
                                      vertical: 9.h,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 14.h),
                    Row(children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('تراجع',
                              style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: ElevatedButton(
                          key: const Key('invoice-checkout-continue-button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.withOpacity(0.85),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.r)),
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                          ),
                          onPressed: widget.isSaving
                              ? null
                              : () async {
                                  if (checkoutClient.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('يجب ادخال اسم العميل')));
                                    return;
                                  }
                                  if (!await widget
                                      .clientExists(checkoutClient.trim())) {
                                    setSheet(
                                        () => checkoutClientNotFound = true);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('هذا العميل غير موجود'),
                                      ),
                                    );
                                    return;
                                  }
                                  final paidInput = paidCtrl.text.trim();
                                  final parsedPaid =
                                      invoiceTryParseAmount(paidInput);
                                  if (paidInput.isNotEmpty &&
                                      parsedPaid == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content:
                                            Text('المبلغ المدفوع غير صحيح'),
                                      ),
                                    );
                                    return;
                                  }
                                  final paidAmount = parsedPaid ?? 0.0;
                                  final validationMessage =
                                      validateInvoiceCheckoutPayment(
                                    paidAmount: paidAmount,
                                    invoiceTotal: totalAfterDiscount,
                                    paymentMethod: paymentMethod,
                                    isReturnInvoice: widget.isReturnInvoice,
                                  );
                                  if (validationMessage != null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(validationMessage),
                                      ),
                                    );
                                    return;
                                  }

                                  final wallet =
                                      _parseBreakdownAmount(walletCtrl);
                                  final cash = _parseBreakdownAmount(cashCtrl);
                                  final instapay =
                                      _parseBreakdownAmount(instapayCtrl);
                                  final bankTransfer =
                                      _parseBreakdownAmount(bankTransferCtrl);
                                  if (wallet == null ||
                                      cash == null ||
                                      instapay == null ||
                                      bankTransfer == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'تفاصيل الدفع تحتوي على مبلغ غير صحيح'),
                                      ),
                                    );
                                    return;
                                  }

                                  Navigator.pop(
                                      context,
                                      CheckoutSelectionResult(
                                        clientName: checkoutClient.trim(),
                                        paidAmount: paidAmount,
                                        paymentMethod: paymentMethod,
                                        notes: notes,
                                        invoiceDiscount: invoiceDiscount,
                                        discountIsPercent: discountIsPercent,
                                        walletAmount: wallet,
                                        cashAmount: cash,
                                        instapayAmount: instapay,
                                        bankTransferAmount: bankTransfer,
                                      ));
                                },
                          child: widget.isSaving
                              ? SizedBox(
                                  width: 20.w,
                                  height: 20.w,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  widget.isQuote ? 'حفظ عرض السعر' : 'متابعة',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ]),
                    SizedBox(height: 20.h),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }
}
