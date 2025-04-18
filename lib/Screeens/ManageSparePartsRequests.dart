import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ManageSparePartsRequests extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('إدارة طلبات قطع الغيار'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('sparePartsRequests')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            }

            final requests = snapshot.data!.docs;

            return ListView.builder(
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final request = requests[index];
                final data = request.data() as Map<String, dynamic>;

                return Card(
                  margin: EdgeInsets.symmetric(vertical: 8.h, horizontal: 5.w),
                  elevation: 2,
                  child: ListTile(
                    title: Text(
                      data['partName'],
                      style: TextStyle(
                          fontSize: 14.sp, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'الكمية: ${data['quantity']}',
                      style: TextStyle(fontSize: 12.sp),
                    ),
                    trailing: Text(
                      _translateStatus(data['status']),
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: data['status'] == 'pending'
                            ? Colors.orange
                            : data['status'] == 'accepted'
                                ? Colors.green
                                : Colors.red,
                      ),
                    ),
                    onTap: () {
                      _showRequestDialog(context, request.id, data['status']);
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'pending':
        return 'انتظار';
      case 'accepted':
        return 'مقبول';
      case 'rejected':
        return 'مرفوض';
      default:
        return status;
    }
  }

  void _showRequestDialog(
      BuildContext context, String requestId, String currentStatus) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('تحديث حالة الطلب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('قبول'),
                leading: Radio(
                  value: 'accepted',
                  groupValue: currentStatus,
                  onChanged: (value) {
                    _updateRequestStatus(requestId, value as String);
                    Navigator.of(context).pop();
                  },
                ),
              ),
              ListTile(
                title: Text('رفض'),
                leading: Radio(
                  value: 'rejected',
                  groupValue: currentStatus,
                  onChanged: (value) {
                    _updateRequestStatus(requestId, value as String);
                    Navigator.of(context).pop();
                  },
                ),
              ),
              ListTile(
                title: Text('معلق'),
                leading: Radio(
                  value: 'pending',
                  groupValue: currentStatus,
                  onChanged: (value) {
                    _updateRequestStatus(requestId, value as String);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateRequestStatus(String requestId, String status) async {
    await FirebaseFirestore.instance
        .collection('sparePartsRequests')
        .doc(requestId)
        .update({
      'status': status,
    });
  }
}
