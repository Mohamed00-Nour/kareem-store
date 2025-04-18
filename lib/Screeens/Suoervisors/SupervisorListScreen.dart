import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'SupervisorDataScreen.dart';

class SupervisorListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('قائمة المشرفين', style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('supervisors').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final supervisors = snapshot.data!.docs;

          return ListView.builder(
            itemCount: supervisors.length,
            itemBuilder: (context, index) {
              final supervisor = supervisors[index];
              return Card(
                margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                elevation: 2,
                color: Colors.orange.withOpacity(0.8),
                child: ListTile(
                  title: Center(
                    child: Text(
                      supervisor.id,
                      style: TextStyle(fontSize: 18.sp, color: Colors.black.withOpacity(0.7)),
                    ),
                  ),
                  subtitle: FutureBuilder<double>(
                    future: _calculateMonthlyRate(supervisor.id),
                    builder: (context, rateSnapshot) {
                      if (!rateSnapshot.hasData) {
                        return Center(child: CircularProgressIndicator(

                          color: Colors.black.withOpacity(0.8), ));
                      }
                      return Center(
                        child: Text(
                          'النسبة الشهرية: %${rateSnapshot.data!.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 16.sp, color: Colors.white),
                        ),
                      );
                    },
                  ),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => SupervisorDataScreen(supervisor: supervisor.id),
                    ));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<double> _calculateMonthlyRate(String supervisorId) async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);

    final querySnapshot = await FirebaseFirestore.instance
        .collection('supervisors')
        .doc(supervisorId)
        .collection('history')
        .where('date', isGreaterThanOrEqualTo: startOfMonth)
        .where('date', isLessThanOrEqualTo: endOfMonth)
        .get();

    if (querySnapshot.docs.isEmpty) {
      return 0.0;
    }

    double totalRate = 0.0;
    for (var doc in querySnapshot.docs) {
      totalRate += doc['rate'];
    }

    return totalRate / querySnapshot.docs.length;
  }
}