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

enum _ProductListFilter { all, lowStock, onDemand, retail, damaged }

class _ProductListPageState extends State<ProductListPage> {
  static const String _damagedProductsCollection = 'damagedProducts';

  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  _ProductListFilter _filter = _ProductListFilter.all;
  bool _showCostPrice = true;
  String _userRole = 'user';
  bool _productActionInProgress = false;

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

  bool get _showingDamaged => _filter == _ProductListFilter.damaged;

  bool _matchesFilter(Map<String, dynamic> product) {
    switch (_filter) {
      case _ProductListFilter.damaged:
        return true;
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

  bool get _isAdmin => _userRole == 'admin';

  void _handleProductLongPress(
    String productId,
    Map<String, dynamic> product,
  ) {
    if (!_isAdmin) {
      _showPermissionDeniedDialog();
      return;
    }
    if (_productActionInProgress) return;

    final name = product['name']?.toString() ?? '';
    showModalBottomSheet<void>(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
              child: Text(
                name.isEmpty ? 'خيارات المنتج' : name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.broken_image_outlined,
                  color: Colors.orange.shade800),
              title: const Text('نقل إلى منتجات تالفة'),
              subtitle: const Text(
                'يُسجَّل في منتجات تالفة ويُزال من المخزن',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmMoveToDamaged(productId, product);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('حذف من المخزن'),
              subtitle: const Text('حذف نهائي من قائمة المنتجات'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteProduct(productId, product);
              },
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('ليس لديك صلاحية'),
          content: const Text(
            'ليس لديك الصلاحية لإدارة المنتجات (حذف أو نقل تالف)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('موافق'),
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

  bool _matchesSearch(Map<String, dynamic> product) {
    if (_searchQuery.isEmpty) return true;
    final name = (product['name'] ?? '').toString().toLowerCase();
    return name.contains(_searchQuery.toLowerCase());
  }

  String _formatMovedAt(dynamic movedAt) {
    if (movedAt is Timestamp) {
      final d = movedAt.toDate().toLocal();
      return '${d.day}/${d.month}/${d.year}';
    }
    if (movedAt is DateTime) {
      final d = movedAt.toLocal();
      return '${d.day}/${d.month}/${d.year}';
    }
    return '';
  }

  double _damagedQuantity(Map<String, dynamic> product) {
    if (product.containsKey('quantityAtMove')) {
      return _productQuantity({'quantity': product['quantityAtMove']});
    }
    return _productQuantity(product);
  }

  Map<String, dynamic> _productPayloadForStorage(
    String productId,
    Map<String, dynamic> product,
  ) {
    final data = Map<String, dynamic>.from(product);
    data['id'] = productId;
    return data;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _fetchProductChanges(String productId) async {
    final snap = await FirebaseFirestore.instance
        .collection('products')
        .doc(productId)
        .collection('changes')
        .get();
    return snap.docs;
  }

  Future<void> _deleteProductChanges(String productId) async {
    final docs = await _fetchProductChanges(productId);
    for (final doc in docs) {
      await doc.reference.delete();
    }
  }

  Future<void> _restoreProductAfterUndo({
    required String productId,
    required Map<String, dynamic> product,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> changes,
  }) async {
    final productRef =
        FirebaseFirestore.instance.collection('products').doc(productId);
    final productSnap = await productRef.get();
    if (!productSnap.exists) {
      await productRef.set(_productPayloadForStorage(productId, product));
    }
    final changesCol = productRef.collection('changes');
    for (final doc in changes) {
      final changeId = doc.id;
      final changeSnap = await changesCol.doc(changeId).get();
      if (!changeSnap.exists) {
        await changesCol.doc(changeId).set(doc.data());
      }
    }
  }

  Future<void> _removeProductFromInventory(String productId) async {
    final docRef =
        FirebaseFirestore.instance.collection('products').doc(productId);
    final doc = await docRef.get();
    if (!doc.exists) {
      throw StateError('المنتج غير موجود في المخزن');
    }
    await _deleteProductChanges(productId);
    await docRef.delete();
  }

  void _confirmDeleteProduct(
    String productId,
    Map<String, dynamic> product,
  ) {
    final name = product['name']?.toString() ?? '';
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('هل تريد حذف المنتج؟'),
          content: Text('سيتم حذف المنتج "$name" من المخزن نهائياً'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                await _executeDeleteProduct(productId, product);
              },
              child: const Text('حذف', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _executeDeleteProduct(
    String productId,
    Map<String, dynamic> product,
  ) async {
    if (_productActionInProgress) return;
    setState(() => _productActionInProgress = true);

    final storedProduct = _productPayloadForStorage(productId, product);
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? changesBackup;

    try {
      changesBackup = await _fetchProductChanges(productId);
      await _removeProductFromInventory(productId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم حذف المنتج بنجاح'),
          action: SnackBarAction(
            label: 'تراجع',
            onPressed: () async {
              try {
                await _restoreProductAfterUndo(
                  productId: productId,
                  product: storedProduct,
                  changes: changesBackup!,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم استرجاع المنتج')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تعذر الاسترجاع: $e')),
                );
              }
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء حذف المنتج: $e')),
      );
    } finally {
      if (mounted) setState(() => _productActionInProgress = false);
    }
  }

  void _confirmMoveToDamaged(
    String productId,
    Map<String, dynamic> product,
  ) {
    final name = product['name']?.toString() ?? '';
    final qty = _productQuantity(product);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('نقل إلى منتجات تالفة'),
          content: Text(
            'سيتم نقل "$name" (الكمية: ${invoiceAmount(qty)}) إلى مجموعة '
            'منتجات تالفة وإزالته من المخزن.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                await _executeMoveToDamaged(productId, product);
              },
              child: Text(
                'نقل',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _executeMoveToDamaged(
    String productId,
    Map<String, dynamic> product,
  ) async {
    if (_productActionInProgress) return;
    setState(() => _productActionInProgress = true);

    final storedProduct = _productPayloadForStorage(productId, product);
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? changesBackup;
    String? damagedDocId;

    try {
      final productRef =
          FirebaseFirestore.instance.collection('products').doc(productId);
      final productSnap = await productRef.get();
      if (!productSnap.exists) {
        throw StateError('المنتج غير موجود في المخزن');
      }

      changesBackup = await _fetchProductChanges(productId);

      final damagedRef = await FirebaseFirestore.instance
          .collection(_damagedProductsCollection)
          .add({
        ...storedProduct,
        'sourceProductId': productId,
        'movedAt': FieldValue.serverTimestamp(),
        'quantityAtMove': _productQuantity(storedProduct),
      });
      damagedDocId = damagedRef.id;

      await _removeProductFromInventory(productId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم نقل المنتج إلى منتجات تالفة'),
          action: SnackBarAction(
            label: 'تراجع',
            onPressed: () async {
              try {
                if (damagedDocId != null) {
                  await FirebaseFirestore.instance
                      .collection(_damagedProductsCollection)
                      .doc(damagedDocId)
                      .delete();
                }
                await _restoreProductAfterUndo(
                  productId: productId,
                  product: storedProduct,
                  changes: changesBackup!,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم استرجاع المنتج للمخزن')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تعذر الاسترجاع: $e')),
                );
              }
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (damagedDocId != null) {
        try {
          await FirebaseFirestore.instance
              .collection(_damagedProductsCollection)
              .doc(damagedDocId)
              .delete();
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء النقل: $e')),
      );
    } finally {
      if (mounted) setState(() => _productActionInProgress = false);
    }
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

  void _handleDamagedLongPress(
    String damagedDocId,
    Map<String, dynamic> product,
  ) {
    if (!_isAdmin) {
      _showPermissionDeniedDialog();
      return;
    }
    if (_productActionInProgress) return;

    final name = product['name']?.toString() ?? '';
    showModalBottomSheet<void>(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
              child: Text(
                name.isEmpty ? 'منتج تالف' : name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.restore, color: Colors.green.shade700),
              title: const Text('إرجاع إلى المخزن'),
              subtitle: const Text('استعادة المنتج إلى قائمة المخزن'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmRestoreDamaged(damagedDocId, product);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('حذف من التالف'),
              subtitle: const Text('حذف السجل من منتجات تالفة فقط'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteDamagedRecord(damagedDocId, product);
              },
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _inventoryPayloadFromDamaged(
    Map<String, dynamic> damaged,
  ) {
    final data = Map<String, dynamic>.from(damaged);
    data.remove('movedAt');
    data.remove('quantityAtMove');
    data.remove('sourceProductId');
    return data;
  }

  void _confirmRestoreDamaged(
    String damagedDocId,
    Map<String, dynamic> product,
  ) {
    final name = product['name']?.toString() ?? '';
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('إرجاع إلى المخزن'),
        content: Text('هل تريد إرجاع "$name" إلى المخزن؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await _executeRestoreDamaged(damagedDocId, product);
            },
            child: Text(
              'إرجاع',
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeRestoreDamaged(
    String damagedDocId,
    Map<String, dynamic> product,
  ) async {
    if (_productActionInProgress) return;
    setState(() => _productActionInProgress = true);

    try {
      final sourceId = product['sourceProductId']?.toString() ??
          product['id']?.toString() ??
          '';
      final payload = _inventoryPayloadFromDamaged(product);

      if (sourceId.isNotEmpty) {
        final ref =
            FirebaseFirestore.instance.collection('products').doc(sourceId);
        final existing = await ref.get();
        if (existing.exists) {
          throw StateError('المنتج موجود بالفعل في المخزن');
        }
        payload['id'] = sourceId;
        await ref.set(payload);
      } else {
        final name = payload['name']?.toString() ?? '';
        if (name.isNotEmpty) {
          final dup = await FirebaseFirestore.instance
              .collection('products')
              .where('name', isEqualTo: name)
              .limit(1)
              .get();
          if (dup.docs.isNotEmpty) {
            throw StateError('يوجد منتج بنفس الاسم في المخزن');
          }
        }
        await FirebaseFirestore.instance.collection('products').add(payload);
      }

      await FirebaseFirestore.instance
          .collection(_damagedProductsCollection)
          .doc(damagedDocId)
          .delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرجاع المنتج إلى المخزن')),
      );
      setState(() => _filter = _ProductListFilter.all);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الإرجاع: $e')),
      );
    } finally {
      if (mounted) setState(() => _productActionInProgress = false);
    }
  }

  void _confirmDeleteDamagedRecord(
    String damagedDocId,
    Map<String, dynamic> product,
  ) {
    final name = product['name']?.toString() ?? '';
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('حذف من منتجات تالفة'),
        content: Text('حذف سجل "$name" من منتجات تالفة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await _executeDeleteDamagedRecord(damagedDocId, product);
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _executeDeleteDamagedRecord(
    String damagedDocId,
    Map<String, dynamic> product,
  ) async {
    if (_productActionInProgress) return;
    setState(() => _productActionInProgress = true);

    final backup = Map<String, dynamic>.from(product);
    try {
      await FirebaseFirestore.instance
          .collection(_damagedProductsCollection)
          .doc(damagedDocId)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم حذف السجل من منتجات تالفة'),
          action: SnackBarAction(
            label: 'تراجع',
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection(_damagedProductsCollection)
                    .doc(damagedDocId)
                    .set(backup);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تعذر الاسترجاع: $e')),
                );
              }
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ: $e')),
      );
    } finally {
      if (mounted) setState(() => _productActionInProgress = false);
    }
  }

  Widget _damagedTableDataRow({
    required int serial,
    required Map<String, dynamic> product,
    required String damagedDocId,
  }) {
    final qty = _damagedQuantity(product);
    final movedLabel = _formatMovedAt(product['movedAt']);
    final rowFill = serial.isOdd ? _tableRowFillA : _tableRowFillB;

    return Material(
      color: rowFill,
      child: InkWell(
        onLongPress: () => _handleDamagedLongPress(damagedDocId, product),
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
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    product['name']?.toString() ?? '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _tableNameTextStyle,
                  ),
                  if (movedLabel.isNotEmpty)
                    Text(
                      movedLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 8.sp,
                        color: Colors.orange.shade800,
                      ),
                    ),
                ],
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
                invoiceAmount(qty),
                textAlign: TextAlign.center,
                style: _tableCellTextStyle.copyWith(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.bold,
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

  Widget _buildDamagedProductsTable(List<QueryDocumentSnapshot> docs) {
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
                  return _damagedTableDataRow(
                    serial: index + 1,
                    product: product,
                    damagedDocId: doc.id,
                  );
                },
              ),
            ),
          ],
        ),
      ),
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
        onLongPress: () => _handleProductLongPress(productId, product),
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

  Widget _buildSearchField({required String hint}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.h, horizontal: 10.w),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black.withOpacity(0.7)),
          ),
          filled: true,
          fillColor: Colors.grey.withOpacity(0.2),
          labelText: hint,
          labelStyle: TextStyle(
            color: Colors.black.withOpacity(0.7),
            fontSize: 18,
          ),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black.withOpacity(0.7)),
          ),
          prefixIcon: const Icon(Icons.search),
        ),
        onChanged: (query) => setState(() => _searchQuery = query),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
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
            SizedBox(width: 8.w),
            _filterChip('منتجات تالفة', _ProductListFilter.damaged),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('products').snapshots(),
      builder: (context, snapshot) {
        if (_productActionInProgress) {
          return Center(
            child: CircularProgressIndicator(
              color: Colors.orange.withOpacity(0.8),
            ),
          );
        }
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

        final displayedProducts = snapshot.data!.docs.where((doc) {
          final product = doc.data() as Map<String, dynamic>;
          return _matchesSearch(product) && _matchesFilter(product);
        }).toList();

        if (displayedProducts.isEmpty) {
          return const Center(child: Text('لا توجد منتجات مطابقة'));
        }

        return _buildBorderedProductsTable(displayedProducts);
      },
    );
  }

  Widget _buildDamagedList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(_damagedProductsCollection)
          .snapshots(),
      builder: (context, snapshot) {
        if (_productActionInProgress) {
          return Center(
            child: CircularProgressIndicator(
              color: Colors.orange.withOpacity(0.8),
            ),
          );
        }
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
          return const Center(child: Text('لا توجد منتجات تالفة'));
        }

        final docs = snapshot.data!.docs.where((doc) {
          final product = doc.data() as Map<String, dynamic>;
          return _matchesSearch(product);
        }).toList();

        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTs = aData['movedAt'];
          final bTs = bData['movedAt'];
          if (aTs is Timestamp && bTs is Timestamp) {
            return bTs.compareTo(aTs);
          }
          return 0;
        });

        if (docs.isEmpty) {
          return const Center(child: Text('لا توجد منتجات تالفة مطابقة'));
        }

        return _buildDamagedProductsTable(docs);
      },
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
          _buildSearchField(
            hint: _showingDamaged ? 'ابحث في منتجات تالفة' : 'ابحث عن منتج',
          ),
          _buildFilterChips(),
          Expanded(
            child: _showingDamaged ? _buildDamagedList() : _buildProductsList(),
          ),
        ],
      ),
    );
  }
}