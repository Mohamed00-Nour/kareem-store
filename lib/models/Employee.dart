class Employee {
  String id;
  String name;
  final double salary;// Add this field
  DateTime startDate;
  List<Borrow> borrows;
  List<Medicine> medicines;
  List<Attendance> attendance;
  int order;

  Employee({
    required this.id,
    required this.name,
    required this.salary, // Add this field
    required this.startDate,
    required this.borrows,
    required this.medicines,
    required this.attendance,
    required this.order,
  });

  factory Employee.fromMap(Map<String, dynamic> data, String documentId) {
    return Employee(
      id: documentId,
      name: data['name'],
      salary: data['salary'], // Add this field
      startDate: DateTime.parse(data['startDate']),
      borrows: (data['borrows'] as List).map((item) => Borrow.fromMap(item)).toList(),
      medicines: (data['medicines'] as List).map((item) => Medicine.fromMap(item)).toList(),
      attendance: (data['attendance'] as List).map((item) => Attendance.fromMap(item)).toList(),
      order: data['order'] ?? 0, // Provide a default value for order
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'salary': salary, // Add this field
      'startDate': startDate.toIso8601String(),
      'borrows': borrows.map((item) => item.toMap()).toList(),
      'medicines': medicines.map((item) => item.toMap()).toList(),
      'attendance': attendance.map((item) => item.toMap()).toList(),
      'order': order,
    };
  }
}

class Borrow {
  String id;
   String employeeId;
  String employeeName;
  String date;
  String responsible;
  String value;

  Borrow({
    required this.id,required this.employeeId,
    required this.date, required this.responsible, required this.value , required this.employeeName});

  factory Borrow.fromMap(Map<String, dynamic> data) {
    return Borrow(
      id: data['id']??'',
      employeeId: data['employeeId']??'',
      employeeName: data['employeeName'],
      date: data['date'],
      responsible: data['responsible'],
      value: data['value'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'date': date,
      'responsible': responsible,
      'value': value,
    };
  }
}

class Medicine {
  String id;
  String employeeId;
  String employeeName;
  String date;
  String responsible;
  String value;

  Medicine({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.responsible,
    required this.value,
  });

  factory Medicine.fromMap(Map<String, dynamic> data) {
    return Medicine(
      id: data['id'] ?? '',
      employeeId: data['employeeId'] ?? '',
      employeeName: data['employeeName'] ?? '',
      date: data['date']??'',
      responsible: data['responsible']??'',
      value: data['value']??'',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'date': date,
      'responsible': responsible,
      'value': value,
    };
  }
}

class Attendance {
  String id;
  String employeeId;
  String employeeName;
  DateTime dateTime;
  final bool isPresent;
  String dayName;
  String attendHour;
  String leaveHour;
  String responsible;

  Attendance({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.dateTime,
    required this.isPresent,
    required this.dayName,
    required this.attendHour,
    required this.leaveHour,
    required this.responsible,
  });

  factory Attendance.fromMap(Map<String, dynamic> data) {
    return Attendance(
      id: data['id'] ?? '',
      employeeId: data['employeeId'] ?? '',
      employeeName: data['employeeName'] ?? '',
      dateTime: DateTime.parse(data['dateTime']),
      isPresent: data['isPresent'],
      dayName: data['dayName'],
      attendHour: data['attendHour'],
      leaveHour: data['leaveHour'],
      responsible: data['responsible'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'dateTime': dateTime.toIso8601String(),
      'isPresent': isPresent,
      'dayName': dayName,
      'attendHour': attendHour,
      'leaveHour': leaveHour,
      'responsible': responsible,
    };
  }
}