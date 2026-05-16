import 'package:flutter/material.dart';

class DeletedClientsPage extends StatelessWidget {
  final Set<String> deletedClients;
  final Function(String) onRestoreClient;

  const DeletedClientsPage({Key? key, required this.deletedClients, required this.onRestoreClient})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        title: const Text(
          'العملاء المحذوفين',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView.builder(
        itemCount: deletedClients.length,
        itemBuilder: (context, index) {
          final clientId = deletedClients.elementAt(index);
          return Card(
            elevation: 2,
            color: Colors.orange.withOpacity(0.7),
            margin: const EdgeInsets.all(10.0),
            child: ListTile(
              title: Center(child: Text('اسم العميل: $clientId')),
              trailing: IconButton(
                icon: const Icon(Icons.restore, color: Colors.white),
                onPressed: () {
                  _showRestoreConfirmationDialog(context, clientId);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _showRestoreConfirmationDialog(BuildContext context, String clientId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: const Text('هل تريد استعادة هذا العميل إلى القائمة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لا'),
          ),
          TextButton(
            onPressed: () {
              onRestoreClient(clientId); // Call the restore function
              Navigator.pop(context);
            },
            child: const Text('نعم'),
          ),
        ],
      ),
    );
  }
}