import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../EditProductPage.dart';
import '../Services/invoice_number_utils.dart';
import 'TotalInventoryValuePage.dart';

class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});

  @override
  _ProductListPageState createState() => _ProductListPageState();
}

enum _ProductListFilter { all, lowStock, onDemand, retail }

class _ProductListPageState extends State<ProductListPage> {
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  _ProductListFilter _filter = _ProductListFilter.all;
  bool _showCostPrice = true;
  String _userRole = 'user';

  bool _isOnDemand(Map<String, dynamic> product) {
    return product['onDemand'] == true;
  }

  bool _isRetail(Map<String, dynamic> product) {
    return product['retail'] == true;
  }

  double _productQuantity(Map<String, dynamic> product) {
    final q = product['quantity'];
    if (q is num) return q.toDouble();
    if (q is String) return double.tryParse(q) ?? 0.0;
    return 0.0;
  }

  bool _matchesFilter(Map<String, dynamic> product) {
    switch (_filter) {
      case _ProductListFilter.retail:
        return _isRetail(product);
      case _ProductListFilter.onDemand:
        return _isOnDemand(product);
      case _ProductListFilter.lowStock:
        return !_isOnDemand(product) &&
            !_isRetail(product) &&
            product['quantity'] <= product['alertAmount'];
      case _ProductListFilter.all:
        if (_isRetail(product)) return false;
        if (_isOnDemand(product)) return _productQuantity(product) != 0;
        return true;
    }
  }

