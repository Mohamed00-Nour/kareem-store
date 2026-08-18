import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../repositories/product_repository.dart';

class InventoryValueByDepartmentPage extends StatefulWidget {
  @override
  _InventoryValueByDepartmentPageState createState() => _InventoryValueByDepartmentPageState();
}

class _InventoryValueByDepartmentPageState extends State<InventoryValueByDepartmentPage> {
  final Map<String, bool> _selectedDepartments = {};
  double _totalValue = 0.0;

  void _calculateTotalValue() {

    double totalValue = 0.0;
    final allProducts = ProductRepository.instance.getAll();

    for (var department in _selectedDepartments.entries) {
      if (department.value) {
        final deptProducts = allProducts.where((p) => p.department == department.key);
        for (var product in deptProducts) {
          totalValue += product.quantity * product.sellingPrice1;
        }
      }
    }

    setState(() {
      _totalValue = totalValue;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('جرد المخزن حسب الأقسام', style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('departments').snapshots(),
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
                  return Center(child: Text('لا توجد أقسام بعد.'));
                }

                final departments = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: departments.length,
                  itemBuilder: (context, index) {
                    final department = departments[index].data() as Map<String, dynamic>;
                    final departmentName = department['name'];

                    return CheckboxListTile(
                      title: Text(departmentName, style: TextStyle(fontSize: 16.sp)),
                      value: _selectedDepartments[departmentName] ?? false,
                      onChanged: (isSelected) {
                        setState(() {
                          _selectedDepartments[departmentName] = isSelected ?? false;
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(10.w),
            child: ElevatedButton(
              onPressed: _calculateTotalValue,
              child: Text('احسب الإجمالي', style: TextStyle(fontSize: 18.sp)),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(10.w),
            child: Text(
              'إجمالي السعر: جنيه ${_totalValue.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }
}