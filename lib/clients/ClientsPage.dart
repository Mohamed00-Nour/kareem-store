import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'ClientInvoicesPage.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({Key? key}) : super(key: key);

  @override
  _ClientsPageState createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('العملاء'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            child: TextField(
              decoration: InputDecoration(
                focusedBorder: OutlineInputBorder(
                  borderSide:  BorderSide(color: Colors.black.withOpacity(0.7)),
                ),
                filled: true,
                fillColor: Colors.grey.withOpacity(0.1),
                labelText: 'ابحث عن عميل',
                labelStyle:  TextStyle(
                  color: Colors.black.withOpacity(0.7),
                  fontSize:18,
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Colors.black.withOpacity(0.7),
                  )
                ),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (query) {
                setState(() {
                  _searchQuery = query;
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('clients').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allClients = snapshot.data!.docs;
                final filteredClients = _searchQuery.isEmpty
                    ? allClients
                    : allClients.where((client) {
                        final clientName = client['clientName']?.toString().toLowerCase() ?? '';
                        return clientName.contains(_searchQuery.toLowerCase());
                      }).toList();

                return ListView.builder(
                  itemCount: filteredClients.length,
                  itemBuilder: (context, index) {
                    final client = filteredClients[index];
                    return Card(
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.7),
                      margin: const EdgeInsets.all(10.0),
                      child: ListTile(
                        title: Center(child: Text(client['clientName'])),
                        subtitle: Center(child: Text('الرصيد: ${client['balance'].toStringAsFixed(2)}')),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ClientInvoicesPage(clientId: client.id),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}