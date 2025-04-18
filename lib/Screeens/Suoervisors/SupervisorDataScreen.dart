import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

class SupervisorDataScreen extends StatelessWidget {
  final String supervisor;

  const SupervisorDataScreen({super.key, required this.supervisor});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('بيانات المشرف', style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('supervisors')
            .doc(supervisor)
            .collection('history')
            .orderBy('date', descending: true) // Order by date in descending order
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.docs;

          return ListView.builder(
            itemCount: data.length,
            itemBuilder: (context, index) {
              final doc = data[index];
              final docData = doc.data() as Map<String, dynamic>?;
              final rate = docData != null && docData.containsKey('rate') ? docData['rate'] : 'N/A';
              final formattedDate = DateFormat('dd/MM/yyyy').format(doc['date'].toDate());

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                elevation: 2,
                color: Colors.orange.withOpacity(0.8),
                child: Column(
                  children: [
                    Center(
                      child: Text(
                        '$formattedDate',
                        style: TextStyle(fontSize: 16.sp, color: Colors.black.withOpacity(0.7)),
                      ),
                    ),
                    ListTile(
                      subtitle: Center(
                        child: Text(
                          'المادة: ${doc['material']}\nالكمية المستلمة: ${doc['amount']}\nالهالك: ${doc['deadMaterials']}',
                          style: TextStyle(fontSize: 14.sp, color: Colors.white),
                        ),
                      ),
                      trailing: Text(
                        'النسبة: %$rate',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: rate < 50
                              ? Colors.redAccent
                              : rate == 50
                              ? Colors.blueGrey
                              : Colors.greenAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}