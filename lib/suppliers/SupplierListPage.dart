import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'DeletedSuppliersPage.dart';
import 'SupplierInvoicesPage.dart';

class SupplierListPage extends StatefulWidget {
  const SupplierListPage({Key? key}) : super(key: key);

  @override
  _SupplierListPageState createState() => _SupplierListPageState();
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
                  borderSide:
                      BorderSide(color: Colors.black.withOpacity(0.7)),
                ),
                filled: true,
                fillColor: Colors.grey.withOpacity(0.1),
                labelText: 'ابحث عن مورد',
                labelStyle: TextStyle(
                  color: Colors.black.withOpacity(0.7),
                  fontSize: 18,
                ),
                border: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: Colors.black.withOpacity(0.7)),
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
                    .where((s) =>
                        !_deletedSuppliersBox!.containsKey(s.id))
                    .toList();

                return ListView.builder(
                  itemCount: visibleSuppliers.length,
                  itemBuilder: (context, index) {
                    final supplier = visibleSuppliers[index];
                    final balance = (supplier['totalBalance'] ?? 0.0)
                        .toDouble();
                    return Card(
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.7),
                      margin: const EdgeInsets.all(10.0),
                      child: ListTile(
                        title: Center(child: Text(supplier['name'])),
                        subtitle: Center(
                          child: Text(
                              'الرصيد: ${balance.toStringAsFixed(2)}'),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SupplierInvoicesPage(
                                  supplierId: supplier.id),
                            ),
                          );
                        },
                        onLongPress: () {
                          _showDeleteConfirmationDialog(supplier.id);
                        },
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
