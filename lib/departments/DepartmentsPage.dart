import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../local_db/hive_init.dart';
import '../repositories/department_repository.dart';
import '../Widgets/app_responsive.dart';
import 'InventoryValueByDepartmentPage.dart';
import 'DepartmentProductsPage.dart';

class DepartmentsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('الأقسام',
            style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (context) => InventoryValueByDepartmentPage()),
              );
            },
            child: Text(
              'جرد المخزن',
              style: TextStyle(fontSize: 16.sp, color: Colors.white),
            ),
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: departmentsBox.listenable(),
        builder: (context, box, _) {
          final localDepartments = DepartmentRepository.instance.getAll();

          if (localDepartments.isEmpty) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('departments').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: Colors.orange.withOpacity(0.8),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Text('No departments found.'));
                }
                final docs = snapshot.data!.docs;
                return _buildGrid(context, docs.map((d) => (d.data() as Map<String, dynamic>)['name']?.toString() ?? '').toList());
              },
            );
          }

          return _buildGrid(context, localDepartments.map((d) => d.name).toList());
        },
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<String> names) {
    return Padding(
      padding: EdgeInsets.all(10.w),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: AppResponsive.gridColumns(context),
          crossAxisSpacing: 10.w,
          mainAxisSpacing: 10.h,
        ),
        itemCount: names.length,
        itemBuilder: (context, index) {
          final name = names[index];
          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => DepartmentProductsPage(
                    departmentName: name,
                  ),
                ),
              );
            },
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/shopping-store_5542724.png',
                    height: 80.h,
                    width: 80.w,
                    fit: BoxFit.cover,
                  ),
                  SizedBox(height: 10.h),
                  Text(
                    name,
                    style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
