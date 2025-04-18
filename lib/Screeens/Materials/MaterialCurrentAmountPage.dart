// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter_screenutil/flutter_screenutil.dart';
// import 'MaterialUsageHistoryPage.dart';
//
// class MaterialCurrentAmountPage extends StatefulWidget {
//   const MaterialCurrentAmountPage({super.key});
//
//   @override
//   _MaterialCurrentAmountPageState createState() => _MaterialCurrentAmountPageState();
// }
//
// class _MaterialCurrentAmountPageState extends State<MaterialCurrentAmountPage> {
//   bool _showAllMaterials = false;
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(
//           'الكمية الحالية للمواد الخام',
//           style: TextStyle(fontSize: 20.sp, color: Colors.white),
//           textAlign: TextAlign.right,
//         ),
//         backgroundColor: Colors.black.withOpacity(0.7),
//       ),
//       body: Padding(
//         padding: EdgeInsets.all(10.w),
//         child: Column(
//           children: [
//             Expanded(
//               child: StreamBuilder<QuerySnapshot>(
//                 stream: FirebaseFirestore.instance.collection('materials').snapshots(),
//                 builder: (context, snapshot) {
//                   if (snapshot.connectionState == ConnectionState.waiting) {
//                     return Center(
//                       child: CircularProgressIndicator(
//                         color: Colors.orange.withOpacity(0.8),
//                       ),
//                     );
//                   } else if (snapshot.hasError) {
//                     return Center(child: Text('Error: ${snapshot.error}'));
//                   } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
//                     return Center(child: Text('No materials available'));
//                   } else {
//                     final materials = snapshot.data!.docs;
//                     final filteredMaterials = _showAllMaterials
//                         ? materials
//                         : materials.where((material) => int.parse(material['amount']) > 0).toList();
//                     return ListView.builder(
//                       itemCount: filteredMaterials.length,
//                       itemBuilder: (context, index) {
//                         final material = filteredMaterials[index];
//                         return Card(
//                           margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
//                           elevation: 2,
//                           color: Colors.orange.withOpacity(0.8),
//                           child: ListTile(
//                             title: Center(child: Text(material['material'], style: TextStyle(fontSize: 18.sp, color: Colors.black.withOpacity(0.7)))),
//                             subtitle: Center(child: Text('الكمية: ${material['amount']}', style: TextStyle(fontSize: 16.sp, color: Colors.white))),
//                             onTap: () {
//                               Navigator.of(context).push(MaterialPageRoute(
//                                 builder: (context) => MaterialUsageHistoryPage(
//                                   materialId: material.id,
//                                   materialName: material['material'],
//                                 ),
//                               ));
//                             },
//                           ),
//                         );
//                       },
//                     );
//                   }
//                 },
//               ),
//             ),
//             TextButton(
//               onPressed: () {
//                 setState(() {
//                   _showAllMaterials = !_showAllMaterials;
//                 });
//               },
//               child: Text(
//                 _showAllMaterials ? 'إخفاء المواد ذات الكمية 0' : 'عرض جميع المواد',
//                 style: TextStyle(fontSize: 16.sp, color: Colors.blue),
//                 textAlign: TextAlign.right,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }