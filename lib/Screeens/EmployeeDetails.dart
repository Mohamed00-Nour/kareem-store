import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/Employee.dart';
import 'EmployeeAttendanceDetails.dart';
import 'EmployeeBorrowDetails.dart';
import 'EmployeeMedicineDetails.dart';
import '../Widgets/main-cards.dart'; // Import the CardWidget

class EmployeeDetails extends StatelessWidget {
  final Employee employee;

  const EmployeeDetails({super.key, required this.employee});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(employee.name, style: TextStyle(fontSize: 20.sp)),
        ),
        body: Padding(
          padding: EdgeInsets.all(10.w),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: CardWidget(
                      imagePath: 'assets/images/checklist.png',
                      text: 'الحضور والإنصراف',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EmployeeAttendanceDetails(employee: employee),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: CardWidget(
                      imagePath: 'assets/images/money.png',
                      text: 'السلف',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EmployeeBorrowDetails(employee: employee),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: 5.h),
              CardWidget(
                imagePath: 'assets/images/medicine.png',
                text: 'العلاج',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EmployeeMedicineDetails(employee: employee),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
  }
}