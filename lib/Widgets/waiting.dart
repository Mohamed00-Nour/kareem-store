// ...employee.borrows.map<Widget>((detail) {
//   return Padding(
//     padding: const EdgeInsets.symmetric(vertical: 5),
//     child: Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text('Date: ${detail.date}'),
//         Text('Responsible: ${detail.responsible}'),
//         Text('Value: ${detail.value}'),
//       ],
//     ),
//   );
// }).toList(),

// import 'package:flutter/material.dart';
// import '../Widgets/Add_Borrow.dart';
// import '../models/Employee.dart';
//
// class EmployeeBorrowDetails extends StatelessWidget {
//   final Employee employee;
//
//   const EmployeeBorrowDetails({super.key, required this.employee});
//
//   @override
//   Widget build(BuildContext context) {
//     TextStyle headTableTextStyle = TextStyle(
//       fontSize: 20,
//       fontWeight: FontWeight.bold,
//       color: Colors.black.withOpacity(0.7),
//     );
//
//     // Calculate the total value
//     final totalValue = employee.borrows.fold<double>(
//       0,
//           (sum, detail) => sum + double.parse(detail.value),
//     );
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(employee.name),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(10.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.center,
//           children: [
//             const SizedBox(height: 10),
//             DataTable(
//               columns: [
//                 DataColumn(
//                   label: Text(
//                     'التاريخ',
//                     style: headTableTextStyle,
//                   ),
//                 ),
//                 DataColumn(label: Text('المسئول', style: headTableTextStyle)),
//                 DataColumn(label: Text('المبلغ', style: headTableTextStyle)),
//               ],
//               rows: employee.borrows.map<DataRow>((detail) {
//                 return DataRow(
//                   cells: [
//                     DataCell(Text(detail.date)),
//                     DataCell(Text(detail.responsible)),
//                     DataCell(Text(detail.value)),
//                   ],
//                 );
//               }).toList(),
//             ),
//             const SizedBox(height: 20),
//             Align(
//               alignment: Alignment.centerRight,
//               child: Text(
//                 '$totalValue :مجموع السلف ',
//                 style: TextStyle(
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                   color: Colors.black.withOpacity(0.7),
//                 ),
//               ),
//             ),
//             Expanded(child: AddBorrow()),
//           ],
//         ),
//       ),
//     );
//   }
// }

// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter_screenutil/flutter_screenutil.dart';
// import '../models/SpareParts.dart';
//
// class SparePartsDetails extends StatefulWidget {
//   @override
//   _SparePartsDetailsState createState() => _SparePartsDetailsState();
// }
//
// class _SparePartsDetailsState extends State<SparePartsDetails> {
//   late Stream<List<SpareParts>> _sparePartsStream;
//   String? selectedDate;
//
//   @override
//   void initState() {
//     super.initState();
//     _sparePartsStream = _fetchSpareParts();
//   }
//
//   Stream<List<SpareParts>> _fetchSpareParts() {
//     return FirebaseFirestore.instance
//         .collection('spare_parts')
//         .orderBy('time', descending: true)
//         .snapshots()
//         .map((snapshot) => snapshot.docs
//         .map((doc) => SpareParts.fromMap(doc.data() as Map<String, dynamic>))
//         .toList());
//   }
//
//   Future<void> _selectDate(BuildContext context) async {
//     final int currentYear = DateTime.now().year;
//     final DateTime? picked = await showDatePicker(
//       context: context,
//       initialDate: DateTime.now(),
//       firstDate: DateTime(currentYear, 1, 1),
//       lastDate: DateTime(currentYear, 12, 31),
//       builder: (BuildContext context, Widget? child) {
//         return Theme(
//           data: ThemeData.light().copyWith(
//             primaryColor: Colors.orange.withOpacity(0.7),
//             hintColor: Colors.orange.withOpacity(0.7),
//             colorScheme: const ColorScheme.light(primary: Colors.orange),
//             buttonTheme: const ButtonThemeData(textTheme: ButtonTextTheme.primary),
//             textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.black),
//           ),
//           child: child!,
//         );
//       },
//     );
//     if (picked != null) {
//       setState(() {
//         selectedDate = "${picked.toLocal()}".split(' ')[0];
//       });
//     }
//   }
//
//   void _showEditDialog(SpareParts? sparePart, String? selectedDate) {
//     final _formKey = GlobalKey<FormState>();
//     final TextEditingController nameController = TextEditingController(text: sparePart?.name ?? '');
//     final TextEditingController valueController = TextEditingController(text: sparePart?.value ?? '');
//
//     showDialog(
//       context: context,
//       builder: (context) {
//         return Dialog(
//           backgroundColor: Colors.black12.withOpacity(0.8),
//           child: Container(
//             width: double.infinity,
//             padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Text(
//                   sparePart == null ? 'إضافة قطع غيار' : 'تعديل قطع غيار',
//                   style: const TextStyle(color: Colors.white, fontSize: 20),
//                 ),
//                 Form(
//                   key: _formKey,
//                   child: Container(
//                     width: double.infinity,
//                     height: MediaQuery.of(context).size.height * 0.4,
//                     child: Column(
//                       children: [
//                         Card(
//                           margin: const EdgeInsets.all(8),
//                           elevation: 2,
//                           color: Colors.orange.withOpacity(0.8),
//                           child: Padding(
//                             padding: const EdgeInsets.all(8.0),
//                             child: TextFormField(
//                               keyboardType: TextInputType.text,
//                               controller: nameController,
//                               decoration: const InputDecoration(
//                                 suffixIcon: Icon(Icons.perm_identity_outlined),
//                                 hintText: 'أدخل إسم قطع الغيار',
//                                 border: InputBorder.none,
//                               ),
//                               textAlign: TextAlign.center,
//                               validator: (value) {
//                                 if (value == null || value.isEmpty) {
//                                   return 'من فضلك أدخل إسم قطع الغيار';
//                                 }
//                                 return null;
//                               },
//                             ),
//                           ),
//                         ),
//                         Card(
//                           margin: const EdgeInsets.all(8),
//                           elevation: 2,
//                           color: Colors.orange.withOpacity(0.8),
//                           child: Padding(
//                             padding: const EdgeInsets.all(8.0),
//                             child: TextFormField(
//                               keyboardType: TextInputType.number,
//                               controller: valueController,
//                               decoration: const InputDecoration(
//                                 suffixIcon: Icon(Icons.attach_money_outlined),
//                                 labelStyle: TextStyle(
//                                   color: Colors.black,
//                                 ),
//                                 hintText: 'أدخل المبلغ',
//                                 border: InputBorder.none,
//                               ),
//                               textAlign: TextAlign.center,
//                               validator: (value) {
//                                 if (value == null || value.isEmpty) {
//                                   return 'من فضلك أدخل المبلغ';
//                                 }
//                                 return null;
//                               },
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.end,
//                   children: [
//                     TextButton(
//                       onPressed: () {
//                         Navigator.of(context).pop();
//                       },
//                       child: const Text('إلغاء', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
//                     ),
//                     TextButton(
//                       onPressed: () async {
//                         if (_formKey.currentState!.validate()) {
//                           if (sparePart == null) {
//                             final newSparePart = SpareParts(
//                               id: FirebaseFirestore.instance.collection('spare_parts').doc().id,
//                               name: nameController.text,
//                               date: selectedDate ?? '',
//                               value: valueController.text,
//                             );
//                             await FirebaseFirestore.instance
//                                 .collection('spare_parts')
//                                 .doc(newSparePart.id)
//                                 .set({
//                               ...newSparePart.toMap(),
//                               'time': FieldValue.serverTimestamp(), // Set the creation time separately
//                             });
//                             ScaffoldMessenger.of(context).showSnackBar(
//                               const SnackBar(content: Text('تم إضافة قطع الغيار بنجاح')),
//                             );
//                             Navigator.of(context).pop();
//                           } else {
//                             await FirebaseFirestore.instance
//                                 .collection('spare_parts')
//                                 .doc(sparePart.id)
//                                 .update({
//                               'name': nameController.text,
//                               'date': selectedDate ?? '',
//                               'value': valueController.text,
//                               'time': FieldValue.serverTimestamp(), // Update the time separately
//                             });
//                             ScaffoldMessenger.of(context).showSnackBar(
//                               const SnackBar(content: Text('تم تعديل قطع الغيار بنجاح')),
//                             );
//                             Navigator.of(context).pop();
//                           }
//                         }
//                       },
//                       child: const Text('حفظ', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }
//
//   void _deleteSparePart(SpareParts sparePart) async {
//     await FirebaseFirestore.instance
//         .collection('spare_parts')
//         .doc(sparePart.id)
//         .delete();
//
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('تم حذف قطع الغيار بنجاح')),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     TextStyle headTableTextStyle = TextStyle(
//       fontSize: 20.sp,
//       fontWeight: FontWeight.bold,
//       color: Colors.black.withOpacity(0.7),
//     );
//
//     return ScreenUtilInit(
//       designSize: const Size(360, 690),
//       builder: (context, child) => Scaffold(
//         appBar: AppBar(
//           title: const Text('تفاصيل قطع الغيار'),
//         ),
//         body: Padding(
//           padding: EdgeInsets.all(10.w),
//           child: SingleChildScrollView(
//             child: Container(
//               constraints: BoxConstraints(
//                 minHeight: MediaQuery.of(context).size.height,
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.center,
//                 children: [
//                   SizedBox(height: 20.h),
//                   ElevatedButton(
//                     onPressed: () => _selectDate(context),
//                     style: ElevatedButton.styleFrom(
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(8.0),
//                       ),
//                       backgroundColor: Colors.black.withOpacity(0.7),
//                     ),
//                     child: Text(
//                       selectedDate ?? 'اختر التاريخ',
//                       style: TextStyle(
//                         fontSize: 20.sp,
//                         color: Colors.white.withOpacity(1),
//                       ),
//                     ),
//                   ),
//                   SizedBox(height: 20.h),
//                   ElevatedButton(
//                     onPressed: selectedDate != null ? () => _showEditDialog(null, selectedDate) : null,
//                     style: ElevatedButton.styleFrom(
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(8.0),
//                       ),
//                       backgroundColor: Colors.black.withOpacity(0.7),
//                     ),
//                     child: Text(
//                       'إضافة',
//                       style: TextStyle(
//                         fontSize: 20.sp,
//                         color: Colors.white.withOpacity(1),
//                       ),
//                     ),
//                   ),
//                   SizedBox(height: 20.h),
//                   StreamBuilder<List<SpareParts>>(
//                     stream: _sparePartsStream,
//                     builder: (context, snapshot) {
//                       if (snapshot.connectionState == ConnectionState.waiting) {
//                         return CircularProgressIndicator(
//                           color: Colors.orange.withOpacity(0.8),
//                         );
//                       } else if (snapshot.hasError) {
//                         return Text('Error: ${snapshot.error}');
//                       } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
//                         return const Center(child: Text('لا يوجد قطع غيار', style: TextStyle(fontSize: 18)));
//                       } else {
//                         final spareParts = snapshot.data!;
//                         return Column(
//                           children: [
//                             SingleChildScrollView(
//                               scrollDirection: Axis.horizontal,
//                               child: DataTable(
//                                 columns: [
//                                   DataColumn(
//                                       label: Text('التاريخ',
//                                           style: headTableTextStyle)),
//                                   DataColumn(
//                                       label: Text('الإسم',
//                                           style: headTableTextStyle)),
//                                   DataColumn(
//                                       label: Text('المبلغ',
//                                           style: headTableTextStyle)),
//                                   DataColumn(
//                                       label: Text('تعديل أو حذف',
//                                           style: headTableTextStyle)),
//                                 ],
//                                 rows: _buildDataRows(spareParts),
//                               ),
//                             ),
//                           ],
//                         );
//                       }
//                     },
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
//
//   List<DataRow> _buildDataRows(List<SpareParts> spareParts) {
//     List<DataRow> rows = [];
//     String? lastDate;
//
//     for (var sparePart in spareParts) {
//       if (lastDate != null && lastDate != sparePart.date) {
//         rows.add(DataRow(cells: [
//           DataCell(Container(
//             width: double.infinity,
//             height: 2.h,
//             color: Colors.green,
//           )),
//           DataCell(Container()),
//           DataCell(Container()),
//           DataCell(Container()),
//         ]));
//       }
//
//       rows.add(DataRow(cells: [
//         DataCell(Text(sparePart.date, style: TextStyle(fontSize: 14.sp))),
//         DataCell(Text(sparePart.name, style: TextStyle(fontSize: 14.sp))),
//         DataCell(Text(sparePart.value, style: TextStyle(fontSize: 14.sp))),
//         DataCell(
//           Row(
//             children: [
//               IconButton(
//                 icon: Icon(Icons.edit, size: 18.sp),
//                 onPressed: () => _showEditDialog(sparePart, selectedDate),
//               ),
//               IconButton(
//                 icon: Icon(Icons.delete, size: 18.sp),
//                 onPressed: () => _deleteSparePart(sparePart),
//               ),
//             ],
//           ),
//         ),
//       ]));
//
//       lastDate = sparePart.date;
//     }
//
//     return rows;
//   }
// }