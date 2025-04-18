// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter_screenutil/flutter_screenutil.dart';
//
// class SupervisorDataScreen extends StatelessWidget {
//   final String supervisor;
//
//   const SupervisorDataScreen({super.key, required this.supervisor});
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('بيانات المشرف', style: TextStyle(fontSize: 20.sp, color: Colors.white)),
//         backgroundColor: Colors.black.withOpacity(0.7),
//       ),
//       body: StreamBuilder<QuerySnapshot>(
//         stream: FirebaseFirestore.instance
//             .collection('supervisors')
//             .doc(supervisor)
//             .collection('history')
//             .snapshots(),
//         builder: (context, snapshot) {
//           if (!snapshot.hasData) {
//             return const Center(child: CircularProgressIndicator());
//           }
//
//           final data = snapshot.data!.docs;
//
//           return ListView.builder(
//             itemCount: data.length,
//             itemBuilder: (context, index) {
//               final doc = data[index];
//               return ListTile(
//                 title: Text('المادة: ${doc['material']}'),
//                 subtitle: Text('التاريخ: ${doc['date'].toDate().toLocal()}'),
//                 trailing: Text('النسبة: ${doc['rate']}%'),
//               );
//             },
//           );
//         },
//       ),
//     );
//   }
// }