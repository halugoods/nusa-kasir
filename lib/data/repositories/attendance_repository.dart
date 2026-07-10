import 'package:drift/drift.dart';
import 'package:nusa_kasir/data/database/app_database.dart';

class AttendanceRepository {
  final AppDatabase db;
  AttendanceRepository(this.db);

  // ---- Employees ----
  Future<List<Employee>> getEmployees() =>
      (db.select(db.employees)..orderBy([(t) => OrderingMode.asc(t.name)])).get();

  Future<int> addEmployee({
    required String name,
    required String pin,
    required String role,
    int? branchId,
  }) {
    return db.into(db.employees).insert(EmployeesCompanion.insert(
          name: name,
          pin: pin,
          role: role,
          branchId: Value(branchId),
        ));
  }

  // ---- Attendance ----
  Future<Attendance?> getToday(int employeeId) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    final list = await (db.select(db.attendance)
          ..where((t) =>
              t.employeeId.equals(employeeId) & t.date.isAfter(start)))
        .get();
    return list.isNotEmpty ? list.first : null;
  }

  Future<void> checkIn(int employeeId) async {
    final now = DateTime.now();
    final today = await getToday(employeeId);
    final time = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    if (today == null) {
      await db.into(db.attendance).insert(AttendanceCompanion.insert(
            employeeId: employeeId,
            checkIn: Value(time),
          ));
    } else {
      await (db.update(db.attendance)
            ..where((t) => t.id.equals(today.id)))
          .write(AttendanceCompanion(checkIn: Value(time)));
    }
  }

  Future<void> checkOut(int employeeId) async {
    final now = DateTime.now();
    final today = await getToday(employeeId);
    final time = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    if (today == null) {
      await db.into(db.attendance).insert(AttendanceCompanion.insert(
            employeeId: employeeId,
            checkOut: Value(time),
          ));
    } else {
      await (db.update(db.attendance)
            ..where((t) => t.id.equals(today.id)))
          .write(AttendanceCompanion(checkOut: Value(time)));
    }
  }

  Future<void> setPettyCash(int attendanceId, int amount) =>
      (db.update(db.attendance)..where((t) => t.id.equals(attendanceId)))
          .write(AttendanceCompanion(pettyCash: Value(amount)));

  Future<void> setPettyCashForToday(int employeeId, int amount) async {
    final today = await getToday(employeeId);
    final id = today?.id ??
        await db.into(db.attendance).insert(
            AttendanceCompanion.insert(employeeId: employeeId));
    await setPettyCash(id, amount);
  }

  Future<List<Attendance>> history({int? employeeId}) {
    final q = db.select(db.attendance);
    if (employeeId != null) {
      q.where((t) => t.employeeId.equals(employeeId));
    }
    q.orderBy([(t) => OrderingMode.desc(t.date)]);
    return q.get();
  }
}
