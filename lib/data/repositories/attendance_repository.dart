import 'package:drift/drift.dart';
import 'package:nusa_kasir/data/database/app_database.dart';

class AttendanceRepository {
  final AppDatabase db;
  AttendanceRepository(this.db);

  // ---- Employees ----
  Future<List<Employee>> getEmployees() =>
      (db.select(db.employees)
            ..orderBy([
              (t) => OrderingTerm(expression: t.name, mode: OrderingMode.asc)
            ]))
          .get();

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

  Future<void> updateEmployee({
    required int id,
    required String name,
    required String pin,
    required String role,
  }) =>
      (db.update(db.employees)..where((t) => t.id.equals(id))).write(
        EmployeesCompanion(
          name: Value(name),
          pin: Value(pin),
          role: Value(role),
        ),
      );

  Future<void> deleteEmployee(int id) =>
      (db.delete(db.employees)..where((t) => t.id.equals(id))).go();

  // ---- Attendance ----
  Future<AttendanceData?> getToday(int employeeId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final list = await (db.select(db.attendance)
          ..where((t) =>
              t.employeeId.equals(employeeId) &
              t.date.isBiggerThanValue(today))
          ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)])
          ..limit(1))
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
        await db.into(db.attendance)
            .insert(AttendanceCompanion.insert(employeeId: employeeId));
    await setPettyCash(id, amount);
  }

  /// Set final cash (kas akhir) for today's attendance record.
  Future<void> setFinalCashForToday(int employeeId, int amount) async {
    final today = await getToday(employeeId);
    final id = today?.id ??
        await db.into(db.attendance)
            .insert(AttendanceCompanion.insert(employeeId: employeeId));
    await (db.update(db.attendance)..where((t) => t.id.equals(id)))
        .write(AttendanceCompanion(finalCash: Value(amount)));
  }

  /// Check in with initial cash (kas awal wajib).
  Future<void> checkInWithCash(int employeeId, int cash) async {
    await checkIn(employeeId);
    await setPettyCashForToday(employeeId, cash);
  }

  /// Check out with final cash (kas akhir wajib).
  Future<void> checkOutWithCash(int employeeId, int cash) async {
    await checkOut(employeeId);
    await setFinalCashForToday(employeeId, cash);
  }

  Future<List<AttendanceData>> history({int? employeeId}) {
    final q = db.select(db.attendance);
    if (employeeId != null) {
      q.where((t) => t.employeeId.equals(employeeId));
    }
    q.orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]);
    return q.get();
  }
}
