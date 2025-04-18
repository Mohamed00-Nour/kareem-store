import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'PipeHistoryPage.dart';

class PipeListPage extends StatefulWidget {
  const PipeListPage({super.key});

  @override
  _PipeListPageState createState() => _PipeListPageState();
}

class _PipeListPageState extends State<PipeListPage> {
  bool _showAllProducts = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'رصيد المواسير الحالي',
          style: TextStyle(fontSize: 20.sp, color: Colors.white),
          textAlign: TextAlign.right,
        ),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: Padding(
        padding: EdgeInsets.all(10.w),
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('pipes').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: Colors.orange.withOpacity(0.8),
                      ),
                    );
                  } else if (snapshot.hasError) {
                    return Center(
                      child: Text('Error: ${snapshot.error}', textAlign: TextAlign.right),
                    );
                  } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text('لا يوجد مواسير متاحة', textAlign: TextAlign.right),
                    );
                  } else {
                    var pipes = snapshot.data!.docs;
                    if (!_showAllProducts) {
                      pipes = pipes.where((doc) => int.parse(doc['amount']) > 0).toList();
                    }
                    return ListView.builder(
                      itemCount: pipes.length,
                      itemBuilder: (context, index) {
                        var pipe = pipes[index];
                        return Card(
                          margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: ListTile(
                            title: Center(child: Text(pipe['product'], style: TextStyle(fontSize: 18.sp, color: Colors.black.withOpacity(0.7)))),
                            subtitle: Center(child: Text('الكمية: ${pipe['amount']}', style: TextStyle(fontSize: 16.sp, color: Colors.white))),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PipeHistoryPage(
                                    pipeId: pipe.id,
                                    pipeName: pipe['product'],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  }
                },
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _showAllProducts = !_showAllProducts;
                });
              },
              child: Text(
                _showAllProducts ? 'إخفاء المواسير ذات الكمية 0' : 'عرض جميع المواسير',
                style: TextStyle(fontSize: 16.sp, color: Colors.blue),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}