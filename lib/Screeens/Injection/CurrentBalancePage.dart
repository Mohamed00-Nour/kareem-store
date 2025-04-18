import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'InjectedProductHistoryPage.dart';

class CurrentBalancePage extends StatefulWidget {
  const CurrentBalancePage({super.key});

  @override
  _CurrentBalancePageState createState() => _CurrentBalancePageState();
}

class _CurrentBalancePageState extends State<CurrentBalancePage> {
  bool _showAllProducts = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'الرصيد الحالي للحقن',
          style: TextStyle(fontSize: 20.sp, color: Colors.white),
          textAlign: TextAlign.right,
        ),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: Padding(
        padding: EdgeInsets.all(10.w),
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('injectedProducts').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: Colors.orange.withOpacity(0.8),
                      ),
                    );
                  } else if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(child: Text('لا يوجد منتجات'));
                  } else {
                    final products = snapshot.data!.docs;
                    final filteredProducts = _showAllProducts
                        ? products
                        : products.where((product) => int.parse(product['amount']) > 0).toList();
                    return ListView.builder(
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];
                        return Card(
                          margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: ListTile(
                            title: Center(child: Text(product['product'], style: TextStyle(fontSize: 18.sp, color: Colors.black.withOpacity(0.7)))),
                            subtitle: Center(child: Text('الكمية: ${product['amount']}', style: TextStyle(fontSize: 16.sp, color: Colors.white))),
                            onTap: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (context) => InjectedProductHistoryPage(
                                  productId: product.id,
                                  productName: product['product'],
                                ),
                              ));
                            },
                          ),
                        );
                      },
                    );
                  }
                },
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _showAllProducts = !_showAllProducts;
                });
              },
              child: Text(
                _showAllProducts ? 'إخفاء المنتجات ذات الكمية 0' : 'عرض جميع المنتجات',
                style: TextStyle(fontSize: 16.sp, color: Colors.blue),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}