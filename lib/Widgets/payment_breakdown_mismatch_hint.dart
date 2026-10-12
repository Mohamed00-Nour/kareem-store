import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../Services/invoice_number_utils.dart';

class PaymentBreakdownMismatchHint extends StatelessWidget {
  final double paidAmount;
  final double breakdownTotal;

  const PaymentBreakdownMismatchHint({
    super.key,
    required this.paidAmount,
    required this.breakdownTotal,
  });

  @override
  Widget build(BuildContext context) {
    if (!paidAmount.isFinite ||
        !breakdownTotal.isFinite ||
        (paidAmount * 100).round() == (breakdownTotal * 100).round()) {
      return const SizedBox.shrink();
    }
    final difference =
        ((paidAmount * 100).round() - (breakdownTotal * 100).round()).abs() /
            100;
    return Container(
      margin: EdgeInsets.only(top: 8.h),
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18.sp, color: Colors.orange.shade800),
          SizedBox(width: 6.w),
          Expanded(
            child: Text(
              'المدفوع لا يطابق إجمالي التوزيع. '
              'المدفوع: ${invoiceAmount(paidAmount)} ج.م، '
              'إجمالي التوزيع: ${invoiceAmount(breakdownTotal)} ج.م، '
              'الفرق: ${invoiceAmount(difference)} ج.م. '
              'راجع توزيع المدفوعات.',
              style: TextStyle(fontSize: 12.sp, color: Colors.orange.shade900),
            ),
          ),
        ],
      ),
    );
  }
}
