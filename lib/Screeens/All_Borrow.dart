import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../Services/FirebaseService.dart';
import '../models/Employee.dart';
import 'EmployeeBorrowDetails.dart';
import 'g_Nav.dart';
import 'home_page.dart';

class AllBorrow extends StatelessWidget {
  const AllBorrow({super.key});

  @override
  Widget build(BuildContext context) {
    final FirebaseService firebaseService = FirebaseService();
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => GNavPage()),
              (Route<dynamic> route) => false,
        );
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xffeeeced),
        appBar: AppBar(
          backgroundColor: const Color(0xffeeeced),
          title: Text(
            'السلف',
            style: TextStyle(
              fontSize: 22.sp, // Smaller font size
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: StreamBuilder<List<Employee>>(
          stream: firebaseService.getEmployees(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(
                  color: Colors.orange.withOpacity(0.7),
                ),
              );
            }
            if (snapshot.hasError) {
              return Center(child: Text('خطأ: ${snapshot.error}'));
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('لا يوجد موظفين بعد'));
            }
            final employees = snapshot.data!
                .where((employee) => employee.borrows.isNotEmpty)
                .toList();

            if (employees.isEmpty) {
              return const Center(child: Text('لا يوجد سلف بعد'));
            }
            return ListView.builder(
              itemCount: employees.length,
              itemBuilder: (context, index) {
                final employee = employees[index];
                final totalBorrowValue = employee.borrows.fold<double>(
                  0,
                      (sum, borrow) => sum + double.parse(borrow.value),
                );

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            EmployeeBorrowDetails(employee: employee),
                      ),
                    );
                  },
                  child: Card(
                    margin: EdgeInsets.all(8.w), // Smaller margin
                    child: Padding(
                      padding: EdgeInsets.all(5.w), // Smaller padding
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Text(
                              employee.name,
                              style: TextStyle(
                                fontSize: 14.sp, // Smaller font size
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(height: 8.h), // Smaller height
                          Center(
                            child: Text(
                              'مجموع السلف: $totalBorrowValue',
                              style: TextStyle(
                                fontSize: 12.sp, // Smaller font size
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}