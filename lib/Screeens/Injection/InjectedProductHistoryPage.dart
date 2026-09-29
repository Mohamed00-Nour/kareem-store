import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../Widgets/paginated_firestore_history_table.dart';

class InjectedProductHistoryPage extends StatelessWidget {
  final String productId;
  final String productName;

  const InjectedProductHistoryPage({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'سجل $productName',
          style: TextStyle(fontSize: 20.sp, color: Colors.white),
        ),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: Padding(
        padding: EdgeInsets.all(10.w),
        child: PaginatedFirestoreHistoryTable(
          collection: FirebaseFirestore.instance
              .collection('injectedProducts')
              .doc(productId)
              .collection('changes'),
        ),
      ),
    );
  }
}
