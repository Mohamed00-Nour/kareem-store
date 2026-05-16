import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../EditProductPage.dart';

class DepartmentProductsPage extends StatefulWidget {
  final String departmentName;

  const DepartmentProductsPage({super.key, required this.departmentName});

  @override
  _DepartmentProductsPageState createState() => _DepartmentProductsPageState();
}

class _DepartmentProductsPageState extends State<DepartmentProductsPage> {
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  bool _showLowStock = false;
  String _currentDepartmentName = ""; // Initialize with a default value

  String _userRole = 'user'; // Default to user role

  Future<void> _loadUserRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userRole = prefs.getString('user_role') ?? 'user';
      });
    } catch (e) {
      print('Error loading user role: $e');
    }
  }

  void _handleDeleteProduct(BuildContext context, String productId) {
    if (_userRole == 'admin') {
      _deleteProduct(context, productId);
    } else {
      _showPermissionDeniedDialog();
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('ليس لديك صلاحية'),
          content: Text('ليس لديك الصلاحية لحذف المنتجات'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('موافق'),
            ),
          ],
        );
      },
    );
  }


  @override
  void initState() {
    super.initState();
    _currentDepartmentName = widget.departmentName;
    _loadUserRole();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _editDepartmentName(BuildContext context) {
    final TextEditingController _editController =
        TextEditingController(text: _currentDepartmentName);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('تعديل اسم القسم'),
          content: TextField(
            controller: _editController,
            decoration: InputDecoration(labelText: 'اسم القسم الجديد'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إلغاء'),
            ),
            TextButton(
              onPressed: () async {
                String newName = _editController.text.trim();
                if (newName.isNotEmpty && newName != _currentDepartmentName) {
                  try {
                    QuerySnapshot query = await FirebaseFirestore.instance
                        .collection('departments')
                        .where('name', isEqualTo: _currentDepartmentName)
                        .get();

                    if (query.docs.isNotEmpty) {
                      await query.docs.first.reference.update({'name': newName});
                    }

                    setState(() {
                      _currentDepartmentName = newName;
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم تعديل اسم القسم بنجاح')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('حدث خطأ أثناء تعديل اسم القسم: $e')),
                    );
                  }
                }
                Navigator.of(context).pop();
              },
              child: Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteDepartment(BuildContext context) {
    if (_userRole == 'admin') {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('حذف القسم'),
            content: Text(
                'هل أنت متأكد أنك تريد حذف القسم $_currentDepartmentName؟\nلن يتم حذف المنتجات المرتبطة.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('إلغاء'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    QuerySnapshot query = await FirebaseFirestore.instance
                        .collection('departments')
                        .where('name', isEqualTo: _currentDepartmentName)
                        .get();

                    if (query.docs.isNotEmpty) {
                      await query.docs.first.reference.delete();
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم حذف القسم بنجاح')),
                    );
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('حدث خطأ أثناء حذف القسم: $e')),
                    );
                  }
                },
                child: Text('حذف'),
              ),
            ],
          );
        },
      );
    } else {
      _showPermissionDeniedForDepartmentDialog();
    }
  }

  void _showPermissionDeniedForDepartmentDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('ليس لديك صلاحية'),
          content: Text('ليس لديك الصلاحية لحذف الأقسام'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('موافق'),
            ),
          ],
        );
      },
    );
  }

  void _deleteProduct(BuildContext context, String productId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('هل تريد حذف المنتج؟'),
          content: Text('سيتم حذف المنتج من القسم $_currentDepartmentName'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إلغاء'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance
                      .collection('products')
                      .doc(productId)
                      .delete();
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم حذف المنتج بنجاح'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                } catch (e) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('حدث خطأ أثناء حذف المنتج: $e'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
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
      appBar: AppBar(
        title: Text('قسم $_currentDepartmentName',
            style: TextStyle(fontSize: 14.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
        actions: [
          IconButton(
            icon: Icon(Icons.edit, color: Colors.white , size: 16,),
            onPressed: () => _editDepartmentName(context),
          ),
          IconButton(
            icon: Icon(Icons.delete, color: Colors.red, size: 16,),
            onPressed: () => _confirmDeleteDepartment(context),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _showLowStock = !_showLowStock;
              });
            },
            child: Text(
              _showLowStock ? 'عرض الكل' : 'عرض النواقص',
              style: TextStyle(fontSize: 14.sp, color: Colors.white),
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
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'السعر',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'التكلفة',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'الإسم',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('products')
                  .where('department', isEqualTo: _currentDepartmentName)
                  .snapshots(),
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
                  return Center(child: Text('لا توجد منتجات في هذا القسم.'));
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
                      margin: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
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
                                  color: (product['quantity'] <= product['alertAmount'])
                                      ? Colors.red
                                      : Colors.black.withOpacity(0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                product['sellingPrice1']?.toStringAsFixed(2) ?? '0.00',
                                style: TextStyle(fontSize: 14.sp),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                product['costPrice']?.toStringAsFixed(2) ?? '0.00',
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
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => EditProductPage(
                                productId: productId,
                                productData: product,
                              ),
                            ),
                          );
                        },
                        onLongPress: () => _handleDeleteProduct(context, productId),
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