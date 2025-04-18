import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/Employee.dart';

class EmployeeBorrowDetails extends StatefulWidget {
  final Employee employee;

  const EmployeeBorrowDetails({super.key, required this.employee});

  @override
  _EmployeeBorrowDetailsState createState() => _EmployeeBorrowDetailsState();
}

class _EmployeeBorrowDetailsState extends State<EmployeeBorrowDetails> {
  final _formKey = GlobalKey<FormState>();
  final _dateController = TextEditingController();
  final _responsibleController = TextEditingController();
  final _valueController = TextEditingController();

  // Define the _borrowsStream
  Stream<List<Borrow>> get _borrowsStream {
    return FirebaseFirestore.instance
        .collection('employees')
        .doc(widget.employee.id)
        .snapshots()
        .map((snapshot) {
      final List<dynamic> borrowsData = snapshot.data()?['borrows'] ?? [];
      return borrowsData.map((data) => Borrow.fromMap(data)).toList();
    });
  }

  @override
  void dispose() {
    _dateController.dispose();
    _responsibleController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  void _disposeFormFields() {
    _dateController.clear();
    _responsibleController.clear();
    _valueController.clear();
  }

  Future<void> _selectDate(BuildContext context) async {
    final int currentYear = DateTime.now().year;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(currentYear, 1, 1),
      lastDate: DateTime(currentYear, 12, 31),
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

  Future<void> _addBorrow() async {
    if (_formKey.currentState!.validate()) {
      final borrow = Borrow(
        id: FirebaseFirestore.instance.collection('employees').doc().id,
        // Generate unique id
        employeeId: widget.employee.id,
        employeeName: widget.employee.name,
        date: _dateController.text,
        responsible: _responsibleController.text,
        value: _valueController.text,
      );

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employee.id)
          .update({
        'borrows': FieldValue.arrayUnion([borrow.toMap()])
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إضافة السلفة بنجاح')),
      );
      _formKey.currentState!.reset();
      _disposeFormFields();
      Navigator.of(context).pop();
    }
  }

  void _showAddBorrowDialog() {
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
                  'إضافة سلفة',
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
                          margin: EdgeInsets.all(8.w),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: EdgeInsets.all(8.w),
                            child: TextFormField(
                              keyboardType: TextInputType.text,
                              controller: _responsibleController,
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.perm_identity_outlined),
                                hintText: 'أدخل إسم المسؤول',
                                border: InputBorder.none,
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'من فضلك أدخل إسم المسؤول';
                                }
                                final validRegExp =
                                RegExp(r'^[a-zA-Z\u0600-\u06FF\s]+$');
                                if (!validRegExp.hasMatch(value)) {
                                  return 'من فضلك أدخل حروف عربية أو إنجليزية فقط ومسافات';
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
                              controller: _valueController,
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.attach_money_outlined),
                                labelStyle: TextStyle(
                                  color: Colors.black,
                                ),
                                hintText: 'أدخل المبلغ',
                                border: InputBorder.none,
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'من فضلك أدخل ا��مبلغ';
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
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: _addBorrow,
                      child: const Text(
                        'حفظ',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
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

  void _editBorrow(Borrow borrow) {
    _dateController.text = borrow.date;
    _responsibleController.text = borrow.responsible;
    _valueController.text = borrow.value;

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
                  'تعديل سلفة',
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
                          margin: EdgeInsets.all(8.w),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: EdgeInsets.all(8.w),
                            child: TextFormField(
                              keyboardType: TextInputType.text,
                              controller: _responsibleController,
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.perm_identity_outlined),
                                hintText: 'أدخل إسم المسؤول',
                                border: InputBorder.none,
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'من فضلك أدخل إسم المسؤول';
                                }
                                final validRegExp =
                                RegExp(r'^[a-zA-Z\u0600-\u06FF\s]+$');
                                if (!validRegExp.hasMatch(value)) {
                                  return 'من فضلك أدخل حروف عربية أو إنجليزية فقط ومسافات';
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
                              controller: _valueController,
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.attach_money_outlined),
                                labelStyle: TextStyle(
                                  color: Colors.black,
                                ),
                                hintText: 'أدخل المبلغ',
                                border: InputBorder.none,
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'من فضلك أدخل المبلغ';
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
                          style: TextStyle(color: Colors.white)),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          final updatedBorrow = Borrow(
                            id: borrow.id,
                            employeeId: widget.employee.id,
                            employeeName: widget.employee.name,
                            date: _dateController.text,
                            responsible: _responsibleController.text,
                            value: _valueController.text,
                          );

                          await FirebaseFirestore.instance
                              .collection('employees')
                              .doc(widget.employee.id)
                              .update({
                            'borrows': FieldValue.arrayRemove([borrow.toMap()]),
                          });

                          await FirebaseFirestore.instance
                              .collection('employees')
                              .doc(widget.employee.id)
                              .update({
                            'borrows':
                            FieldValue.arrayUnion([updatedBorrow.toMap()]),
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('تم تعديل السلفة بنجاح')),
                          );

                          _formKey.currentState!.reset();
                          _disposeFormFields();
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Text('حفظ',
                          style: TextStyle(color: Colors.white)),
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

  void _deleteBorrow(Borrow borrow) async {
    await FirebaseFirestore.instance
        .collection('employees')
        .doc(widget.employee.id)
        .update({
      'borrows': FieldValue.arrayRemove([borrow.toMap()])
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف السلفة بنجاح')),
    );
  }

  @override
  Widget build(BuildContext context) {
    TextStyle headTableTextStyle = TextStyle(
      fontSize: 18.sp,
      fontWeight: FontWeight.bold,
      color: Colors.black.withOpacity(0.7),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.employee.name),
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
                StreamBuilder<List<Borrow>>(
                  stream: _borrowsStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return CircularProgressIndicator(
                        color: Colors.orange.withOpacity(0.8),
                      );
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Text(
                          'لا يوجد سلف',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.black.withOpacity(0.7),
                          ),
                        ),
                      );
                    } else {
                      final borrows = snapshot.data!;
                      final totalValue = borrows.fold<double>(
                        0,
                            (sum, detail) => sum + double.parse(detail.value),
                      );

                      return Column(
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: [
                                DataColumn(
                                  label: Text(
                                    'التاريخ',
                                    style: headTableTextStyle,
                                  ),
                                ),
                                DataColumn(
                                    label: Text('المسئول',
                                        style: headTableTextStyle)),
                                DataColumn(
                                    label: Text('المبلغ',
                                        style: headTableTextStyle)),
                                DataColumn(
                                    label: Text('تعديل أو حذف',
                                        style: headTableTextStyle)),
                              ],
                              rows: borrows.map<DataRow>((detail) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(detail.date, style: TextStyle(fontSize: 14.sp),)),
                                    DataCell(Text(detail.responsible,style: TextStyle(fontSize: 14.sp),)),
                                    DataCell(Text(detail.value,style: TextStyle(fontSize: 14.sp),)),
                                    DataCell(
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: Icon(Icons.edit ,size: 18.sp,),
                                            onPressed: () =>
                                                _editBorrow(detail),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.delete , size: 18.sp,),
                                            onPressed: () =>
                                                _deleteBorrow(detail),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                          SizedBox(height: 20.h),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '$totalValue :مجموع السلف ',
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.black.withOpacity(0.7),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),
                SizedBox(height: 10.h),
                Center(
                  child: ElevatedButton(
                    onPressed: _showAddBorrowDialog,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      backgroundColor: Colors.black.withOpacity(0.7),
                    ),
                    child: Text(
                      'إضافة',
                      style: TextStyle(
                        fontSize: 18.sp,
                        color: Colors.white.withOpacity(1),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}