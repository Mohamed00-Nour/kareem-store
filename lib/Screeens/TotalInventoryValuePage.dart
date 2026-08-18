import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../repositories/product_repository.dart';
import '../local_db/hive_init.dart';

class TotalInventoryValuePage extends StatelessWidget {
  const TotalInventoryValuePage({super.key});

  Map<String, double> _calculateInventoryTotals() {
    final products = ProductRepository.instance.getAll();
    double totalValue = 0.0;
    double totalCost = 0.0;

    for (var product in products) {
      final quantity = product.quantity;
      final sellingPrice1 = product.sellingPrice1;
      final costPrice = product.costPrice;

      totalValue += quantity * sellingPrice1;
      totalCost += quantity * costPrice;
    }

    return {
      'totalValue': totalValue,
      'totalCost': totalCost,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('اجمالي قيمة المخزون', style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withValues(alpha: 0.7),
      ),
      body: ValueListenableBuilder(
        valueListenable: productsBox.listenable(),
        builder: (context, _, __) {
          final totals = _calculateInventoryTotals();
          final totalValue = totals['totalValue'] ?? 0.0;
          final totalCost = totals['totalCost'] ?? 0.0;


          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Total Selling Value
                Container(
                  margin: EdgeInsets.symmetric(vertical: 20.h),
                  padding: EdgeInsets.all(20.w),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(15.r),
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'اجمالي سعر المخزون',
                        style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                      SizedBox(height: 10.h),
                      Text(
                        '${totalValue.toStringAsFixed(2)} جنيه',
                        style: TextStyle(fontSize: 20.sp, color: Colors.green, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),

                // Total Cost
                Container(
                  margin: EdgeInsets.symmetric(vertical: 20.h),
                  padding: EdgeInsets.all(20.w),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(15.r),
                    border: Border.all(color: Colors.orange, width: 2),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'إجمالي تكلفة المخزون',
                        style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                      SizedBox(height: 10.h),
                      Text(
                        '${totalCost.toStringAsFixed(2)} جنيه',
                        style: TextStyle(fontSize: 20.sp, color: Colors.red, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),

                // Profit Margin
                Container(
                  margin: EdgeInsets.symmetric(vertical: 20.h),
                  padding: EdgeInsets.all(20.w),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(15.r),
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'إجمالي الربح المتوقع',
                        style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                      SizedBox(height: 10.h),
                      Text(
                        '${(totalValue - totalCost).toStringAsFixed(2)} جنيه',
                        style: TextStyle(fontSize: 20.sp, color: Colors.purple, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}