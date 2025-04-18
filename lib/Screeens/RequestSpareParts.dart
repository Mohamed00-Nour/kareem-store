import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'ManageSparePartsRequests.dart';

class RequestSpareParts extends StatefulWidget {
  @override
  _RequestSparePartsState createState() => _RequestSparePartsState();
}

class _RequestSparePartsState extends State<RequestSpareParts> {
  final TextEditingController _partNameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();

  Future<void> _submitRequest() async {
    final partName = _partNameController.text;
    final quantity = _quantityController.text;

    if (partName.isNotEmpty && quantity.isNotEmpty) {
      await FirebaseFirestore.instance.collection('sparePartsRequests').add({
        'partName': partName,
        'quantity': quantity,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إرسال الطلب بنجاح')),
      );

      _partNameController.clear();
      _quantityController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('يرجى ملء جميع الحقول')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('طلب شراء قطع غيار'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              margin: EdgeInsets.all(5.w),
              elevation: 2,
              color: Colors.orange.withOpacity(0.8),
              child: Padding(
                padding: EdgeInsets.all(8.w),
                child: TextFormField(
                  controller: _partNameController,
                  decoration: const InputDecoration(
                    hintText: 'اسم القطعة',
                    border: InputBorder.none,
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14.sp),
                ),
              ),
            ),
            Card(
              margin: EdgeInsets.all(5.w),
              elevation: 2,
              color: Colors.orange.withOpacity(0.8),
              child: Padding(
                padding: EdgeInsets.all(8.w),
                child: TextFormField(
                  controller: _quantityController,
                  decoration: const InputDecoration(
                    hintText: 'الكمية',
                    border: InputBorder.none,
                  ),
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  style: TextStyle(fontSize: 14.sp),
                ),
              ),
            ),
            SizedBox(height: 20.h),
            ElevatedButton(
              onPressed: _submitRequest,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                backgroundColor: Colors.black.withOpacity(0.7),
              ),
              child: Text(
                'إرسال الطلب',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.white.withOpacity(1),
                ),
              ),
            ),
            SizedBox(height: 10.h),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => ManageSparePartsRequests(),
                ));
              },
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                backgroundColor: Colors.black.withOpacity(0.7),
              ),
              child: Text(
                'إدارة طلبات القطع',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.white.withOpacity(1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}