import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class CheckoutSelectionResult {
  final String clientName;
  final double paidAmount;
  final String paymentMethod;
  final String notes;
  final double invoiceDiscount;
  final bool discountIsPercent;

  CheckoutSelectionResult({
    required this.clientName,
    required this.paidAmount,
    required this.paymentMethod,
    required this.notes,
    required this.invoiceDiscount,
    required this.discountIsPercent,
  });
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
}) {
  return showModalBottomSheet<CheckoutSelectionResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
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
  });

  @override
  State<_InvoiceCheckoutSheetContent> createState() => _InvoiceCheckoutSheetContentState();
}

class _InvoiceCheckoutSheetContentState extends State<_InvoiceCheckoutSheetContent> {
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

  @override
  void initState() {
    super.initState();
    paymentMethod = widget.isEditing ? widget.paymentMethod : 'نقداً';
    invoiceDiscount = widget.isEditing ? widget.invoiceDiscount : 0.0;
    discountIsPercent = !widget.isEditing;
    checkoutClient = widget.clientName;
    notes = widget.isEditing ? widget.notes : '';
    checkoutClientBalance = checkoutClient.trim().isNotEmpty && checkoutClient.trim() == widget.clientName.trim() ? widget.clientBalance : null;
    
    paidCtrl = TextEditingController(text: widget.isEditing && widget.originalPaidAmount > 0 ? widget.originalPaidAmount.toStringAsFixed(2) : '');
    discountCtrl = TextEditingController(text: widget.isEditing && widget.invoiceDiscount > 0 ? widget.invoiceDiscount.toStringAsFixed(2) : '');
    notesCtrl = TextEditingController(text: notes);
    lastManualPaid = widget.isEditing && widget.originalPaidAmount > 0 ? widget.originalPaidAmount.toStringAsFixed(2) : '';
  }

  @override
  void dispose() {
    paidCtrl.dispose();
    discountCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  void _selectAllField(TextEditingController controller) {
    final text = controller.text;
    if (text.isEmpty) return;
    controller.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  String invoiceAmount(double amount) => amount.toStringAsFixed(2);

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
          double paid = double.tryParse(paidCtrl.text) ?? 0.0;
          double remaining = paid - totalAfterDiscount;
          final bool isCash = paymentMethod == 'نقداً';
          final bool paidLessThanTotal =
              isCash && paid + 0.001 < totalAfterDiscount;

          void syncPaidForPaymentMethod() {
            if (paymentMethod == 'نقداً') {
              paidCtrl.text = '';
            } else {
              paidCtrl.text = lastManualPaid;
            }
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
                    Row(
                      children: [
                        Text('طريقة الدفع',
                            style: TextStyle(
                                fontSize: 13.sp, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        ...['نقداً', 'آجل', 'بطاقه', 'ش'].map((m) => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Radio<String>(
                                  value: m,
                                  groupValue: paymentMethod,
                                  activeColor: Colors.green,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onChanged: (v) => setSheet(() {
                                    paymentMethod = v!;
                                    syncPaidForPaymentMethod();
                                  }),
                                ),
                                Text(m, style: TextStyle(fontSize: 11.sp)),
                              ],
                            )),
                      ],
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
                    if (paidLessThanTotal)
                      Padding(
                        padding: EdgeInsets.only(top: 6.h),
                        child: Text(
                          'المبلغ المدفوع أصغر من الإجمالي',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    SizedBox(height: 8.h),
                    Row(children: [
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              vertical: 10.h, horizontal: 10.w),
                          decoration: BoxDecoration(
                            color: remaining >= 0
                                ? Colors.green.shade50
                                : Colors.red.shade50,
                            border: Border.all(
                                color: remaining >= 0
                                    ? Colors.green.shade300
                                    : Colors.red.shade300),
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
                                    : Colors.red.shade700),
                          ),
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Text('الباقي', style: TextStyle(fontSize: 12.sp)),
                      SizedBox(width: 6.w),
                      GestureDetector(
                        onTap: () => setSheet(() {
                          discountIsPercent = !discountIsPercent;
                        }),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10.w, vertical: 9.h),
                          decoration: BoxDecoration(
                            color: discountIsPercent
                                ? Colors.orange.shade100
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Text('%',
                              style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      SizedBox(width: 6.w),
                      SizedBox(
                        width: 80.w,
                        child: TextField(
                          controller: discountCtrl,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            hintText: '0',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.r)),
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 8.h, horizontal: 6.w),
                          ),
                          onTap: () => _selectAllField(discountCtrl),
                          onChanged: (v) => setSheet(() {
                            invoiceDiscount = double.tryParse(v) ?? 0.0;
                          }),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Text('الخصم',
                          style: TextStyle(
                              fontSize: 13.sp, fontWeight: FontWeight.bold)),
                    ]),
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
                                  if (!await widget.clientExists(
                                      checkoutClient.trim())) {
                                    setSheet(() => checkoutClientNotFound = true);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('هذا العميل غير موجود'),
                                      ),
                                    );
                                    return;
                                  }
                                  final paidAmount =
                                      double.tryParse(paidCtrl.text) ?? 0.0;
                                  if (paymentMethod == 'نقداً' &&
                                      paidAmount + 0.001 < totalAfterDiscount) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'المبلغ المدفوع أصغر من الإجمالي'),
                                      ),
                                    );
                                    return;
                                  }
                                  Navigator.pop(context, CheckoutSelectionResult(
                                    clientName: checkoutClient.trim(),
                                    paidAmount: paidAmount,
                                    paymentMethod: paymentMethod,
                                    notes: notes,
                                    invoiceDiscount: invoiceDiscount,
                                    discountIsPercent: discountIsPercent,
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