import 'package:drift/drift.dart';
import 'package:nusa_kasir/data/database/app_database.dart';

class CustomerRepository {
  final AppDatabase db;
  CustomerRepository(this.db);

  Future<int> addCustomer({required String name, String? phone, String? address}) =>
    db.into(db.customers).insert(CustomersCompanion.insert(
      name: name, phone: Value(phone), address: Value(address)));

  Future<Customer?> byId(int id) =>
    (db.select(db.customers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<Customer>> getCustomers() => db.select(db.customers).get();

  Future<void> addSpent(int id, int amount) async {
    final c = await byId(id);
    if (c == null) return;
    final total = c.totalSpent + amount;
    final points = total ~/ 100;
    final level = points >= 5000 ? 'Platinum' : points >= 1000 ? 'Gold' : 'Silver';
    await (db.update(db.customers)..where((t) => t.id.equals(id))).write(
      CustomersCompanion(totalSpent: Value(total), points: Value(points), level: Value(level)));
  }
}
