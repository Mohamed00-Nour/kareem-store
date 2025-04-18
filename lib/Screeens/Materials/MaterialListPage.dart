import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'MaterialHistoryPage.dart';

class MaterialListPage extends StatefulWidget {
  const MaterialListPage({super.key});

  @override
  _MaterialListPageState createState() => _MaterialListPageState();
}

class _MaterialListPageState extends State<MaterialListPage> {
  bool _showAllMaterials = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'رصيد المواد الحالي',
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
                stream: FirebaseFirestore.instance.collection('materials').snapshots(),
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
                      child: Text('لا يوجد خامة متاحة', textAlign: TextAlign.right),
                    );
                  } else {
                    var materials = snapshot.data!.docs;
                    if (!_showAllMaterials) {
                      materials = materials.where((doc) => int.parse(doc['amount']) > 0).toList();
                    }
                    return ListView.builder(
                      itemCount: materials.length,
                      itemBuilder: (context, index) {
                        var material = materials[index];
                        return Card(
                          margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: ListTile(
                            title: Center(child: Text(material['material'], style: TextStyle(fontSize: 18.sp, color: Colors.black.withOpacity(0.7)))),
                            subtitle: Center(child: Text('الكمية: ${material['amount']}', style: TextStyle(fontSize: 16.sp, color: Colors.white))),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => MaterialHistoryPage(
                                    materialId: material.id,
                                    materialName: material['material'],
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
                  _showAllMaterials = !_showAllMaterials;
                });
              },
              child: Text(
                _showAllMaterials ? 'إخفاء الخامات ذات الكمية 0' : 'عرض جميع الخامات',
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