import 'package:cloud_firestore/cloud_firestore.dart';

final List<String> products = [];
final List<String> responsibles = [];

Future<void> fetchSharedLists() async {
  // Fetch products from Firebase
  QuerySnapshot productSnapshot = await FirebaseFirestore.instance.collection('products').get();
  for (var doc in productSnapshot.docs) {
    products.add(doc['product']);
  }

  // Fetch responsibles from Firebase
  QuerySnapshot responsibleSnapshot = await FirebaseFirestore.instance.collection('responsibles').get();
  for (var doc in responsibleSnapshot.docs) {
    responsibles.add(doc['name']);
  }
}