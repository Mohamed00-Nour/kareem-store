import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../Services/party_rename_service.dart';
import '../Widgets/app_responsive.dart';
import 'DeletedSuppliersPage.dart';
import 'SupplierInvoicesPage.dart';

class SupplierListPage extends StatefulWidget {
  const SupplierListPage({Key? key}) : super(key: key);

  @override
  _SupplierListPageState createState() => _SupplierListPageState();
}

class _SupplierInfoCard extends StatelessWidget {
  final String name;
  final double balance;
  final String phone;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SupplierInfoCard({
    required this.name,
    required this.balance,
    required this.phone,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final balanceColor = balance > 0
        ? Colors.red.shade700
        : balance < 0
            ? Colors.green.shade700
            : Colors.black87;

    return Card(
      elevation: 3,
      color: Colors.orange.withOpacity(0.75),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.store_outlined,
                size: 32,
                color: Colors.black.withOpacity(0.65),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'الرصيد',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
              Text(
                balance.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: balanceColor,
                ),
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.phone,
                        size: 14, color: Colors.black.withOpacity(0.5)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        phone,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'اضغط للفواتير • اضغط مطولاً للخيارات',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.black.withOpacity(0.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierListPageState extends State<SupplierListPage> {
  String _searchQuery = '';
  Box<String>? _deletedSuppliersBox;

  @override
  void initState() {
    super.initState();
    _initializeHive();
  }

  Future<void> _initializeHive() async {
    final dir = await getApplicationDocumentsDirectory();
    Hive.init(dir.path);
    final box = await Hive.openBox<String>('deletedSuppliers');
    if (mounted) {
      setState(() {
        _deletedSuppliersBox = box;
      });
    }
  }

  void _showDeleteConfirmationDialog(String supplierId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل تريد حذف هذا المورد من القائمة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لا'),
          ),
          TextButton(
            onPressed: () {
              _deletedSuppliersBox?.put(supplierId, supplierId);
              setState(() {});
              Navigator.pop(context);
            },
            child: const Text('نعم'),
          ),
        ],
      ),
    );
  }

  void _showFirebaseDeleteConfirmationDialog(
      String supplierId, String supplierName) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.red, size: 28),
              const SizedBox(width: 8),
              const Text(
                'حذف نهائي',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'سيتم حذف المورد بشكل نهائي من قاعدة البيانات ولا يمكن التراجع عن هذا الإجراء.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.store_outlined,
                        color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        supplierName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever, color: Colors.white),
              label: const Text('حذف نهائي',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700),
              onPressed: () async {
                Navigator.pop(ctx);
                await _deleteSupplierFromFirebase(supplierId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSupplierFromFirebase(String supplierId) async {
    try {
      await FirebaseFirestore.instance
          .collection('suppliers')
          .doc(supplierId)
          .delete();
      // Also remove from local hidden list if present
      _deletedSuppliersBox?.delete(supplierId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف المورد نهائياً من قاعدة البيانات'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحذف: $e')),
        );
      }
    }
  }

  void _showSupplierOptionsSheet(
      String supplierId, String currentName) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  currentName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('تغيير الاسم'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRenameSupplierDialog(supplierId, currentName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined,
                    color: Colors.orange),
                title: const Text('إخفاء من القائمة'),
                subtitle: const Text('يمكن الاسترجاع لاحقاً',
                    style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDeleteConfirmationDialog(supplierId);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text(
                  'حذف نهائي من قاعدة البيانات',
                  style: TextStyle(color: Colors.red),
                ),
                subtitle: const Text('لا يمكن التراجع عن هذا الإجراء',
                    style: TextStyle(fontSize: 11, color: Colors.red)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showFirebaseDeleteConfirmationDialog(
                      supplierId, currentName);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameSupplierDialog(String supplierId, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير اسم المورد'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'الاسم الجديد',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              Navigator.pop(dialogContext);
              if (newName.isEmpty || newName == currentName) return;
              _performSupplierRename(supplierId, newName);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _performSupplierRename(String supplierId, String newName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(
          color: Colors.black.withOpacity(0.7),
        ),
      ),
    );

    try {
      await PartyRenameService.renameSupplier(
        supplierId: supplierId,
        newName: newName,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تغيير اسم المورد إلى "$newName"')),
      );
      setState(() {});
    } on PartyRenameException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تغيير الاسم: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        title: const Text(
          'عرض الموردين',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: _deletedSuppliersBox == null
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DeletedSuppliersPage(
                          deletedSuppliers:
                              _deletedSuppliersBox!.values.toSet(),
                          onRestoreSupplier: (supplierId) {
                            _deletedSuppliersBox!.delete(supplierId);
                            setState(() {});
                          },
                        ),
                      ),
                    );
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            child: TextField(
              decoration: InputDecoration(
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.black.withOpacity(0.7)),
                ),
                filled: true,
                fillColor: Colors.grey.withOpacity(0.1),
                labelText: 'ابحث عن مورد',
                labelStyle: TextStyle(
                  color: Colors.black.withOpacity(0.7),
                  fontSize: 18,
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.black.withOpacity(0.7)),
                ),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (query) {
                setState(() {
                  _searchQuery = query;
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('suppliers')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || _deletedSuppliersBox == null) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: Colors.black.withOpacity(0.7),
                    ),
                  );
                }

                final allSuppliers = snapshot.data!.docs;
                final filteredSuppliers = _searchQuery.isEmpty
                    ? allSuppliers
                    : allSuppliers.where((supplier) {
                        final name =
                            supplier['name']?.toString().toLowerCase() ?? '';
                        return name.contains(_searchQuery.toLowerCase());
                      }).toList();
                final visibleSuppliers = filteredSuppliers
                    .where((s) => !_deletedSuppliersBox!.containsKey(s.id))
                    .toList();

                if (visibleSuppliers.isEmpty) {
                  return const Center(child: Text('لا يوجد موردين'));
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: AppResponsive.gridColumns(context),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.92,
                  ),
                  itemCount: visibleSuppliers.length,
                  itemBuilder: (context, index) {
                    final supplier = visibleSuppliers[index];
                    final data = supplier.data() as Map<String, dynamic>;
                    final name = data['name']?.toString() ?? supplier.id;
                    final balance = (data['totalBalance'] ?? 0.0).toDouble();
                    final phone = data['phone']?.toString() ?? '';

                    return _SupplierInfoCard(
                      name: name,
                      balance: balance,
                      phone: phone,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                SupplierInvoicesPage(supplierId: supplier.id),
                          ),
                        );
                      },
                      onLongPress: () {
                        _showSupplierOptionsSheet(supplier.id, name);
                      },
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
