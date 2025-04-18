// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter_screenutil/flutter_screenutil.dart';
//
// class MaterialUsagePage extends StatefulWidget {
//   const MaterialUsagePage({super.key});
//
//   @override
//   _MaterialUsagePageState createState() => _MaterialUsagePageState();
// }
//
// class _MaterialUsagePageState extends State<MaterialUsagePage> {
//   final List<String> _materials = ['Material 1', 'Material 2', 'Material 3'];
//   final List<String> _sections = ['سحب', 'حقن'];
//   final List<String> _responsibles = [
//     'Responsible 1',
//     'Responsible 2',
//     'Responsible 3'
//   ];
//   String? _selectedMaterial;
//   String? _selectedSection;
//   String? _selectedResponsible;
//   DateTime? _selectedDate;
//   final List<Map<String, dynamic>> _usedMaterials = [];
//   final TextEditingController _dateController = TextEditingController();
//   final TextEditingController _amountController = TextEditingController();
//   final _formKey = GlobalKey<FormState>();
//   int? _editingIndex;
//   bool _dataSaved = false;
//   bool _dataModified = false;
//   bool _isSaving = false;
//
//   void _pickDate() async {
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
//             buttonTheme: ButtonThemeData(textTheme: ButtonTextTheme.primary),
//             textSelectionTheme: TextSelectionThemeData(
//               cursorColor: Colors.orange.withOpacity(0.7),
//               selectionColor: Colors.orange.withOpacity(0.7),
//               selectionHandleColor: Colors.orange.withOpacity(0.7),
//             ),
//           ),
//           child: child!,
//         );
//       },
//     );
//     if (picked != null) {
//       setState(() {
//         _selectedDate = picked;
//         _dateController.text = "${picked.toLocal()}".split(' ')[0];
//         _dataModified = true;
//       });
//     }
//   }
//
//   void _selectResponsible() {
//     showDialog(
//       context: context,
//       builder: (BuildContext context) {
//         return AlertDialog(
//           backgroundColor: Colors.black.withOpacity(0.7),
//           title:
//               const Text('اختر المسئول', style: TextStyle(color: Colors.white)),
//           content: SingleChildScrollView(
//             child: Column(
//               children: _responsibles.map((responsible) {
//                 return ListTile(
//                   title: Text(responsible,
//                       style: const TextStyle(color: Colors.white)),
//                   onTap: () {
//                     setState(() {
//                       _selectedResponsible = responsible;
//                       _dataModified = true;
//                     });
//                     Navigator.of(context).pop();
//                   },
//                 );
//               }).toList(),
//             ),
//           ),
//         );
//       },
//     );
//   }
//
//   void _addMaterial() {
//     if (_formKey.currentState!.validate()) {
//       setState(() {
//         if (_editingIndex != null) {
//           _usedMaterials[_editingIndex!] = {
//             'material': _selectedMaterial,
//             'date': _selectedDate,
//             'responsible': _selectedResponsible,
//             'amount': _amountController.text,
//             'section': _selectedSection,
//           };
//           _editingIndex = null;
//         } else {
//           _usedMaterials.add({
//             'material': _selectedMaterial,
//             'date': _selectedDate,
//             'responsible': _selectedResponsible,
//             'amount': _amountController.text,
//             'section': _selectedSection,
//           });
//         }
//         _selectedMaterial = null;
//         _amountController.clear();
//         _dataModified = true;
//       });
//     }
//   }
//
//   void _editMaterial(int index) {
//     setState(() {
//       _selectedMaterial = _usedMaterials[index]['material'];
//       _selectedDate = _usedMaterials[index]['date'];
//       _selectedResponsible = _usedMaterials[index]['responsible'];
//       _amountController.text = _usedMaterials[index]['amount'];
//       _selectedSection = _usedMaterials[index]['section'];
//       _dateController.text = "${_selectedDate!.toLocal()}".split(' ')[0];
//       _editingIndex = index;
//     });
//   }
//
//   void _deleteMaterial(int index) {
//     setState(() {
//       _usedMaterials.removeAt(index);
//       _dataModified = true;
//     });
//   }
//
//   void _saveData() async {
//     if (!_dataModified) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Data already saved')),
//       );
//       return;
//     }
//
//     setState(() {
//       _isSaving = true;
//     });
//
//     for (var material in _usedMaterials) {
//       QuerySnapshot query = await FirebaseFirestore.instance
//           .collection('materialUsage')
//           .where('material', isEqualTo: material['material'])
//           .where('responsible', isEqualTo: material['responsible'])
//           .get();
//
//       if (query.docs.isNotEmpty) {
//         for (var doc in query.docs) {
//           int existingAmount = int.parse(doc['amount']);
//           int newAmount = existingAmount - int.parse(material['amount']);
//           await FirebaseFirestore.instance
//               .collection('materialUsage')
//               .doc(doc.id)
//               .update({
//             'amount': newAmount.toString(),
//           });
//
//           await FirebaseFirestore.instance
//               .collection('materialUsage')
//               .doc(doc.id)
//               .collection('changes')
//               .add({
//             'date': material['date'],
//             'amount': material['amount'],
//             'type': 'decrease',
//           });
//         }
//       } else {
//         DocumentReference newMaterialRef =
//             await FirebaseFirestore.instance.collection('materialUsage').add({
//           'material': material['material'],
//           'date': material['date'],
//           'responsible': material['responsible'],
//           'amount': material['amount'],
//           'section': material['section'],
//         });
//
//         await newMaterialRef.collection('changes').add({
//           'date': material['date'],
//           'amount': material['amount'],
//           'type': 'decrease',
//         });
//       }
//     }
//
//     setState(() {
//       _dataSaved = true;
//       _dataModified = false;
//       _isSaving = false;
//     });
//
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('Data saved successfully')),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     TextStyle headTableTextStyle = TextStyle(
//       fontSize: 18.sp,
//       fontWeight: FontWeight.bold,
//       color: Colors.black.withOpacity(0.7),
//     );
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('صرف المواد الخام',
//             style: TextStyle(fontSize: 20.sp, color: Colors.white)),
//         backgroundColor: Colors.black.withOpacity(0.7),
//       ),
//       body: Stack(
//         children: [
//           SingleChildScrollView(
//             child: Padding(
//               padding: EdgeInsets.all(10.w),
//               child: Form(
//                 key: _formKey,
//                 child: Column(
//                   children: [
//                     Card(
//                       margin:
//                           EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
//                       elevation: 2,
//                       color: Colors.orange.withOpacity(0.8),
//                       child: Padding(
//                         padding: EdgeInsets.all(8.w),
//                         child: TextFormField(
//                           controller: _dateController,
//                           decoration: const InputDecoration(
//                             suffixIcon: Icon(Icons.calendar_today),
//                             hintText: 'اختر التاريخ',
//                             border: InputBorder.none,
//                           ),
//                           readOnly: true,
//                           onTap: _pickDate,
//                           validator: (value) {
//                             if (value == null || value.isEmpty) {
//                               return 'يرجى اختيار التاريخ';
//                             }
//                             return null;
//                           },
//                         ),
//                       ),
//                     ),
//                     Card(
//                       margin:
//                           EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
//                       elevation: 2,
//                       color: Colors.orange.withOpacity(0.8),
//                       child: Padding(
//                         padding: EdgeInsets.all(8.w),
//                         child: DropdownButtonFormField<String>(
//                           decoration: const InputDecoration(
//                             suffixIcon: Icon(Icons.person),
//                             hintText: 'اختر المسئول',
//                             border: InputBorder.none,
//                           ),
//                           value: _selectedResponsible,
//                           onChanged: (String? newValue) {
//                             setState(() {
//                               _selectedResponsible = newValue;
//                             });
//                           },
//                           items: _responsibles
//                               .map<DropdownMenuItem<String>>((String value) {
//                             return DropdownMenuItem<String>(
//                               value: value,
//                               child: Text(value),
//                             );
//                           }).toList(),
//                           validator: (value) {
//                             if (value == null || value.isEmpty) {
//                               return 'يرجى اختيار المسئول';
//                             }
//                             return null;
//                           },
//                         ),
//                       ),
//                     ),
//                     Card(
//                       margin:
//                           EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
//                       elevation: 2,
//                       color: Colors.orange.withOpacity(0.8),
//                       child: Padding(
//                         padding: EdgeInsets.all(8.w),
//                         child: DropdownButtonFormField<String>(
//                           decoration: const InputDecoration(
//                             suffixIcon: Icon(Icons.shopping_cart),
//                             hintText: 'اختر المادة الخام',
//                             border: InputBorder.none,
//                           ),
//                           value: _selectedMaterial,
//                           onChanged: (String? newValue) {
//                             setState(() {
//                               _selectedMaterial = newValue;
//                             });
//                           },
//                           items: _materials
//                               .map<DropdownMenuItem<String>>((String value) {
//                             return DropdownMenuItem<String>(
//                               value: value,
//                               child: Text(value),
//                             );
//                           }).toList(),
//                           validator: (value) {
//                             if (value == null || value.isEmpty) {
//                               return 'يرجى اختيار المادة الخام';
//                             }
//                             return null;
//                           },
//                         ),
//                       ),
//                     ),
//                     Card(
//                       margin:
//                           EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
//                       elevation: 2,
//                       color: Colors.orange.withOpacity(0.8),
//                       child: Padding(
//                         padding: EdgeInsets.all(8.w),
//                         child: TextFormField(
//                           controller: _amountController,
//                           decoration: const InputDecoration(
//                             suffixIcon: Icon(Icons.format_list_numbered),
//                             hintText: 'أدخل الكمية',
//                             border: InputBorder.none,
//                           ),
//                           textAlign: TextAlign.center,
//                           keyboardType: TextInputType.number,
//                           validator: (value) {
//                             if (value == null || value.isEmpty) {
//                               return 'يرجى إدخال الكمية';
//                             }
//                             return null;
//                           },
//                         ),
//                       ),
//                     ),
//                     Card(
//                       margin:
//                           EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
//                       elevation: 2,
//                       color: Colors.orange.withOpacity(0.8),
//                       child: Padding(
//                         padding: EdgeInsets.all(8.w),
//                         child: DropdownButtonFormField<String>(
//                           decoration: const InputDecoration(
//                             suffixIcon: Icon(Icons.business),
//                             hintText: 'اختر القسم',
//                             border: InputBorder.none,
//                           ),
//                           value: _selectedSection,
//                           onChanged: (String? newValue) {
//                             setState(() {
//                               _selectedSection = newValue;
//                             });
//                           },
//                           items: _sections
//                               .map<DropdownMenuItem<String>>((String value) {
//                             return DropdownMenuItem<String>(
//                               value: value,
//                               child: Text(value),
//                             );
//                           }).toList(),
//                           validator: (value) {
//                             if (value == null || value.isEmpty) {
//                               return 'يرجى اختيار القسم';
//                             }
//                             return null;
//                           },
//                         ),
//                       ),
//                     ),
//                     Center(
//                       child: ElevatedButton(
//                         onPressed: _addMaterial,
//                         style: ElevatedButton.styleFrom(
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(8.0),
//                           ),
//                           backgroundColor: Colors.black.withOpacity(0.7),
//                         ),
//                         child: Text(
//                           _editingIndex != null ? 'تحديث المادة' : 'إضافة مادة',
//                           style: TextStyle(
//                             fontSize: 18.sp,
//                             color: Colors.white.withOpacity(1),
//                           ),
//                         ),
//                       ),
//                     ),
//                     SingleChildScrollView(
//                       scrollDirection: Axis.horizontal,
//                       child: DataTable(
//                         columns: [
//                           DataColumn(
//                               label:
//                                   Text('التاريخ', style: headTableTextStyle)),
//                           DataColumn(
//                               label:
//                                   Text('المسئول', style: headTableTextStyle)),
//                           DataColumn(
//                               label: Text('المادة', style: headTableTextStyle)),
//                           DataColumn(
//                               label: Text('الكمية', style: headTableTextStyle)),
//                           DataColumn(
//                               label: Text('القسم', style: headTableTextStyle)),
//                           DataColumn(
//                               label: Text('تعديل وحذف',
//                                   style: headTableTextStyle)),
//                         ],
//                         rows: _usedMaterials.asMap().entries.map((entry) {
//                           int index = entry.key;
//                           Map<String, dynamic> material = entry.value;
//                           return DataRow(cells: [
//                             DataCell(Text(
//                                 material['date'].toString().split(' ')[0],
//                                 style: TextStyle(fontSize: 14.sp))),
//                             DataCell(Text(material['responsible'],
//                                 style: TextStyle(fontSize: 14.sp))),
//                             DataCell(Text(material['material'],
//                                 style: TextStyle(fontSize: 14.sp))),
//                             DataCell(Text(material['amount'],
//                                 style: TextStyle(fontSize: 14.sp))),
//                             DataCell(Text(material['section'],
//                                 style: TextStyle(fontSize: 14.sp))),
//                             DataCell(Row(
//                               children: [
//                                 IconButton(
//                                   icon: Icon(Icons.edit, color: Colors.blue),
//                                   onPressed: () => _editMaterial(index),
//                                 ),
//                                 IconButton(
//                                   icon: Icon(Icons.delete, color: Colors.red),
//                                   onPressed: () => _deleteMaterial(index),
//                                 ),
//                               ],
//                             )),
//                           ]);
//                         }).toList(),
//                       ),
//                     ),
//                     Center(
//                       child: ElevatedButton(
//                         onPressed: _saveData,
//                         style: ElevatedButton.styleFrom(
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(8.0),
//                           ),
//                           backgroundColor: Colors.black.withOpacity(0.7),
//                         ),
//                         child: Text(
//                           'حفظ',
//                           style: TextStyle(
//                             fontSize: 20.sp,
//                             color: Colors.white.withOpacity(1),
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//           if (_isSaving)
//             Container(
//               color: Colors.black.withOpacity(0.5),
//               child: Center(
//                 child: CircularProgressIndicator(
//                   color: Colors.orange.withOpacity(0.8),
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }
// }
