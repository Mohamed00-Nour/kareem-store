import 'package:cloud_firestore/cloud_firestore.dart';
import '../expenses/expense_service.dart';
import '../models/Employee.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addEmployee(Employee employee) async {
    await _firestore.collection('employees').doc(employee.id).set(employee.toMap());
  }

  Future<Employee> getEmployee(String id) async {
    DocumentSnapshot doc = await _firestore.collection('employees').doc(id).get();
    return Employee.fromMap(doc.data() as Map<String, dynamic>, doc.id);
  }

  Future<void> updateEmployee(Employee employee) async {
    await _firestore.collection('employees').doc(employee.id).update(employee.toMap());
  }

  Stream<List<Employee>> getEmployees() {
    return _firestore.collection('employees').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Employee.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();
    });
  }

  Stream<double> getTotalBorrowValueStream() {
    return FirebaseFirestore.instance.collection('employees').snapshots().map((snapshot) {
      double totalBorrowValue = 0.0;
      for (var doc in snapshot.docs) {
        Employee employee = Employee.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        totalBorrowValue += employee.borrows.fold(0.0, (sum, borrow) => sum + double.parse(borrow.value));
      }
      return totalBorrowValue;
    });
  }

  Stream<double> getTotalMedicineValueStream() {
    return FirebaseFirestore.instance.collection('employees').snapshots().map((snapshot) {
      double totalMedicineValue = 0.0;
      for (var doc in snapshot.docs) {
        Employee employee = Employee.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        totalMedicineValue += employee.medicines.fold(0.0, (sum, medicine) => sum + double.parse(medicine.value));
      }
      return totalMedicineValue;
    });
  }

  Future<void> addAttendance(Attendance attendance) async {
    await FirebaseFirestore.instance
        .collection('employees')
        .doc(attendance.employeeId)
        .update({
      'attendance': FieldValue.arrayUnion([attendance.toMap()])
    });
  }

  Stream<double> getTotalExpensesValueStream() {
    return _firestore.collection('expenses').snapshots().map((snapshot) {
      return ExpenseService.sumExpensesDocs(snapshot.docs);
    });
  }

  Stream<double> getMonthlyExpensesSumStream() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1)
        .subtract(const Duration(seconds: 1));
    return getMonthlyExpensesSumStreamForDateRange(start, end);
  }

  Stream<double> getMonthlyExpensesSumStreamForDateRange(
    DateTime start,
    DateTime end,
  ) {
    return _firestore.collection('expenses').snapshots().map((snapshot) {
      return ExpenseService.sumExpensesDocs(
        snapshot.docs,
        start: start,
        end: end,
      );
    });
  }

  static Map<String, double> _netProfitAfterExpenses(
    Map<String, double> profitAndSum,
    double totalExpenses,
  ) {
    return {
      'totalProfitMargin': profitAndSum['totalProfitMargin']! - totalExpenses,
      'totalSum': profitAndSum['totalSum']!,
      'grossProfitMargin': profitAndSum['totalProfitMargin']!,
      'totalExpenses': totalExpenses,
    };
  }

  Stream<double> getTotalSparePartsValueStream() {
    return FirebaseFirestore.instance.collection('spare_parts').snapshots().map((snapshot) {
      double total = 0.0;
      for (var doc in snapshot.docs) {
        total += double.tryParse(doc['value']) ?? 0.0;
      }
      return total;
    });
  }

  static double _docNum(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static Map<String, double> _sumSalesInvoices(QuerySnapshot snapshot) {
    var totalProfitMargin = 0.0;
    var totalSum = 0.0;
    for (final doc in snapshot.docs) {
      totalProfitMargin += _docNum(doc['profitMargin']);
      totalSum += _docNum(doc['totalSum']);
    }
    return {
      'totalProfitMargin': totalProfitMargin,
      'totalSum': totalSum,
    };
  }

  static Map<String, double> _netWithReturns(
    Map<String, double> sales,
    QuerySnapshot returnsSnap,
  ) {
    var returnProfit = 0.0;
    var returnSum = 0.0;
    for (final doc in returnsSnap.docs) {
      returnProfit += _docNum(doc['profitMargin']);
      returnSum += _docNum(doc['totalSum']);
    }
    return {
      'totalProfitMargin': sales['totalProfitMargin']! + returnProfit,
      'totalSum': sales['totalSum']! - returnSum,
    };
  }

  Stream<Map<String, double>> getTotalProfitAndSumStream() {
    return _firestore.collection('invoices').snapshots().asyncMap(
      (salesSnap) async {
        final returnsSnap =
            await _firestore.collection('returnInvoices').get();
        final expensesSnap = await _firestore.collection('expenses').get();
        final gross =
            _netWithReturns(_sumSalesInvoices(salesSnap), returnsSnap);
        final expenses = ExpenseService.sumExpensesDocs(expensesSnap.docs);
        return _netProfitAfterExpenses(gross, expenses);
      },
    );
  }

  Stream<double> getTotalBuyingInvoicesSumStream() {
    return _firestore.collection('buying invoices').snapshots().map((snapshot) {
      double totalSum = 0.0;
      for (var doc in snapshot.docs) {
        totalSum += doc['totalSum'] ?? 0.0;
      }
      return totalSum;
    });
  }

  Stream<Map<String, double>> getMonthlyProfitAndSumStream() {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 1)
        .subtract(const Duration(seconds: 1));

    return _monthlyNetProfitAndSumStream(startOfMonth, endOfMonth);
  }

  Stream<double> getMonthlyBuyingInvoicesSumStream() {
    DateTime now = DateTime.now();
    DateTime startOfMonth = DateTime(now.year, now.month, 1);
    DateTime endOfMonth = DateTime(now.year, now.month + 1, 1).subtract(Duration(seconds: 1));

    return _firestore.collection('buying invoices')
        .where('date', isGreaterThanOrEqualTo: startOfMonth)
        .where('date', isLessThanOrEqualTo: endOfMonth)
        .snapshots()
        .map((snapshot) {
      double totalSum = 0.0;
      for (var doc in snapshot.docs) {
        totalSum += doc['totalSum'] ?? 0.0;
      }
      return totalSum;
    });
  }

  Stream<Map<String, double>> getMonthlyProfitAndSumStreamForDateRange(
      DateTime start, DateTime end) {
    return _monthlyNetProfitAndSumStream(start, end);
  }

  Stream<Map<String, double>> _monthlyNetProfitAndSumStream(
    DateTime start,
    DateTime end,
  ) {
    return _firestore
        .collection('invoices')
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThanOrEqualTo: end)
        .snapshots()
        .asyncMap((salesSnap) async {
      final returnsSnap = await _firestore
          .collection('returnInvoices')
          .where('date', isGreaterThanOrEqualTo: start)
          .where('date', isLessThanOrEqualTo: end)
          .get();
      final expensesSnap = await _firestore.collection('expenses').get();
      final gross =
          _netWithReturns(_sumSalesInvoices(salesSnap), returnsSnap);
      final expenses = ExpenseService.sumExpensesDocs(
        expensesSnap.docs,
        start: start,
        end: end,
      );
      return _netProfitAfterExpenses(gross, expenses);
    });
  }

  Stream<double> getMonthlyBuyingInvoicesSumStreamForDateRange(DateTime start, DateTime end) {
    return _firestore.collection('buying invoices')
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThanOrEqualTo: end)
        .snapshots()
        .map((snapshot) {
      double totalSum = 0.0;
      for (var doc in snapshot.docs) {
        totalSum += doc['totalSum'] ?? 0.0;
      }
      return totalSum;
    });
  }

  Future<List<DateTime>> getDistinctMonths() async {
    QuerySnapshot snapshot = await _firestore.collection('invoices').get();
    Set<DateTime> months = {};
    for (var doc in snapshot.docs) {
      Timestamp timestamp = doc['date'];
      DateTime date = timestamp.toDate();
      DateTime month = DateTime(date.year, date.month);
      months.add(month);
    }
    return months.toList()..sort((a, b) => b.compareTo(a));
  }

}