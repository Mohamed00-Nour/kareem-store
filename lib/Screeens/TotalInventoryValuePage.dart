import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class TotalInventoryValuePage extends StatelessWidget {
  const TotalInventoryValuePage({super.key});

  Future<double> _calculateTotalInventoryValue() async {
    final querySnapshot = await FirebaseFirestore.instance.collection('products').get();
    double totalValue = 0.0;

    for (var doc in querySnapshot.docs) {
      final product = doc.data() as Map<String, dynamic>;
      final quantity = product['quantity'] ?? 0;
      final sellingPrice1 = product['sellingPrice1'] ?? 0.0;
      totalValue += quantity * sellingPrice1;
    }

    return totalValue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('اجمالي سعر المخزون', style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: FutureBuilder<double>(
        future: _calculateTotalInventoryValue(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                color: Colors.orange.withOpacity(0.8),
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final totalValue = snapshot.data ?? 0.0;

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  ':اجمالي سعر المخزون',
                  style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                ),
                Text(
                  'جنيه ${totalValue.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 20.sp , color: Colors.green),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}