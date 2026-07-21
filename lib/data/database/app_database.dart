import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'tables.dart';
part 'app_database.g.dart';

@DriftDatabase(tables: [Categories, Products, StockMovements, Transactions, Customers, Promos,
  Employees, Attendance, Expenses, Payroll, Waste, Liquidity, Suppliers, Branches,
  Settings, ActivationsLocal, SyncQueue, CashierSessions, OnlineOrders])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.test() : super(NativeDatabase.memory());
  @override
  int get schemaVersion => 13;

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
      if (from < 7) {
        await m.addColumn(products, products.expiryDate);
        await m.addColumn(products, products.productType);
      }
      if (from < 8) {
        await m.addColumn(products, products.variantsJson);
        await m.addColumn(products, products.wholesaleJson);
      }
      if (from < 9) {
        await m.createTable(categories);
      }
      if (from < 10) {
        await m.addColumn(settings, settings.receiptFooter);
        await m.addColumn(settings, settings.storeLogoPath);
      }
      if (from < 11) {
        await m.addColumn(settings, settings.waTemplates);
        await m.addColumn(settings, settings.pointsPerRupiah);
        await m.addColumn(settings, settings.silverThreshold);
        await m.addColumn(settings, settings.goldThreshold);
        await m.addColumn(settings, settings.platinumThreshold);
      }
      if (from < 12) {
        await m.addColumn(employees, employees.phone);
        await m.addColumn(attendance, attendance.status);
      }
      if (from < 13) {
        await m.addColumn(employees, employees.photoPath);
        await m.addColumn(employees, employees.baseSalary);
        await m.addColumn(employees, employees.startDate);
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