  void _openMoreMenu() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('جرد المخزن'),
              onTap: () {
                Navigator.pop(ctx);
                if (_userRole == 'admin') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const TotalInventoryValuePage(),
                    ),
                  );
                } else {
                  _showInventoryPermissionDeniedDialog();
                }
              },
            ),
            ListTile(
              leading: Icon(
                _showCostPrice ? Icons.visibility_off : Icons.visibility,
              ),
              title: Text(_showCostPrice ? 'إخفاء التكلفة' : 'إظهار التكلفة'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _showCostPrice = !_showCostPrice);
              },
            ),
          ],
        ),
      ),
    );
  }

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

  void _handleDeleteProduct(BuildContext context, String productId, Map<String, dynamic> product) {
    if (_userRole == 'admin') {
      _deleteProduct(context, productId, product);
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

  void _showInventoryPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('ليس لديك صلاحية'),
          content: Text('ليس لديك الصلاحية للوصول إلى جرد المخزن'),
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
  _loadUserRole();
}

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

  static const Color _tableBorderColor = Color(0xFF424242);
  static const Color _tableHeaderFill = Color(0xFFE8E8E8);
  static const Color _tableRowFillA = Color(0xFFFFFFFF);
  static const Color _tableRowFillB = Color(0xFFF0F4F8);

  TextStyle get _tableHeaderTextStyle => TextStyle(
        fontSize: 12.sp,
        fontWeight: FontWeight.bold,
        color: Colors.black,
      );

  TextStyle get _tableCellTextStyle => TextStyle(
        fontSize: 11.sp,
        color: Colors.black,
      );

  TextStyle get _tableNameTextStyle => TextStyle(
        fontSize: 9.5.sp,
        color: Colors.black,
        height: 1.15,
      );

  Widget _borderedCell(
    Widget child, {
    required int flex,
    Color? fill,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        decoration: BoxDecoration(
          color: fill ?? Colors.white,
          border: Border.all(color: _tableBorderColor, width: 1),
        ),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 6.h),
        child: child,
      ),
    );
  }

  Widget _tableHeaderRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _borderedCell(
          Text('تعداد', textAlign: TextAlign.center, style: _tableHeaderTextStyle),
          flex: 1,
          fill: _tableHeaderFill,
        ),
        _borderedCell(
          Text('الإسم', textAlign: TextAlign.center, style: _tableHeaderTextStyle),
          flex: 4,
          fill: _tableHeaderFill,
        ),
        if (_showCostPrice)
          _borderedCell(
            Text('التكلفة',
                textAlign: TextAlign.center, style: _tableHeaderTextStyle),
            flex: 2,
            fill: _tableHeaderFill,
          ),
        _borderedCell(
          Text('السعر', textAlign: TextAlign.center, style: _tableHeaderTextStyle),
          flex: 2,
          fill: _tableHeaderFill,
        ),
        _borderedCell(
          Text('الكمية', textAlign: TextAlign.center, style: _tableHeaderTextStyle),
          flex: 2,
          fill: _tableHeaderFill,
        ),
      ],
    );
  }

  Widget _tableDataRow({
    required int serial,
    required Map<String, dynamic> product,
    required String productId,
  }) {
    final qty = _productQuantity(product);
    final alert = invoiceNum(product['alertAmount']);
    final lowStock = qty <= alert;
    final rowFill = serial.isOdd ? _tableRowFillA : _tableRowFillB;

    return Material(
      color: rowFill,
      child: InkWell(
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
        onLongPress: () => _handleDeleteProduct(context, productId, product),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _borderedCell(
              Text(
                '$serial',
                textAlign: TextAlign.center,
                style: _tableCellTextStyle.copyWith(fontWeight: FontWeight.w600),
              ),
              flex: 1,
              fill: rowFill,
            ),
            _borderedCell(
              Text(
                product['name']?.toString() ?? '',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _tableNameTextStyle,
              ),
              flex: 4,
              fill: rowFill,
            ),
            if (_showCostPrice)
              _borderedCell(
                Text(
                  invoiceAmount(product['costPrice']),
                  textAlign: TextAlign.center,
                  style: _tableCellTextStyle,
                ),
                flex: 2,
                fill: rowFill,
              ),
            _borderedCell(
              Text(
                invoiceAmount(product['sellingPrice1']),
                textAlign: TextAlign.center,
                style: _tableCellTextStyle,
              ),
              flex: 2,
              fill: rowFill,
            ),
            _borderedCell(
              Text(
                invoiceAmount(product['quantity']),
                textAlign: TextAlign.center,
                style: _tableCellTextStyle.copyWith(
                  color: lowStock ? Colors.red.shade700 : Colors.black,
                  fontWeight: lowStock ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              flex: 2,
              fill: rowFill,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBorderedProductsTable(List<QueryDocumentSnapshot> docs) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            _tableHeaderRow(),
            Expanded(
              child: ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final product = doc.data() as Map<String, dynamic>;
                  return _tableDataRow(
                    serial: index + 1,
                    product: product,
                    productId: doc.id,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, _ProductListFilter mode) {
    final selected = _filter == mode;
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 13.sp)),
      selected: selected,
      onSelected: (_) => setState(() => _filter = mode),
      selectedColor: Colors.orange.withOpacity(0.35),
      checkmarkColor: Colors.black87,
      backgroundColor: Colors.grey.withOpacity(0.15),
      side: BorderSide(
        color: selected
            ? Colors.orange.withOpacity(0.9)
            : Colors.black.withOpacity(0.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffeeeced),
      appBar: AppBar(
        title: Text(
          'جميع المنتجات',
          style: TextStyle(fontSize: 20.sp, color: Colors.white),
        ),
        backgroundColor: Colors.black.withOpacity(0.7),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: 'المزيد',
            onPressed: _openMoreMenu,
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
            padding: EdgeInsets.fromLTRB(10.w, 0, 10.w, 8.h),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('الكل', _ProductListFilter.all),
                  SizedBox(width: 8.w),
                  _filterChip('النواقص', _ProductListFilter.lowStock),
                  SizedBox(width: 8.w),
                  _filterChip('حسب الطلب', _ProductListFilter.onDemand),
                  SizedBox(width: 8.w),
                  _filterChip('قطاعي', _ProductListFilter.retail),
                ],
              ),
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
                  return const Center(child: Text('لا توجد منتجات'));
                }

                final products = snapshot.data!.docs;
                final filteredProducts = _searchQuery.isEmpty
                    ? products
                    : products.where((doc) {
                        final product = doc.data() as Map<String, dynamic>;
                        final productName =
                            (product['name'] ?? '').toLowerCase();
                        return productName.contains(_searchQuery.toLowerCase());
                      }).toList();

                final displayedProducts = filteredProducts.where((doc) {
                  final product = doc.data() as Map<String, dynamic>;
                  return _matchesFilter(product);
                }).toList();

                if (displayedProducts.isEmpty) {
                  return const Center(child: Text('لا توجد منتجات مطابقة'));
                }

                return _buildBorderedProductsTable(displayedProducts);
              },
            ),
          ),
        ],
      ),
    );
  }
}