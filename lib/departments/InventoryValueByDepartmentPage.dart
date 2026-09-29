import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../local_db/hive_init.dart';
import '../repositories/department_repository.dart';
import '../repositories/product_repository.dart';

class InventoryValueByDepartmentPage extends StatefulWidget {
  const InventoryValueByDepartmentPage({super.key});

  @override
  State<InventoryValueByDepartmentPage> createState() =>
      _InventoryValueByDepartmentPageState();
}

class _InventoryValueByDepartmentPageState
    extends State<InventoryValueByDepartmentPage> {
  final Map<String, bool> _selectedDepartments = {};
  double _totalValue = 0.0;

  void _calculateTotalValue() {
    var total = 0.0;
    final products = ProductRepository.instance.getAll();
    for (final department in _selectedDepartments.entries) {
      if (!department.value) continue;
      for (final product
          in products.where((item) => item.department == department.key)) {
        total += product.quantity * product.sellingPrice1;
      }
    }
    setState(() => _totalValue = total);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Ø¬Ø±Ø¯ Ø§Ù„Ù…Ø®Ø²Ù† Ø­Ø³Ø¨ Ø§Ù„Ø£Ù‚Ø³Ø§Ù…',
          style: TextStyle(fontSize: 20.sp, color: Colors.white),
        ),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: departmentsBox.listenable(),
              builder: (context, _, __) {
                final departments = DepartmentRepository.instance.getAll();
                if (departments.isEmpty) {
                  return const Center(
                    child: Text('Ù„Ø§ ØªÙˆØ¬Ø¯ Ø£Ù‚Ø³Ø§Ù… Ø¨Ø¹Ø¯.'),
                  );
                }
                return ListView.builder(
                  itemCount: departments.length,
                  itemBuilder: (context, index) {
                    final name = departments[index].name;
                    return CheckboxListTile(
                      title: Text(name, style: TextStyle(fontSize: 16.sp)),
                      value: _selectedDepartments[name] ?? false,
                      onChanged: (selected) {
                        setState(() {
                          _selectedDepartments[name] = selected ?? false;
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
              child: Text('Ø§Ø­Ø³Ø¨ Ø§Ù„Ø¥Ø¬Ù…Ø§Ù„ÙŠ',
                  style: TextStyle(fontSize: 18.sp)),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(10.w),
            child: Text(
              'Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ø³Ø¹Ø±: Ø¬Ù†ÙŠÙ‡ ${_totalValue.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
