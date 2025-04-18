import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/Employee.dart';
import 'EmployeeAttendanceDetails.dart';

class AttendanceWidget extends StatefulWidget {
  const AttendanceWidget({super.key});

  @override
  _AttendanceWidgetState createState() => _AttendanceWidgetState();
}

class _AttendanceWidgetState extends State<AttendanceWidget> {
  final _formKey = GlobalKey<FormState>();
  final _dateController = TextEditingController();
  final _attendHourController = TextEditingController();
  final _leaveHourController = TextEditingController();
  final _responsibleController = TextEditingController();
  final Map<String, bool> _selectedEmployees = {};

  @override
  void dispose() {
    _dateController.dispose();
    _attendHourController.dispose();
    _leaveHourController.dispose();
    _responsibleController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Colors.orange.withOpacity(0.7),
            hintColor: Colors.orange.withOpacity(0.7),
            colorScheme: const ColorScheme.light(primary: Colors.orange),
            buttonTheme: const ButtonThemeData(textTheme: ButtonTextTheme.primary),
            textSelectionTheme: TextSelectionThemeData(cursorColor: Colors.black.withOpacity(0.7)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dateController.text = "${picked.toLocal()}".split(' ')[0];
      });
    }
  }
  Future<void> _selectTime(BuildContext context, TextEditingController controller) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Colors.orange.withOpacity(0.7),
            hintColor: Colors.orange.withOpacity(0.7),
            colorScheme: const ColorScheme.light(primary: Colors.orange),
            buttonTheme: const ButtonThemeData(textTheme: ButtonTextTheme.primary),
            textSelectionTheme: TextSelectionThemeData(cursorColor: Colors.black.withOpacity(0.7)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        controller.text = picked.format(context);
      });
    }
  }
  String _getDayName(DateTime date) {
    return ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][date.weekday - 1];
  }

  Future<void> _addAttendance() async {
    if (_formKey.currentState!.validate()) {
      final selectedDate = DateTime.parse(_dateController.text);
      final dayName = _getDayName(selectedDate);
      final attendHour = _attendHourController.text.isEmpty ? '' : _attendHourController.text;
      final leaveHour = _leaveHourController.text.isEmpty ? '' : _leaveHourController.text;
      final responsible = _responsibleController.text;

      final selectedEmployees = _selectedEmployees.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toList();

      for (var employeeId in selectedEmployees) {
        final employeeDoc = await FirebaseFirestore.instance.collection('employees').doc(employeeId).get();
        final employeeName = employeeDoc.data()?['name'] ?? '';

        final attendance = Attendance(
          employeeId: employeeId,
          employeeName: employeeName,
          isPresent: true,
          id: FirebaseFirestore.instance.collection('employees').doc().id,
          dateTime: selectedDate,
          dayName: dayName,
          attendHour: attendHour,
          leaveHour: leaveHour,
          responsible: responsible,
        );

        await FirebaseFirestore.instance
            .collection('employees')
            .doc(employeeId)
            .update({
          'attendance': FieldValue.arrayUnion([attendance.toMap()])
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إضافة ��لحضور بنجاح')),
      );

      _formKey.currentState!.reset();
      _dateController.clear();
      _attendHourController.clear();
      _leaveHourController.clear();
      _responsibleController.clear();
      setState(() {
        _selectedEmployees.clear();
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الحضور والإنصراف'),
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(vertical: 15.h, horizontal: 25.w),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Card(
                margin: EdgeInsets.all(5.w),
                elevation: 2,
                color: Colors.orange.withOpacity(0.8),
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: TextFormField(
                    controller: _dateController,
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.calendar_month),
                      hintText: 'أدخل التاريخ',
                      border: InputBorder.none,
                    ),
                    textAlign: TextAlign.center,
                    readOnly: true,
                    onTap: () => _selectDate(context),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'من فضلك أدخل التاريخ';
                      }
                      return null;
                    },
                    style: TextStyle(fontSize: 14.sp),
                  ),
                ),
              ),
              Card(
                margin: EdgeInsets.all(5.w),
                elevation: 2,
                color: Colors.orange.withOpacity(0.8),
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: TextFormField(
                    controller: _attendHourController,
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.access_time),
                      hintText: 'ساعة الحضور',
                      border: InputBorder.none,
                    ),
                    textAlign: TextAlign.center,
                    readOnly: true,
                    onTap: () => _selectTime(context, _attendHourController),
                    style: TextStyle(fontSize: 14.sp),
                  ),
                ),
              ),
              Card(
                margin: EdgeInsets.all(5.w),
                elevation: 2,
                color: Colors.orange.withOpacity(0.8),
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: TextFormField(
                    controller: _leaveHourController,
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.access_time),
                      hintText: 'ساعة الإنصراف',
                      border: InputBorder.none,
                    ),
                    textAlign: TextAlign.center,
                    readOnly: true,
                    onTap: () => _selectTime(context, _leaveHourController),
                    style: TextStyle(fontSize: 14.sp),
                  ),
                ),
              ),
              Card(
                margin: EdgeInsets.all(3.w),
                elevation: 2,
                color: Colors.orange.withOpacity(0.8),
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: TextFormField(
                    controller: _responsibleController,
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.person),
                      hintText: 'أدخل اسم المسؤول',
                      border: InputBorder.none,
                    ),
                    textAlign: TextAlign.center,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'من فضلك أدخل اسم المسؤول';
                      }
                      return null;
                    },
                    style: TextStyle(fontSize: 14.sp),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Employee>>(
                  stream: FirebaseFirestore.instance
                      .collection('employees')
                      .snapshots()
                      .map((snapshot) => snapshot.docs
                      .map((doc) => Employee.fromMap(doc.data(), doc.id))
                      .toList()),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator(
                        color: Colors.black.withOpacity(0.7),
                      ));
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(child: Text('لا يوجد موظفين'));
                    }

                    final employees = snapshot.data!;
                    return ListView.builder(
                      itemCount: employees.length,
                      itemBuilder: (context, index) {
                        final employee = employees[index];
                        return Card(
                          margin: EdgeInsets.all(10.w),
                          child: ListTile(
                            leading: Checkbox(
                              value: _selectedEmployees[employee.id] ?? false,
                              onChanged: (bool? value) {
                                setState(() {
                                  _selectedEmployees[employee.id] = value ?? false;
                                });
                              },
                            ),
                            title: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EmployeeAttendanceDetails(employee: employee),
                                  ),
                                );
                              },
                              child: Text(employee.name, style: TextStyle(fontSize: 14.sp)),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  ElevatedButton(
                    onPressed: _addAttendance,
                    style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        backgroundColor: Colors.black.withOpacity(0.7)),
                    child: Text(
                      'تسجيل الحضور/الإنصراف',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.white.withOpacity(1),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}