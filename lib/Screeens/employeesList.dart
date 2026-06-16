import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/Employee.dart';
import 'EmployeeDetails.dart';

class EmployeeList extends StatefulWidget {
  @override
  _EmployeeListState createState() => _EmployeeListState();
}

class _EmployeeListState extends State<EmployeeList> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addEmployee(Employee employee) async {
    await _firestore.collection('employees').doc(employee.id).set(employee.toMap());
  }

  Future<void> _addEmployeeDialog(BuildContext context) async {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController nameController = TextEditingController();
    final TextEditingController salaryController = TextEditingController();
    final TextEditingController startDateController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black12.withOpacity(0.8),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 10.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'إضافة موظف جديد',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
                Form(
                  key: _formKey,
                  child: Container(
                    width: double.infinity,
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: Column(
                      children: [
                        Card(
                          margin: EdgeInsets.all(8.w),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: EdgeInsets.all(8.w),
                            child: TextFormField(
                              keyboardType: TextInputType.text,
                              controller: nameController,
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.person),
                                hintText: 'اسم الموظف',
                                border: InputBorder.none,
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'الرجاء إدخال اسم الموظف';
                                }
                                return null;
                              },
                              style: TextStyle(fontSize: 14.sp),
                            ),
                          ),
                        ),
                        Card(
                          margin: EdgeInsets.all(8.w),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: EdgeInsets.all(8.w),
                            child: TextFormField(
                              keyboardType: TextInputType.number,
                              controller: salaryController,
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.attach_money),
                                hintText: 'الراتب',
                                border: InputBorder.none,
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'الرجاء إدخال الراتب';
                                }
                                return null;
                              },
                              style: TextStyle(fontSize: 14.sp),
                            ),
                          ),
                        ),
                        Card(
                          margin: EdgeInsets.all(8.w),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: EdgeInsets.all(8.w),
                            child: TextFormField(
                              controller: startDateController,
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.calendar_month),
                                hintText: 'تاريخ بدء العمل',
                                border: InputBorder.none,
                              ),
                              readOnly: true,
                              onTap: () async {
                                DateTime? pickedDate = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2101),
                                  builder: (BuildContext context, Widget? child) {
                                    return Theme(
                                      data: ThemeData.dark().copyWith(
                                        colorScheme: ColorScheme.dark(
                                          primary: Colors.orange.withOpacity(0.8),
                                          onPrimary: Colors.white,
                                          surface: Colors.black.withOpacity(0.7),
                                          onSurface: Colors.white,
                                        ),
                                        dialogBackgroundColor: Colors.black12.withOpacity(0.8),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (pickedDate != null) {
                                  startDateController.text = pickedDate.toIso8601String().split('T')[0];
                                }
                              },
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'الرجاء إدخال تاريخ بدء العمل';
                                }
                                return null;
                              },
                              style: TextStyle(fontSize: 14.sp),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('إلغاء',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          // Fetch the latest order
                          final latestEmployee = await FirebaseFirestore
                              .instance
                              .collection('employees')
                              .orderBy('order', descending: true)
                              .limit(1)
                              .get();

                          int newOrder = 0;
                          if (latestEmployee.docs.isNotEmpty) {
                            newOrder = latestEmployee.docs.first['order'] + 1;
                          }

                          final newEmployee = Employee(
                            id: nameController.text, // Set ID to the employee's name
                            name: nameController.text,
                            salary: double.parse(salaryController.text),
                            startDate: DateTime.parse(startDateController.text),
                            borrows: [],
                            medicines: [],
                            attendance: [],
                            order: newOrder,
                          );
                          await addEmployee(newEmployee);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('تم إضافة الموظف بنجاح')),
                          );
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Text('حفظ',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editEmployeeDialog(
      BuildContext context, Employee employee) async {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController nameController =
    TextEditingController(text: employee.name);
    final TextEditingController salaryController =
    TextEditingController(text: employee.salary.toString());
    final TextEditingController startDateController =
    TextEditingController(text: employee.startDate.toIso8601String().split('T')[0]);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black12.withOpacity(0.8),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 10.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'تعديل اسم الموظف',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
                Form(
                  key: _formKey,
                  child: Container(
                    width: double.infinity,
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: Column(
                      children: [
                        Card(
                          margin: EdgeInsets.all(8.w),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: EdgeInsets.all(8.w),
                            child: TextFormField(
                              keyboardType: TextInputType.text,
                              controller: nameController,
                              decoration: const InputDecoration(
                                labelText: 'اسم الموظف',
                                border: OutlineInputBorder(),
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'الرجاء إدخال اسم الموظف';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                        Card(
                          margin: EdgeInsets.all(8.w),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: EdgeInsets.all(8.w),
                            child: TextFormField(
                              keyboardType: TextInputType.number,
                              controller: salaryController,
                              decoration: const InputDecoration(
                                labelText: 'الراتب',
                                border: OutlineInputBorder(),
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'الرجاء إدخال الراتب';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                        Card(
                          margin: EdgeInsets.all(8.w),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: EdgeInsets.all(8.w),
                            child: TextFormField(
                              controller: startDateController,
                              decoration: const InputDecoration(
                                labelText: 'تاريخ بدء العمل',
                                border: OutlineInputBorder(),
                              ),
                              readOnly: true,
                              onTap: () async {
                                DateTime? pickedDate = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2101),
                                );
                                if (pickedDate != null) {
                                  startDateController.text = pickedDate.toIso8601String().split('T')[0];
                                }
                              },
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'الرجاء إدخال تاريخ بدء العمل';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('إلغاء',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          await _firestore
                              .collection('employees')
                              .doc(employee.id)
                              .update({
                            'name': nameController.text,
                            'salary': double.parse(salaryController.text),
                            'startDate': DateTime.parse(startDateController.text),
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('تم تعديل اسم الموظف بنجاح')),
                          );
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Text('حفظ',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteEmployee(String employeeId) async {
    await _firestore.collection('employees').doc(employeeId).delete();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف الموظف بنجاح')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('الموظفين', style: TextStyle(color: Colors.white, fontSize: 20.sp)),
          backgroundColor: Colors.black.withOpacity(0.7),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('employees')
              .orderBy('order', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(
                  color: Colors.orange.withOpacity(0.8),
                ),
              );
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(fontSize: 18.sp)));
            } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                  child: Text('لا يوجد موظفين', style: TextStyle(fontSize: 18.sp)));
            } else {
              final employees = snapshot.data!.docs
                  .map((doc) => Employee.fromMap(
                  doc.data() as Map<String, dynamic>, doc.id))
                  .toList();
              return ListView.builder(
                itemCount: employees.length,
                itemBuilder: (context, index) {
                  return Card(
                    margin: EdgeInsets.all(8.w),
                    elevation: 2,
                    child: ListTile(
                      title: Text('${employees[index].name} - ${employees[index].salary} ريال', style: TextStyle(fontSize: 16.sp)),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EmployeeDetails(employee: employees[index]),
                          ),
                        );
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit),
                            onPressed: () =>
                                _editEmployeeDialog(context, employees[index]),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete),
                            onPressed: () => _deleteEmployee(employees[index].id),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _addEmployeeDialog(context),
          child: Icon(Icons.add, size: 24.sp),
          backgroundColor: Colors.orange.withOpacity(0.8),
        ),
      );
  }
}