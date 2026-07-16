import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'tables.dart';
part 'app_database.g.dart';

@DriftDatabase(tables: [Products, StockMovements, Transactions, Customers, Promos,
  Employees, Attendance, Expenses, Payroll, Waste, Liquidity, Suppliers, Branches,
  Settings, ActivationsLocal, SyncQueue, CashierSessions, OnlineOrders])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.test() : super(NativeDatabase.memory());
  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(cashierSessions);
      }
      if (from < 3) {
        await m.addColumn(attendance, attendance.finalCash);
      }
      if (from < 4) {
        await m.addColumn(products, products.isOnline);
        await m.createTable(onlineOrders);
      }
      if (from < 5) {
        await m.addColumn(transactions, transactions.status);
        await m.addColumn(transactions, transactions.voidReason);
        await m.addColumn(transactions, transactions.voidedAt);
      }
      if (from < 6) {
        await m.addColumn(settings, settings.posGridColumns);
        await m.addColumn(settings, settings.bankName);
        await m.addColumn(settings, settings.bankAccount);
        await m.addColumn(settings, settings.bankHolder);
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = p.join(dir.path, 'nusa_kasir.sqlite');
    return NativeDatabase.createInBackground(File(file));
  });
}
