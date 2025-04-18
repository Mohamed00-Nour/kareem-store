import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../EditProductPage.dart';
import 'TotalInventoryValuePage.dart';

class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});

  @override
  _ProductListPageState createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  bool _showLowStock = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _deleteProduct(
      BuildContext context, String productId, Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('هل تريد حذف المنتج؟'),
          content: Text('سيتم حذف المنتج ${product['name']} من المخزن'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('إلغاء'),
            ),
            TextButton(
              onPressed: () async {
                final changesCollection = FirebaseFirestore.instance
                    .collection('products')
                    .doc(productId)
                    .collection('changes');
                final changesSnapshot = await changesCollection.get();
                for (var doc in changesSnapshot.docs) {
                  await doc.reference.delete();
                }
                await FirebaseFirestore.instance
                    .collection('products')
                    .doc(productId)
                    .delete();
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم حذف المنتج بنجاح'),
                    action: SnackBarAction(
                      label: 'تراجع',
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('products')
                            .doc(productId)
                            .set(product);
                      },
                    ),
                    duration: Duration(seconds: 5),
                  ),
                );
              },
              child: Text('حذف'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffeeeced),
      appBar: AppBar(
        title: Text('جميع المنتجات',
            style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (context) => TotalInventoryValuePage()),
              );
            },
            child: Text('جرد المخزن',
                style: TextStyle(fontSize: 16.sp, color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _showLowStock = !_showLowStock;
              });
            },
            child: Text(
              _showLowStock ? 'عرض الكل' : 'عرض النواقص',
              style: TextStyle(fontSize: 16.sp, color: Colors.white),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 5.h, horizontal: 10.w),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.black.withOpacity(0.7)),
                ),
                filled: true,
                fillColor: Colors.grey.withOpacity(0.2),
                labelText: 'ابحث عن منتج',
                labelStyle: TextStyle(
                  color: Colors.black.withOpacity(0.7),
                  fontSize: 18,
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (query) {
                setState(() {
                  _searchQuery = query;
                });
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 10.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'الكمية',
                    style:
                        TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'السعر',
                    style:
                        TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'التكلفة',
                    style:
                        TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'الإسم',
                    style:
                        TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance.collection('products').snapshots(),
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
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                }

                final products = snapshot.data!.docs;
                final filteredProducts = _searchQuery.isEmpty
                    ? products
                    : products.where((doc) {
                        final product = doc.data() as Map<String, dynamic>;
                        final productName = (product['name'] ?? '').toLowerCase();
                        return productName.contains(_searchQuery.toLowerCase());
                      }).toList();

                final displayedProducts = _showLowStock
                    ? filteredProducts.where((doc) {
                        final product = doc.data() as Map<String, dynamic>;
                        return product['quantity'] <= product['alertAmount'];
                      }).toList()
                    : filteredProducts;

                return ListView.builder(
                  itemCount: displayedProducts.length,
                  itemBuilder: (context, index) {
                    final doc = displayedProducts[index];
                    final product = doc.data() as Map<String, dynamic>;
                    final productId = doc.id;
                    return Card(
                      margin:
                          EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.8),
                      child: ListTile(
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                product['quantity']?.toString() ?? '0',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  color: (product['quantity'] <=
                                          product['alertAmount'])
                                      ? Colors.red
                                      : Colors.black.withOpacity(0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                product['sellingPrice1']?.toStringAsFixed(2) ??
                                    '0.00',
                                style: TextStyle(fontSize: 14.sp),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                product['costPrice']?.toStringAsFixed(2) ??
                                    '0.00',
                                style: TextStyle(fontSize: 14.sp),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                product['name'] ?? 'No Name',
                                style: TextStyle(fontSize: 14.sp),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => EditProductPage(
                              productId: productId,
                              productData: product,
                            ),
                          ));
                        },
                        onLongPress: () =>
                            _deleteProduct(context, productId, product),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}