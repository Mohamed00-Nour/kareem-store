import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/Employee.dart';
import '../Widgets/AddMedicine.dart';

class EmployeeMedicineDetails extends StatefulWidget {
  final Employee employee;

  const EmployeeMedicineDetails({super.key, required this.employee});

  @override
  _EmployeeMedicineDetailsState createState() =>
      _EmployeeMedicineDetailsState();
}

class _EmployeeMedicineDetailsState extends State<EmployeeMedicineDetails> {
  late Stream<List<Medicine>> _medicinesStream;
  final TextEditingController _dateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _medicinesStream = _fetchMedicines();
  }

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }

  Stream<List<Medicine>> _fetchMedicines() {
    return FirebaseFirestore.instance
        .collection('employees')
        .doc(widget.employee.id)
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data();
      if (data != null && data.containsKey('medicines')) {
        return (data['medicines'] as List)
            .map((medicine) => Medicine.fromMap(medicine))
            .toList();
      } else {
        return [];
      }
    });
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
            buttonTheme:
                const ButtonThemeData(textTheme: ButtonTextTheme.primary),
            textSelectionTheme:
                const TextSelectionThemeData(cursorColor: Colors.black),
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

  void _editMedicine(Medicine medicine) {
    _showEditDialog(medicine);
  }

  void _showEditDialog(Medicine medicine) {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController dateController =
        TextEditingController(text: medicine.date);
    final TextEditingController valueController =
        TextEditingController(text: medicine.value);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.black12.withOpacity(0.8),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 10.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'تعديل سجل العلاج',
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
                              controller: dateController,
                              decoration: const InputDecoration(
                                labelText: 'التاريخ',
                                border: OutlineInputBorder(),
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'الرجاء إدخال التاريخ';
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
                              controller: valueController,
                              decoration: const InputDecoration(
                                labelText: 'المبلغ',
                                border: OutlineInputBorder(),
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'الرجاء إدخال المبلغ';
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
                          await FirebaseFirestore.instance
                              .collection('employees')
                              .doc(widget.employee.id)
                              .update({
                            'medicines':
                                FieldValue.arrayRemove([medicine.toMap()])
                          });

                          final updatedMedicine = Medicine(
                            id: medicine.id,
                            employeeId: widget.employee.id,
                            employeeName: widget.employee.name,
                            date: dateController.text,
                            responsible: widget.employee.name,
                            value: valueController.text,
                          );

                          await FirebaseFirestore.instance
                              .collection('employees')
                              .doc(widget.employee.id)
                              .update({
                            'medicines':
                                FieldValue.arrayUnion([updatedMedicine.toMap()])
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('تم تعديل سجل العلاج بنجاح')),
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

  void _deleteMedicine(Medicine medicine) async {
    await FirebaseFirestore.instance
        .collection('employees')
        .doc(widget.employee.id)
        .update({
      'medicines': FieldValue.arrayRemove([medicine.toMap()])
    });

    // Update the local state
    setState(() {
      widget.employee.medicines.removeWhere((m) => m.id == medicine.id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف سجل العلاج بنجاح')),
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
        padding: EdgeInsets.all(10.w),
        child: SingleChildScrollView(
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: 10.h),
                StreamBuilder<List<Medicine>>(
                  stream: _medicinesStream,
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
                          'لا يوجد علاج',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.black.withOpacity(0.7),
                          ),
                        ),
                      );
                    } else {
                      final medicines = snapshot.data!;
                      final totalValue = medicines.fold<double>(
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
                              rows: medicines.map<DataRow>((detail) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(
                                      detail.date,
                                      style: TextStyle(fontSize: 14.sp),
                                    )),
                                    DataCell(Text(
                                      detail.responsible,
                                      style: TextStyle(fontSize: 14.sp),
                                    )),
                                    DataCell(Text(
                                      detail.value,
                                      style: TextStyle(fontSize: 14.sp),
                                    )),
                                    DataCell(
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              Icons.edit,
                                              size: 18.sp,
                                            ),
                                            onPressed: () =>
                                                _editMedicine(detail),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.delete,
                                              size: 18.sp,
                                            ),
                                            onPressed: () =>
                                                _deleteMedicine(detail),
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
                              '$totalValue :مجموع العلاج ',
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
                Container(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: AddMedicine(employee: widget.employee),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
