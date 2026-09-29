import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../local_db/hive_init.dart';
import '../../Services/customer_balance_review.dart';
import '../../Services/invoice_number_utils.dart';

class CustomerBalanceReviewScreen extends StatelessWidget {
  const CustomerBalanceReviewScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('مراجعة أرصدة العملاء')),
        body: AnimatedBuilder(
          animation: Listenable.merge([
            clientsBox.listenable(),
            appMetaBox.listenable(),
            balanceHistoryBox.listenable(),
            invoicesBox.listenable(),
            returnInvoicesBox.listenable()
          ]),
          builder: (context, _) {
            final rows = CustomerBalanceReview.rows();
            return ListView(children: [
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'مراجعة فقط، لا يتم تعديل الأرصدة. الفرق قد يعني سجلاً تاريخياً غير مكتمل. '
                      'راجع الفواتير والدفعات والعمليات المعلقة قبل أي تسوية.')),
              for (final row in rows)
                ListTile(
                  title: Text(row['name'].toString()),
                  subtitle: Text('الرصيد المحلي المعتمد: ' +
                      invoiceAmount(row['accepted']) +
                      '\nإجمالي السجل المتاح: ' +
                      invoiceAmount(row['cachedHistory']) +
                      '\nالفرق للمراجعة: ' +
                      invoiceAmount(row['difference']) +
                      '\nآخر رصيد سحابي معروف: ' +
                      (row['cloud'] == null
                          ? 'غير متاح'
                          : invoiceAmount(row['cloud'])) +
                      (row['pending'] == true
                          ? '\nتوجد عمليات لم ترفع بعد'
                          : '')),
                  isThreeLine: true,
                ),
            ]);
          },
        ),
      );
}
