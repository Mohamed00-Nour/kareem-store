import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

  class EmployeeData {
  static List<Map<String, dynamic>> employees = [
    {
      "name": "احمد كمال حسين ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 0
    },
    {
      "name": "محمد خالد عبدالنور",
      "borrows": [

      ],
      "medicines": [
        {
          "employeeName": "محمد خالد",
          "date": "2022-01-01",
          "value": "1000",
        },
        {
          "employeeName": " محمد خالدعبدالنور",
          "date": "2022-02-01",
          "value": "2000",
        },
      ],
      "attendance": [
        {
          "dateTime": "2022-01-01",
          "dayName": "saturday",
          "attendHour": "8:00 AM",
          "leaveHour": "8:00 PM",
          "responsible": "أحمد طلعت"
        },
      ],
      "order": 1
    },
    {
      "name": "يحيي زكريا إسماعيل الفقي",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 2
    },
    {
      "name": "سيد محمد عوض",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 3
    },
    {
      "name": "عبد الرحمن محمد (عزوز)",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 4
    },
    {
      "name": "ابراهيم أحمد (الغنام)",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 5
    },
    {
      "name": "ايمن صلاح عبد العزيز",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 6
    },
    {
      "name": "رمضان معوض قرني ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 7
    },
    {
      "name": "محمود علي محمد",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 8
    },
    {
      "name": "محمد عبدالخالق محفوظ ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 10
    },
    {
      "name": "عبدالرحمن علي",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 11
    },
    {
      "name": "مصطفي خالد محمد",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 12
    },
    {
      "name": "حمادة رضا محمد ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 13
    },
    {
      "name": "احمد طلعت عبدالعزيز ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 14
    },
    {
      "name": "وحيد عبدالمنعم أمين ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 15
    },
    {
      "name": "مصطفي سيد عبد الله",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 16
    },
    {
      "name": "محمد رمضان كامل",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 17
    },
    {
      "name": "عمرو ابو الخير عبدالتواب ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 18
    },
    {
      "name": "محمد علي جنيدي ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 19
    },
    {
      "name": "احمد جابر فتحي ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 20
    },
    {
      "name": "وليد عبد الستار عبد الله",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 21
    },
    {
      "name": "محمد رمضان عبد العزيز ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 22
    },
    {
      "name": "سعيد جمال حمدان ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 23
    },
    {
      "name": "محمد عويس بريك ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 25
    },
    {
      "name": "محمود حامد عبدالمنعم ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 26
    },
    {
      "name": "احمد ابو الخير يونس",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 27
    },
    {
      "name": "صالح سلامة سعيد ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 28
    },
    {
      "name": "عبد الرحمن محمد معوض ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 29
    },
    {
      "name": "مؤمن السيد محمد عبد الكريم",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 30
    },
    {
      "name": "صفاء جبالي رجب ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 31
    },
    {
      "name": "نورا عبد الفتاح عثمان ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 32
    },
    {
      "name": "عبير عبد الظاهر محمد ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 33
    },
    {
      "name": "كريمة مختار مصطفي ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 34
    },
    {
      "name": "اسراء قرني كمال",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 35
    },
    {
      "name": "احمد علي جنيدي ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 36
    },

    {
      "name": "حسن شحاته عويس",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 38
    },
    {
      "name": "مروان محمد عبد الفتاح ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 39
    },
    {
      "name": "اسامة وحيد فرج",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 40
    },
    {
      "name": "محمد فيصل ربيع",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 41
    },
    {
      "name": "منال حسين عبد التواب",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 42
    },
    {
      "name": "احمد عابدين عباس",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 43
    },
    {
      "name": "اسر وحيد عبد المنعم",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 44
    },
    {
      "name": "اسلام طلعت عبد العزيز",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 45
    },
    {
      "name": "مصطفي شعبان شحاته سيد",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 46
    },
    {
      "name": "احمد محمد صابر",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 47
    },
    {
      "name": "أسامة مجدي حسني",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 48
    },
    {
      "name": "اسلام جمعة حسني",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 49
    },
    {
      "name": "يونس ابراهيم حسن ",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 50
    },
    {
      "name": "محمد أحمد عويس",
      "borrows": [],
      "medicines": [],
      "attendance": [],
      "order": 51
    },
  ];

  static Future<void> addEmployeesToFirestore() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    FirebaseFirestore firestore = FirebaseFirestore.instance;
    WriteBatch batch = firestore.batch();

    // Sort employees by the 'order' field
    employees.sort((a, b) => a['order'].compareTo(b['order']));

    // Debug: Print sorted employees to verify order
    for (var employee in employees) {
      print('Order: ${employee['order']}, Name: ${employee['name']}');
    }

    for (var employee in employees) {
      String documentId = employee['name'].replaceAll(' ', '_');
      DocumentReference docRef = firestore.collection('employees').doc(documentId);
      batch.set(docRef, employee);
    }

    await batch.commit();
  }
  static Future<void> deleteAllEmployees() async {
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    WriteBatch batch = firestore.batch();

    QuerySnapshot querySnapshot = await firestore.collection('employees').get();

    for (QueryDocumentSnapshot doc in querySnapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }
}