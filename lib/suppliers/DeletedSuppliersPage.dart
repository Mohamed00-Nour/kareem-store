import 'package:flutter/material.dart';

import '../repositories/supplier_repository.dart';

class DeletedSuppliersPage extends StatelessWidget {
  final Set<String> deletedSuppliers;
  final Function(String) onRestoreSupplier;

  const DeletedSuppliersPage({
    Key? key,
    required this.deletedSuppliers,
    required this.onRestoreSupplier,
  }) : super(key: key);

  String _getSupplierName(String supplierId) =>
      SupplierRepository.instance.getById(supplierId)?.name ?? 'Unknown';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        title: const Text(
          'الموردين المحذوفين',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView.builder(
        itemCount: deletedSuppliers.length,
        itemBuilder: (context, index) {
          final supplierId = deletedSuppliers.elementAt(index);
          return Card(
            elevation: 2,
            color: Colors.orange.withOpacity(0.7),
            margin: const EdgeInsets.all(10.0),
            child: ListTile(
              title: Center(
                  child: Text('اسم المورد: ${_getSupplierName(supplierId)}')),
              trailing: IconButton(
                icon: const Icon(Icons.restore, color: Colors.white),
                onPressed: () {
                  _showRestoreConfirmationDialog(context, supplierId);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _showRestoreConfirmationDialog(BuildContext context, String supplierId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: const Text('هل تريد استعادة هذا المورد إلى القائمة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لا'),
          ),
          TextButton(
            onPressed: () {
              onRestoreSupplier(supplierId);
              Navigator.pop(context);
            },
            child: const Text('نعم'),
          ),
        ],
      ),
    );
  }
}
