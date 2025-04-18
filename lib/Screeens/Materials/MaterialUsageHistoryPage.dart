// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter_screenutil/flutter_screenutil.dart';
//
// class MaterialUsageHistoryPage extends StatelessWidget {
//   final String materialId;
//   final String materialName;
//
//   const MaterialUsageHistoryPage({super.key, required this.materialId, required this.materialName});
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('سجل $materialName', style: TextStyle(fontSize: 20.sp, color: Colors.white)),
//         backgroundColor: Colors.black.withOpacity(0.7),
//       ),
//       body: Padding(
//         padding: EdgeInsets.all(10.w),
//         child: StreamBuilder<QuerySnapshot>(
//           stream: FirebaseFirestore.instance
//               .collection('materials')
//               .doc(materialId)
//               .collection('usageHistory')
//               .orderBy('date', descending: true)
//               .snapshots(),
//           builder: (context, snapshot) {
//             if (snapshot.connectionState == ConnectionState.waiting) {
//               return Center(
//                 child: CircularProgressIndicator(
//                   color: Colors.orange.withOpacity(0.8),
//                 ),
//               );
//             } else if (snapshot.hasError) {
//               return Center(
//                 child: Text('خطأ: ${snapshot.error}'),
//               );
//             } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
//               return Center(
//                 child: Text(
//                   'لا يوجد تاريخ متاح',
//                   style: TextStyle(
//                     fontSize: 18.sp,
//                     fontWeight: FontWeight.bold,
//                     color: Colors.black.withOpacity(0.7),
//                   ),
//                 ),
//               );
//             } else {
//               final changes = snapshot.data!.docs;
//               return SingleChildScrollView(
//                 scrollDirection: Axis.horizontal,
//                 child: DataTable(
//                   columns: [
//                     DataColumn(label: Text('التاريخ', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold))),
//                     DataColumn(label: Text('الكمية', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold))),
//                     DataColumn(label: Text('النوع', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold))),
//                   ],
//                   rows: changes.map((change) {
//                     return DataRow(cells: [
//                       DataCell(Text(change['date'].toDate().toString().split(' ')[0])),
//                       DataCell(Text(change['amount'].toString())),
//                       DataCell(Text(change['type'])),
//                     ]);
//                   }).toList(),
//                 ),
//               );
//             }
//           },
//         ),
//       ),
//     );
//   }
// }