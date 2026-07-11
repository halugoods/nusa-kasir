import 'package:drift/drift.dart';
import 'package:nusa_kasir/data/database/app_database.dart';

class FinanceRepository {
  final AppDatabase db;
  FinanceRepository(this.db);

  // ---- Expenses ----
  Future<int> addExpense({
    required String category,
    required String description,
    required int amount,
  }) {
    return db.into(db.expenses).insert(ExpensesCompanion.insert(
          category: category,
          description: description,
          amount: amount,
        ));
  }

  Future<List<Expense>> getExpenses() =>
      (db.select(db.expenses)
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)
            ]))
          .get();

  // ---- Payroll ----
  Future<int> addPayroll({
    required int employeeId,
    required String period,
    required int salary,
    int bonus = 0,
    int deduction = 0,
    String? notes,
    String status = 'Pending',
  }) {
    return db.into(db.payroll).insert(PayrollCompanion.insert(
          employeeId: employeeId,
          period: period,
          salary: salary,
          bonus: Value(bonus),
          deduction: Value(deduction),
          notes: Value(notes),
          status: Value(status),
        ));
  }

  Future<List<PayrollData>> getPayroll() =>
      (db.select(db.payroll)
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)
            ]))
          .get();

  // ---- Waste ----
  Future<int> addWaste({
    required int productId,
    required int qty,
    String? reason,
    String type = 'Expired',
  }) {
    return db.into(db.waste).insert(WasteCompanion.insert(
          productId: productId,
          qty: qty,
          reason: Value(reason),
          type: Value(type),
        ));
  }

  Future<List<WasteData>> getWaste() =>
      (db.select(db.waste)
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)
            ]))
          .get();

  // ---- Liquidity ----
  Future<int> addLiquidity({
    required String type, // 'in' | 'out'
    required String category,
    required String description,
    required int amount,
    String? method,
  }) {
    return db.into(db.liquidity).insert(LiquidityCompanion.insert(
          type: type,
          category: category,
          description: description,
          amount: amount,
          method: Value(method),
        ));
  }

  Future<List<LiquidityData>> getLiquidity() =>
      (db.select(db.liquidity)
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)
            ]))
          .get();

  // ---- Delete ----
  Future<void> deleteExpense(int id) =>
      (db.delete(db.expenses)..where((t) => t.id.equals(id))).go();

  Future<void> deletePayroll(int id) =>
      (db.delete(db.payroll)..where((t) => t.id.equals(id))).go();

  Future<void> deleteWaste(int id) =>
      (db.delete(db.waste)..where((t) => t.id.equals(id))).go();

  Future<void> deleteLiquidity(int id) =>
      (db.delete(db.liquidity)..where((t) => t.id.equals(id))).go();

  // ---- Payroll status ----
  Future<void> updatePayrollStatus(int id, String status) =>
      (db.update(db.payroll)..where((t) => t.id.equals(id)))
          .write(PayrollCompanion(status: Value(status)));
}
