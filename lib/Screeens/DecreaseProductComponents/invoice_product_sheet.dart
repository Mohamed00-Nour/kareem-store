import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'product_model.dart';
import 'decrease_product_widgets.dart';

class ProductSelectionResult {
  final Product product;
  final double amount;
  final int priceTier;
  final double customPrice;
  final double discount;
  final bool discountIsPercent;
  final String barcodeNote;
  final String customProductName;
  final bool removeProduct;
  final double sp1;
  final double sp2;
  final double sp3;
  final String sp1Text;
  final String sp2Text;
  final String sp3Text;

  ProductSelectionResult({
    required this.product,
    required this.amount,
    required this.priceTier,
    required this.customPrice,
    required this.discount,
    required this.discountIsPercent,
    required this.barcodeNote,
    required this.customProductName,
    required this.removeProduct,
    required this.sp1,
    required this.sp2,
    required this.sp3,
    required this.sp1Text,
    required this.sp2Text,
    required this.sp3Text,
  });
}

Future<ProductSelectionResult?> showInvoiceProductSheet({
  required BuildContext context,
  required Product product,
  required int defaultPriceTier,
  required bool isQuote,
  Map<String, dynamic>? editItem,
  required Future<Product?> Function(Product) onNavigateToEdit,
}) {
  return showModalBottomSheet<ProductSelectionResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
    builder: (ctx) {
      return _InvoiceProductSheetContent(
        product: product,
        defaultPriceTier: defaultPriceTier,
        isQuote: isQuote,
        editItem: editItem,
        onNavigateToEdit: onNavigateToEdit,
      );
    },
  );
}

class _InvoiceProductSheetContent extends StatefulWidget {
  final Product product;
  final int defaultPriceTier;
  final bool isQuote;
  final Map<String, dynamic>? editItem;
  final Future<Product?> Function(Product) onNavigateToEdit;

  const _InvoiceProductSheetContent({
    required this.product,
    required this.defaultPriceTier,
    required this.isQuote,
    this.editItem,
    required this.onNavigateToEdit,
  });

  @override
  State<_InvoiceProductSheetContent> createState() => _InvoiceProductSheetContentState();
}

class _InvoiceProductSheetContentState extends State<_InvoiceProductSheetContent> {
  late Product sheetProduct;
  late double amount;
  late int priceTier;
  late double customPrice;
  late double sp1;
  late double sp2;
  late double sp3;
  late double discount;
  late bool discountIsPercent;
  late String barcodeNote;
  late String customProductName;
  bool removeProduct = false;
  bool costObscured = false;

  late TextEditingController qtyCtrl;
  late TextEditingController discountCtrl;
  late TextEditingController barcodeCtrl;
  late TextEditingController customNameCtrl;
  late TextEditingController customPriceCtrl;
  late TextEditingController sp1Ctrl;
  late TextEditingController sp2Ctrl;
  late TextEditingController sp3Ctrl;

  @override
  void initState() {
    super.initState();
    sheetProduct = widget.product;
    final editItem = widget.editItem;

    amount = editItem != null ? double.tryParse(editItem['amount'].toString()) ?? 1.0 : 1.0;
    priceTier = editItem != null ? (editItem['priceTier'] ?? 1) : widget.defaultPriceTier;
    customPrice = editItem != null && (editItem['priceTier'] ?? 1) == 0
        ? ((editItem['selectedPrice'] ?? 0.0) as num).toDouble()
        : 0.0;
    
    double defaultInvoiceNum(dynamic v) => v == null ? 0.0 : (v as num).toDouble();
    
    sp1 = editItem != null ? defaultInvoiceNum(editItem['sellingPrice1']) : sheetProduct.sellingPrice1;
    sp2 = editItem != null ? defaultInvoiceNum(editItem['sellingPrice2']) : sheetProduct.sellingPrice2;
    sp3 = editItem != null ? defaultInvoiceNum(editItem['sellingPrice3']) : sheetProduct.sellingPrice3;
    if (sp1 == 0) sp1 = sheetProduct.sellingPrice1;
    if (sp2 == 0) sp2 = sheetProduct.sellingPrice2;
    if (sp3 == 0) sp3 = sheetProduct.sellingPrice3;
    
    discount = editItem != null ? ((editItem['discount'] ?? 0.0) as num).toDouble() : 0.0;
    discountIsPercent = editItem != null ? (editItem['discountIsPercent'] ?? true) : true;
    barcodeNote = editItem != null ? (editItem['barcodeNote'] ?? '') : '';
    customProductName = editItem != null ? (editItem['customProductName']?.toString() ?? '') : '';

    qtyCtrl = TextEditingController(text: amount.toStringAsFixed(1));
    discountCtrl = TextEditingController(text: discount > 0 ? discount.toStringAsFixed(1) : '');
    barcodeCtrl = TextEditingController(text: barcodeNote);
    customNameCtrl = TextEditingController(text: customProductName);
    customPriceCtrl = TextEditingController(text: customPrice > 0 ? customPrice.toStringAsFixed(2) : '');
    sp1Ctrl = TextEditingController(text: sp1 > 0 ? sp1.toStringAsFixed(2) : '');
    sp2Ctrl = TextEditingController(text: sp2 > 0 ? sp2.toStringAsFixed(2) : '');
    sp3Ctrl = TextEditingController(text: sp3 > 0 ? sp3.toStringAsFixed(2) : '');
  }

