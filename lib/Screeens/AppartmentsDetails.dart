import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/Appartments.dart';

class AppartmentsDetails extends StatefulWidget {
  @override
  _AppartmentsDetailsState createState() => _AppartmentsDetailsState();
}

class _AppartmentsDetailsState extends State<AppartmentsDetails> {
  late Stream<List<Appartments>> _appartmentsStream;

  @override
  void initState() {
    super.initState();
    _appartmentsStream = _fetchAppartments();
  }

  Stream<List<Appartments>> _fetchAppartments() {
    return FirebaseFirestore.instance
        .collection('appartments')
        .orderBy('date', descending: false) // Order by date in ascending order
        .orderBy('time', descending: false) // Order by time in ascending order
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => Appartments.fromMap(doc.data() as Map<String, dynamic>))
        .toList());
  }

  void _editAppartment(Appartments appartment) {
    _showEditDialog(appartment);
  }

  void _showEditDialog(Appartments? appartment) {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController nameController =
    TextEditingController(text: appartment?.name ?? '');
    final TextEditingController dateController =
    TextEditingController(text: appartment?.date ?? '');
    final TextEditingController valueController =
    TextEditingController(text: appartment?.value ?? '');

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
            ),
            child: child!,
          );
        },
      );
      if (picked != null) {
        setState(() {
          dateController.text = "${picked.toLocal()}".split(' ')[0];
        });
      }
    }

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
                Text(
                  appartment == null ? 'إضافة مصاريف سكن' : 'تعديل مصاريف سكن',
                  style: TextStyle(color: Colors.white, fontSize: 18.sp),
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
                              controller: dateController,
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
                              controller: nameController,
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.perm_identity_outlined),
                                hintText: 'أدخل إسم المصاريف',
                                border: InputBorder.none,
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'من فضلك أدخل اسم المصاريف';
                                }
                                final validRegExp =
                                RegExp(r'^[a-zA-Z0-9\u0600-\u06FF\s]+$');
                                if (!validRegExp.hasMatch(value)) {
                                  return 'من فضلك أدخل حروف أو أرقام فقط';
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
                            padding: EdgeInsets.symmetric(
                                vertical: 8.h, horizontal: 0.w),
                            child: TextFormField(
                              keyboardType: TextInputType.number,
                              controller: valueController,
                              decoration: InputDecoration(
                                suffixIcon: const Icon(Icons.attach_money_outlined),
                                labelStyle: TextStyle(
                                  color: Colors.black.withOpacity(0.7),
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
                      child: Text('إلغاء',
                          style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          if (appartment == null) {
                            final newAppartment = Appartments(
                              id: FirebaseFirestore.instance
                                  .collection('appartments')
                                  .doc()
                                  .id, // Generate unique id
                              name: nameController.text,
                              date: dateController.text,
                              value: valueController.text,
                              time: Timestamp.now(), // Use Timestamp.now()
                            );
                            await FirebaseFirestore.instance
                                .collection('appartments')
                                .doc(newAppartment.id)
                                .set(newAppartment.toMap());
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('تم إضافة مصاريف للسكن بنجاح')),
                            );
                          } else {
                            await FirebaseFirestore.instance
                                .collection('appartments')
                                .doc(appartment.id)
                                .update({
                              'name': nameController.text,
                              'date': dateController.text,
                              'value': valueController.text,
                              'time': Timestamp.now(), // Use Timestamp.now()
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('تم تعديل مصاريف للسكن بنجاح')),
                            );
                          }
                          Navigator.of(context).pop();
                        }
                      },
                      child: Text('حفظ',
                          style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold)),
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

  void _deleteAppartment(Appartments appartment) async {
    await FirebaseFirestore.instance
        .collection('appartments')
        .doc(appartment.id)
        .delete();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف مصاريف السكن بنجاح')),
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
        title: Text('تفاصيل الشقق', style: TextStyle(fontSize: 20.sp)),
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
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.3,
                    height: MediaQuery.of(context).size.height * 0.05,
                    child: ElevatedButton(
                      onPressed: () {
                        _showEditDialog(null);
                      },
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0.r),
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
                ),
                SizedBox(height: 20.h),
                StreamBuilder<List<Appartments>>(
                  stream: _appartmentsStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return CircularProgressIndicator(
                        color: Colors.orange.withOpacity(0.7),
                      );
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                          child: Text('لا يوجد مصاريف للسكن',
                              style: TextStyle(fontSize: 18.sp)));
                    } else {
                      final appartments = snapshot.data!;
                      return Column(
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: [
                                DataColumn(
                                    label: Text('التاريخ',
                                        style: headTableTextStyle)),
                                DataColumn(
                                    label: Text('الإسم',
                                        style: headTableTextStyle)),
                                DataColumn(
                                    label: Text('المبلغ',
                                        style: headTableTextStyle)),
                                DataColumn(
                                    label: Text('تعديل أو حذف',
                                        style: headTableTextStyle)),
                              ],
                              rows: appartments.map<DataRow>((appartment) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(appartment.date)),
                                    DataCell(Text(appartment.name)),
                                    DataCell(Text(appartment.value)),
                                    DataCell(
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            onPressed: () =>
                                                _editAppartment(appartment),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete),
                                            onPressed: () =>
                                                _deleteAppartment(appartment),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
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