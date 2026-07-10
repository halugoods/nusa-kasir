import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/features/pos/cart.dart';

class TransactionRepository {
  final AppDatabase db;
  TransactionRepository(this.db);

  Future<int> saveTransaction({
    required List<CartItem> items,
    required int total,
    required String paymentMethod,
    int discount = 0,
    int? customerId,
    int? cashGiven,
    int? cashReturn,
    String? cashierName,
    int? branchId,
  }) async {
    final invoice = 'INV-${DateTime.now().millisecondsSinceEpoch}';
    final itemsJson = jsonEncode(items.map((e) => {
      'productId': e.productId, 'name': e.name, 'qty': e.qty, 'price': e.price
    }).toList());
    return db.into(db.transactions).insert(TransactionsCompanion.insert(
      invoice: invoice,
      items: itemsJson,
      total: Value(total),
      discount: Value(discount),
      paymentMethod: Value(paymentMethod),
      customerId: Value(customerId),
      cashGiven: Value(cashGiven),
      cashReturn: Value(cashReturn),
      cashierName: Value(cashierName),
      branchId: Value(branchId),
    ));
  }

  Future<List<Transaction>> getTransactions() =>
      db.select(db.transactions).get();

  Future<List<Transaction>> getToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return (db.select(db.transactions)
          ..where((t) => t.date.isBiggerThanValue(today)))
        .get();
  }
}
