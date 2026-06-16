import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/SpareParts.dart';

class SparePartsDetails extends StatefulWidget {
  @override
  _SparePartsDetailsState createState() => _SparePartsDetailsState();
}

class _SparePartsDetailsState extends State<SparePartsDetails> {
  late Stream<List<SpareParts>> _sparePartsStream;
  String? selectedDate;

  @override
  void initState() {
    super.initState();
    _sparePartsStream = _fetchSpareParts();
  }

  Stream<List<SpareParts>> _fetchSpareParts() {
    return FirebaseFirestore.instance
        .collection('spare_parts')
        .orderBy('time', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => SpareParts.fromMap(doc.data() as Map<String, dynamic>))
        .toList());
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
            textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.black),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        selectedDate = "${picked.toLocal()}".split(' ')[0];
      });
    }
  }

  void _showEditDialog(SpareParts? sparePart, String? selectedDate) {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController nameController = TextEditingController(text: sparePart?.name ?? '');
    final TextEditingController valueController = TextEditingController(text: sparePart?.value ?? '');
    final TextEditingController amountController = TextEditingController(text: sparePart?.amount.toString() ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black12.withOpacity(0.8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sparePart == null ? 'إضافة قطع غيار' : 'تعديل قطع غيار',
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
                Form(
                  key: _formKey,
                  child: Container(
                    width: double.infinity,
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: Column(
                      children: [
                        Card(
                          margin: const EdgeInsets.all(8),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TextFormField(
                              keyboardType: TextInputType.text,
                              controller: nameController,
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.perm_identity_outlined),
                                hintText: 'أدخل إسم قطع الغيار',
                                border: InputBorder.none,
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'من فضلك أدخل إسم قطع الغيار';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                        Card(
                          margin: const EdgeInsets.all(8),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TextFormField(
                              keyboardType: TextInputType.number,
                              controller: valueController,
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
                            ),
                          ),
                        ),
                        Card(
                          margin: const EdgeInsets.all(8),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TextFormField(
                              keyboardType: TextInputType.number,
                              controller: amountController,
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.format_list_numbered),
                                labelStyle: TextStyle(
                                  color: Colors.black,
                                ),
                                hintText: 'أدخل الكمية',
                                border: InputBorder.none,
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'من فضلك أدخل الكمية';
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
                      child: const Text('إلغاء', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          if (sparePart == null) {
                            final newSparePart = SpareParts(
                              id: FirebaseFirestore.instance.collection('spare_parts').doc().id,
                              name: nameController.text,
                              date: selectedDate ?? '',
                              value: valueController.text,
                              amount: double.parse(amountController.text),
                            );
                            await FirebaseFirestore.instance
                                .collection('spare_parts')
                                .doc(newSparePart.id)
                                .set({
                              ...newSparePart.toMap(),
                              'time': FieldValue.serverTimestamp(), // Set the creation time separately
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم إضافة قطع الغيار بنجاح')),
                            );
                            Navigator.of(context).pop();
                          } else {
                            await FirebaseFirestore.instance
                                .collection('spare_parts')
                                .doc(sparePart.id)
                                .update({
                              'name': nameController.text,
                              'date': selectedDate ?? '',
                              'value': valueController.text,
                              'amount': int.parse(amountController.text),
                              'time': FieldValue.serverTimestamp(), // Update the time separately
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم تعديل قطع الغيار بنجاح')),
                            );
                            Navigator.of(context).pop();
                          }
                        }
                      },
                      child: const Text('حفظ', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
  void _deleteSparePart(SpareParts sparePart) async {
    await FirebaseFirestore.instance
        .collection('spare_parts')
        .doc(sparePart.id)
        .delete();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف قطع الغيار بنجاح')),
    );
  }

  @override
  Widget build(BuildContext context) {
    TextStyle headTableTextStyle = TextStyle(
      fontSize: 16.sp,
      fontWeight: FontWeight.bold,
      color: Colors.black.withOpacity(0.7),
    );

    return Scaffold(
        appBar: AppBar(
          title: const Text('تفاصيل قطع الغيار'),
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
                  SizedBox(height: 20.h),
                  ElevatedButton(
                    onPressed: () => _selectDate(context),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      backgroundColor: Colors.black.withOpacity(0.7),
                    ),
                    child: Text(
                      selectedDate ?? 'اختر التاريخ',
                      style: TextStyle(
                        fontSize: 15.sp,
                        color: Colors.white.withOpacity(1),
                      ),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  ElevatedButton(
                    onPressed: selectedDate != null ? () => _showEditDialog(null, selectedDate) : null,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      backgroundColor: Colors.black.withOpacity(0.7),
                    ),
                    child: Text(
                      'إضافة',
                      style: TextStyle(
                        fontSize: 15.sp,
                        color: Colors.white.withOpacity(1),
                      ),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  StreamBuilder<List<SpareParts>>(
                    stream: _sparePartsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return CircularProgressIndicator(
                          color: Colors.orange.withOpacity(0.8),
                        );
                      } else if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(child: Text('لا يوجد قطع غيار', style: TextStyle(fontSize: 18)));
                      } else {
                        final spareParts = snapshot.data!;
                        final groupedSpareParts = <String, List<SpareParts>>{};

                        for (var sparePart in spareParts) {
                          if (!groupedSpareParts.containsKey(sparePart.date)) {
                            groupedSpareParts[sparePart.date] = [];
                          }
                          groupedSpareParts[sparePart.date]!.add(sparePart);
                        }

                        return Column(
                          children: groupedSpareParts.entries.map((entry) {
                            return Column(
                              children: [
                                Container(
                                  width: double.infinity,
                                  height: 1.h,
                                  color: Colors.green,
                                  margin: EdgeInsets.symmetric(vertical: 10.h),
                                ),
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
                                          label: Text('الكمية',
                                              style: headTableTextStyle)),
                                      DataColumn(
                                          label: Text('المبلغ',
                                              style: headTableTextStyle)),
                                      DataColumn(
                                          label: Text('تعديل أو حذف',
                                              style: headTableTextStyle)),
                                    ],
                                    rows: entry.value.map<DataRow>((sparePart) {
                                      return DataRow(
                                        cells: [
                                          DataCell(Text(sparePart.date, style:  TextStyle(fontSize: 14.sp,))),
                                          DataCell(Text('${sparePart.name}', style:  TextStyle(fontSize: 14.sp,))),
                                          DataCell(Text(sparePart.amount.toString(), style:  TextStyle(fontSize: 14.sp,))),
                                          DataCell(Text(sparePart.value, style:  TextStyle(fontSize: 14.sp,))),
                                          DataCell(
                                            Row(
                                              children: [
                                                IconButton(
                                                  icon: Icon(Icons.edit , size: 18.sp),
                                                  onPressed: () =>
                                                      _showEditDialog(sparePart, selectedDate),
                                                ),
                                                IconButton(
                                                  icon: Icon(Icons.delete , size: 18.sp),
                                                  onPressed: () =>
                                                      _deleteSparePart(sparePart),
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
                          }).toList(),
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