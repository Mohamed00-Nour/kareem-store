import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../models/Employee.dart';

class EmployeeAttendanceDetails extends StatefulWidget {
  final Employee employee;

  const EmployeeAttendanceDetails({super.key, required this.employee});

  @override
  _EmployeeAttendanceDetailsState createState() =>
      _EmployeeAttendanceDetailsState();
}

class _EmployeeAttendanceDetailsState extends State<EmployeeAttendanceDetails> {
  late Stream<List<Attendance>> _attendanceStream;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _attendanceStream = _fetchAttendance();
  }

  Stream<List<Attendance>> _fetchAttendance() {
    DateTime startOfPeriod = DateTime(_selectedYear, _selectedMonth - 1, 28);
    DateTime endOfPeriod = DateTime(_selectedYear, _selectedMonth, 27);

    return FirebaseFirestore.instance
        .collection('employees')
        .doc(widget.employee.id)
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data();
      if (data != null && data.containsKey('attendance')) {
        return (data['attendance'] as List)
            .map((attendance) => Attendance.fromMap(attendance))
            .where((attendance) =>
                attendance.dateTime.isAfter(startOfPeriod) &&
                attendance.dateTime.isBefore(endOfPeriod))
            .toList()
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
      } else {
        return [];
      }
    });
  }

  void _selectMonth(int month) {
    setState(() {
      _selectedMonth = month;
      _attendanceStream = _fetchAttendance();
    });
  }

  void _selectYear(int year) {
    setState(() {
      _selectedYear = year;
      _attendanceStream = _fetchAttendance();
    });
  }

  double _calculateSalaryDeduction(int totalDays, int absentDays) {
    double dailySalary = widget.employee.salary / 30;
    double deduction = dailySalary * absentDays;
    return deduction;
  }

  int _calculateAbsentDays(List<Attendance> attendanceRecords, DateTime employeeStartWork) {
    DateTime currentDate = DateTime.now();
    DateTime monthStart = DateTime(currentDate.year, currentDate.month - 1, 28).isBefore(employeeStartWork) ? employeeStartWork : DateTime(currentDate.year, currentDate.month - 1, 28);
    int totalDays = min(currentDate.difference(monthStart).inDays + 1, 30);
    int attendanceDays = attendanceRecords.length;
    int absentDays = totalDays - attendanceDays;

    return absentDays;
  }

  double _calculateCumulativeSalary(double salary, int attendanceDays) {
    attendanceDays = min(attendanceDays, 30);
    return (salary / 30) * attendanceDays;
  }

  String getArabicDayName(String dayName) {
    switch (dayName) {
      case 'Monday':
        return 'الإثنين';
      case 'Tuesday':
        return 'الثلاثاء';
      case 'Wednesday':
        return 'الأربعاء';
      case 'Thursday':
        return 'الخميس';
      case 'Friday':
        return 'الجمعة';
      case 'Saturday':
        return 'السبت';
      case 'Sunday':
        return 'الأحد';
      default:
        return dayName;
    }
  }

  Future<void> _editAttendance(Attendance attendance) async {
    TextEditingController attendHourController =
    TextEditingController(text: attendance.attendHour);
    TextEditingController leaveHourController =
    TextEditingController(text: attendance.leaveHour);
    TextEditingController responsibleController =
    TextEditingController(text: attendance.responsible);

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('تعديل الحضور'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: attendHourController,
                decoration: InputDecoration(labelText: 'ساعة الحضور'),
              ),
              TextField(
                controller: leaveHourController,
                decoration: InputDecoration(labelText: 'ساعة الإنصراف'),
              ),
              TextField(
                controller: responsibleController,
                decoration: InputDecoration(labelText: 'المسؤول'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إلغاء'),
            ),
            TextButton(
              onPressed: () async {
                // Save changes
                Navigator.of(context).pop();
              },
              child: Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAttendance(Attendance attendance) async {
    try {
      if (attendance.id.isNotEmpty) {
        final employeeDoc = FirebaseFirestore.instance
            .collection('employees')
            .doc(widget.employee.id);
        final snapshot = await employeeDoc.get();
        final data = snapshot.data();

        if (data != null && data.containsKey('attendance')) {
          final attendanceList =
          List<Map<String, dynamic>>.from(data['attendance']);
          attendanceList.removeWhere((item) => item['id'] == attendance.id);

          await employeeDoc.update({'attendance': attendanceList});

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حذف الحضور بنجاح')),
          );
        } else {
          print('Error: Attendance data not found');
        }
      } else {
        print('Error: Attendance ID is empty');
      }
    } catch (error) {
      print('Error deleting document: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ أثناء حذف الحضور')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    TextStyle headTableTextStyle = TextStyle(
      fontSize: 15.sp,
      fontWeight: FontWeight.bold,
      color: Colors.black.withOpacity(0.7),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.employee.name,
          style: TextStyle(fontSize: 18.sp),
        ),
        actions: [
          DropdownButton<int>(
            value: _selectedMonth,
            items: List.generate(12, (index) => index + 1)
                .map((month) => DropdownMenuItem(
                      value: month,
                      child: Text(DateFormat.MMMM().format(DateTime(0, month))),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                _selectMonth(value);
              }
            },
          ),
          DropdownButton<int>(
            value: _selectedYear,
            items: List.generate(50, (index) => DateTime.now().year - 25 + index)
                .map((year) => DropdownMenuItem(
                      value: year,
                      child: Text(year.toString()),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                _selectYear(value);
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(5.w),
        child: SingleChildScrollView(
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: 10.h),
                StreamBuilder<List<Attendance>>(
                  stream: _attendanceStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return CircularProgressIndicator(
                        color: Colors.black.withOpacity(0.7),
                      );
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Text(
                        'لا يوجد سجل حضور وإنصراف',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.black.withOpacity(0.7),
                        ),
                      );
                    } else {
                      final attendanceRecords = snapshot.data!;
                      DateTime currentDate = DateTime.now();
                      DateTime lastMonth28 =
                      DateTime(currentDate.year, currentDate.month - 1, 28);
                      int totalDays = min(
                          currentDate.difference(lastMonth28).inDays + 1, 30);
                      int absentDays = _calculateAbsentDays(attendanceRecords , widget.employee.startDate);
                      double salaryDeduction =
                      _calculateSalaryDeduction(totalDays, absentDays);
                      double remainingSalary = _calculateCumulativeSalary(
                          widget.employee.salary, attendanceRecords.length);

                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Column(
                              //   children: [
                              //     Text('الراتب حتى الآن', style: headTableTextStyle),
                              //     Text(remainingSalary.toStringAsFixed(2)),
                              //   ],
                              // ),
                              Column(
                                children: [
                                  Text('أيام الحضور', style: headTableTextStyle),
                                  Text(attendanceRecords.length.toString()),
                                ],
                              ),
                              Column(
                                children: [
                                  Text('أيام الغياب', style: headTableTextStyle),
                                  Text(absentDays.toString()),
                                ],
                              ),
                              Column(
                                children: [
                                  Text('الخصم', style: headTableTextStyle),
                                  Text(salaryDeduction.toStringAsFixed(2)),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 10.h),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: [
                                DataColumn(label: Text('التاريخ', style: headTableTextStyle)),
                                DataColumn(label: Text('ساعة الحضور', style: headTableTextStyle)),
                                DataColumn(label: Text('ساعة الإنصراف', style: headTableTextStyle)),
                                DataColumn(label: Text('المسؤول', style: headTableTextStyle)),
                              ],
                              rows: attendanceRecords.map((attendance) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(DateFormat('yyyy-MM-dd').format(attendance.dateTime))),
                                    DataCell(Text(attendance.attendHour)),
                                    DataCell(Text(attendance.leaveHour)),
                                    DataCell(Text(attendance.responsible)),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                          Divider(color: Colors.green, thickness: 2),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}