  @override
  void dispose() {
    qtyCtrl.dispose();
    discountCtrl.dispose();
    barcodeCtrl.dispose();
    customNameCtrl.dispose();
    customPriceCtrl.dispose();
    sp1Ctrl.dispose();
    sp2Ctrl.dispose();
    sp3Ctrl.dispose();
    super.dispose();
  }

  void _selectAllField(TextEditingController controller) {
    final text = controller.text;
    if (text.isEmpty) return;
    controller.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  double getPriceForTier(int tier) {
    if (tier == 0) return customPrice;
    switch (tier) {
      case 2: return sp2;
      case 3: return sp3;
      default: return sp1;
    }
  }

  double calcTotal(double amt, double disc, bool isPercent, int tier) {
    double price = getPriceForTier(tier);
    double subtotal = price * amt;
    double result = isPercent ? subtotal - (subtotal * disc / 100) : subtotal - disc;
    return result < 0 ? 0 : result;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16.w,
          right: 16.w,
          top: 20.h,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Product name + open full edit page
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        sheetProduct.name,
                        style: TextStyle(
                          fontSize: 17.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final updated = await widget.onNavigateToEdit(sheetProduct);
                      if (updated == null || !mounted) return;
                      setState(() {
                        sheetProduct = updated;
                        sp1 = updated.sellingPrice1;
                        sp2 = updated.sellingPrice2;
                        sp3 = updated.sellingPrice3;
                        sp1Ctrl.text = sp1 > 0 ? sp1.toStringAsFixed(2) : '';
                        sp2Ctrl.text = sp2 > 0 ? sp2.toStringAsFixed(2) : '';
                        sp3Ctrl.text = sp3 > 0 ? sp3.toStringAsFixed(2) : '';
                      });
                    },
                    icon: Icon(Icons.edit_outlined, size: 18.sp),
                    label: Text(
                      'تعديل المنتج',
                      style: TextStyle(fontSize: 12.sp),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'اسم المخزن: ${sheetProduct.name}',
                  style: TextStyle(fontSize: 11.sp, color: Colors.black54),
                ),
              ),
              if (sheetProduct.description != null && sheetProduct.description!.trim().isNotEmpty) ...[
                SizedBox(height: 6.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    border: Border.all(color: Colors.blue.shade200),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 16.sp, color: Colors.blue.shade800),
                          SizedBox(width: 6.w),
                          Text(
                            'وصف المنتج (تلميح للاسترشاد فقط - لا يظهر بالفاتورة):',
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        sheetProduct.description!.trim(),
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: 8.h),
              TextField(
                controller: customNameCtrl,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  labelText: 'اسم مخصص (للفاتورة فقط)',
                  hintText: 'اتركه فارغاً لاستخدام اسم المخزن',
                  hintStyle: TextStyle(fontSize: 11.sp),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                  contentPadding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
                ),
                onTap: () => _selectAllField(customNameCtrl),
                onChanged: (v) => customProductName = v,
              ),
              SizedBox(height: 14.h),

              // ── سعر البيع ──
              Row(children: [
                Expanded(
                  flex: 3,
                  child: priceTier == 0
                      ? TextField(
                          controller: customPriceCtrl,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800),
                          decoration: InputDecoration(
                            hintText: 'سعر خاص',
                            hintStyle: TextStyle(fontSize: 12.sp, color: Colors.grey),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.r),
                                borderSide: const BorderSide(color: Colors.orange)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.r),
                                borderSide: const BorderSide(color: Colors.orange, width: 2)),
                            contentPadding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
                          ),
                          onTap: () => _selectAllField(customPriceCtrl),
                          onChanged: (v) => setState(() {
                            customPrice = double.tryParse(v) ?? 0.0;
                          }),
                        )
                      : TextField(
                          controller: priceTier == 2 ? sp2Ctrl : priceTier == 3 ? sp3Ctrl : sp1Ctrl,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800),
                          decoration: InputDecoration(
                            hintText: 'أدخل السعر',
                            hintStyle: TextStyle(fontSize: 12.sp, color: Colors.grey),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.r),
                                borderSide: const BorderSide(color: Colors.orange)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.r),
                                borderSide: const BorderSide(color: Colors.orange, width: 2)),
                            contentPadding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
                          ),
                          onTap: () => _selectAllField(
                            priceTier == 2 ? sp2Ctrl : priceTier == 3 ? sp3Ctrl : sp1Ctrl,
                          ),
                          onChanged: (v) => setState(() {
                            final parsed = double.tryParse(v) ?? 0.0;
                            if (priceTier == 2) sp2 = parsed;
                            else if (priceTier == 3) sp3 = parsed;
                            else sp1 = parsed;
                          }),
                        ),
                ),
                SizedBox(width: 8.w),
                PriceTierBtn(
                    label: '3', selected: priceTier == 3, onTap: () => setState(() => priceTier = 3)),
                SizedBox(width: 4.w),
                PriceTierBtn(
                    label: '2', selected: priceTier == 2, onTap: () => setState(() => priceTier = 2)),
                SizedBox(width: 4.w),
                PriceTierBtn(
                    label: '1', selected: priceTier == 1, onTap: () => setState(() => priceTier = 1)),
                SizedBox(width: 4.w),
                PriceTierBtn(
                    label: 'خ', selected: priceTier == 0, onTap: () => setState(() => priceTier = 0)),
                SizedBox(width: 8.w),
                Text('سعر البيع', style: TextStyle(fontSize: 13.sp)),
              ]),
              SizedBox(height: 10.h),

              // ── الكمية ──
              Row(children: [
                Expanded(
                    flex: 3,
                    child: SheetValueBox(
                        value: calcTotal(amount, discount, discountIsPercent, priceTier)
                            .toStringAsFixed(1))),
                SizedBox(width: 8.w),
                CircleBtn(
                    icon: Icons.remove,
                    onTap: () {
                      if (amount > 1) {
                        setState(() {
                          amount -= 1;
                          qtyCtrl.text = amount.toStringAsFixed(1);
                        });
                      }
                    }),
                SizedBox(width: 6.w),
                SizedBox(
                  width: 64.w,
                  child: TextField(
                    controller: qtyCtrl,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade700),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.r),
                          borderSide: const BorderSide(color: Colors.orange)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.r),
                          borderSide: const BorderSide(color: Colors.orange, width: 2)),
                      contentPadding: EdgeInsets.symmetric(vertical: 8.h),
                    ),
                    onTap: () => _selectAllField(qtyCtrl),
                    onChanged: (v) => setState(() => amount = double.tryParse(v) ?? amount),
                  ),
                ),
                SizedBox(width: 6.w),
                CircleBtn(
                    icon: Icons.add,
                    onTap: () => setState(() {
                          amount += 1;
                          qtyCtrl.text = amount.toStringAsFixed(1);
                        })),
                SizedBox(width: 8.w),
                Text('الكمية', style: TextStyle(fontSize: 13.sp)),
              ]),
              SizedBox(height: 10.h),

              // ── الخصم ──
              Row(children: [
                Expanded(
                    flex: 3,
                    child: SheetValueBox(
                        value: (discountIsPercent
                                ? getPriceForTier(priceTier) * amount * discount / 100
                                : discount)
                            .toStringAsFixed(1))),
                SizedBox(width: 8.w),
                GestureDetector(
                  onTap: () => setState(() => discountIsPercent = true),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h),
                    decoration: BoxDecoration(
                      color: discountIsPercent ? Colors.orange.withOpacity(0.85) : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text('%',
                        style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold,
                            color: discountIsPercent ? Colors.white : Colors.black87)),
                  ),
                ),
                SizedBox(width: 6.w),
                SizedBox(
                  width: 74.w,
                  child: TextField(
                    controller: discountCtrl,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(fontSize: 14.sp),
                    decoration: InputDecoration(
                      hintText: 'نسبه',
                      hintStyle: TextStyle(fontSize: 12.sp, color: Colors.grey),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                      contentPadding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 6.w),
                    ),
                    onTap: () => _selectAllField(discountCtrl),
                    onChanged: (v) => setState(() => discount = double.tryParse(v) ?? 0.0),
                  ),
                ),
                SizedBox(width: 6.w),
                GestureDetector(
                  onTap: () => setState(() => discountIsPercent = false),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h),
                    decoration: BoxDecoration(
                      color: !discountIsPercent ? Colors.orange.withOpacity(0.85) : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(Icons.monetization_on_outlined,
                        size: 16.sp, color: !discountIsPercent ? Colors.white : Colors.black87),
                  ),
                ),
                SizedBox(width: 8.w),
                Text('الخصم', style: TextStyle(fontSize: 13.sp)),
              ]),
              SizedBox(height: 12.h),

              // ── ملاحظة للمنتج ──
              Align(
                alignment: Alignment.centerRight,
                child: Text('ملاحظه للمنتج تظهر في الفاتورة',
                    style: TextStyle(fontSize: 11.sp, color: Colors.black54)),
              ),
              SizedBox(height: 6.h),
              Row(children: [
                Icon(Icons.qr_code, size: 38.sp, color: Colors.black87),
                SizedBox(width: 8.w),
                Expanded(
                  child: TextField(
                    controller: barcodeCtrl,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      hintText: 'مثلا:اللون | الرقم التسلسلي |الحجم',
                      hintStyle: TextStyle(fontSize: 11.sp),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                      contentPadding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 12.w),
                      suffixIcon: Icon(Icons.edit_outlined, size: 18.sp),
                    ),
                    onTap: () => _selectAllField(barcodeCtrl),
                    onChanged: (v) => barcodeNote = v,
                  ),
                ),
              ]),
              SizedBox(height: 12.h),

              // ── الكمية المتوفرة + التكلفة ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الكميه المتوفره', style: TextStyle(fontSize: 13.sp)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Text(
                          sheetProduct.quantity.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 6.h),
                      GestureDetector(
                        onTap: () => setState(() => costObscured = !costObscured),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 8.h),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6.r),
                            child: costObscured
                                ? ImageFiltered(
                                    imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                    child: Text(
                                      sheetProduct.costPrice.toStringAsFixed(2),
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  )
                                : Text(
                                    sheetProduct.costPrice.toStringAsFixed(2),
                                    style: TextStyle(
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 10.h),

              // ── إلغاء المنتج ──
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Checkbox(
                  value: removeProduct,
                  activeColor: Colors.red,
                  onChanged: (v) => setState(() => removeProduct = v ?? false),
                ),
                Row(children: [
                  Icon(Icons.close, color: Colors.red, size: 16.sp),
                  SizedBox(width: 4.w),
                  Text('إلغاء المنتج من القائمه',
                      style: TextStyle(fontSize: 13.sp, color: Colors.red)),
                ]),
              ]),
              SizedBox(height: 14.h),

              // ── Action buttons ──
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('تراجع',
                        style: TextStyle(
                            color: Colors.orange, fontSize: 15.sp, fontWeight: FontWeight.bold)),
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.withOpacity(0.85),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                    ),
                    onPressed: () async {
                      if (removeProduct) {
                        Navigator.pop(
                            context,
                            ProductSelectionResult(
                                product: sheetProduct,
                                amount: amount,
                                priceTier: priceTier,
                                customPrice: customPrice,
                                discount: discount,
                                discountIsPercent: discountIsPercent,
                                barcodeNote: barcodeNote,
                                customProductName: customProductName,
                                removeProduct: true,
                                sp1: sp1,
                                sp2: sp2,
                                sp3: sp3,
                                sp1Text: sp1Ctrl.text,
                                sp2Text: sp2Ctrl.text,
                                sp3Text: sp3Ctrl.text));
                        return;
                      }

                      double activePrice = getPriceForTier(priceTier);

                      if (sheetProduct.costPrice > 0 && activePrice < sheetProduct.costPrice) {
                        final proceed = await showDialog<bool>(
                          context: context,
                          builder: (dialogCtx) => Directionality(
                            textDirection: TextDirection.rtl,
                            child: AlertDialog(
                              title: const Text('تنبيه هام'),
                              content: Text(
                                  'سعر البيع ($activePrice) أقل من سعر التكلفة (${sheetProduct.costPrice}). هل تريد الاستمرار؟'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogCtx, false),
                                  child: const Text('تعديل السعر', style: TextStyle(color: Colors.red)),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                  onPressed: () => Navigator.pop(dialogCtx, true),
                                  child: const Text('استمرار', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (proceed != true) return;
                      }

                      if (!mounted) return;
                      Navigator.pop(
                          context,
                          ProductSelectionResult(
                              product: sheetProduct,
                              amount: amount,
                              priceTier: priceTier,
                              customPrice: customPrice,
                              discount: discount,
                              discountIsPercent: discountIsPercent,
                              barcodeNote: barcodeNote,
                              customProductName: customProductName,
                              removeProduct: false,
                              sp1: sp1,
                              sp2: sp2,
                              sp3: sp3,
                              sp1Text: sp1Ctrl.text,
                              sp2Text: sp2Ctrl.text,
                              sp3Text: sp3Ctrl.text));
                    },
                    child: Text(widget.isQuote ? 'حفظ عرض السعر' : 'متابعة',
                        style: TextStyle(color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
              SizedBox(height: 20.h),
            ],
          ),
        ),
      ),
    );
  }
}
