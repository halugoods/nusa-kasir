import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:nusa_kasir/data/database/app_database.dart';

class ReportRepository {
  final AppDatabase db;
  ReportRepository(this.db);

  Future<List<Transaction>> getTransactions(
      {DateTime? from, DateTime? to}) async {
    final q = db.select(db.transactions);
    if (from != null || to != null) {
      q.where((t) {
        final conds = <Expression<bool>>[];
        if (from != null) {
          conds.add(t.date
              .isBiggerThan(Constant(from.subtract(const Duration(days: 1)))));
        }
        if (to != null) {
          conds.add(t.date
              .isSmallerThan(Constant(to.add(const Duration(days: 1)))));
        }
        return conds.reduce((a, b) => a & b);
      });
    }
    q.orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]);
    return q.get();
  }

  /// Returns summary stats for a period.
  /// Keys: omzet (int), count (int), avg (int), items (List<Transaction>).
  Future<Map<String, dynamic>> summary({DateTime? from, DateTime? to}) async {
    final list = await getTransactions(from: from, to: to);
    final omzet = list.fold(0, (int sum, t) => sum + t.total);
    final count = list.length;
    final avg = count == 0 ? 0 : (omzet / count).round();
    return {'omzet': omzet, 'count': count, 'avg': avg, 'items': list};
  }

  /// Full Profit & Loss (Laba Rugi) for a date range.
  /// Returns a map with all line items.
  Future<Map<String, dynamic>> profitLoss({
    DateTime? from,
    DateTime? to,
  }) async {
    // ── Revenue (pendapatan) ──────────────────────────────────────
    final txList = await getTransactions(from: from, to: to);
    final normalTx = txList.where((t) => t.status == 'Normal');
    final pendapatan = normalTx.fold(0, (int s, t) => s + t.total);

    // ── HPP (Harga Pokok Penjualan) ───────────────────────────────
    int hpp = 0;
    // Collect all product IDs to batch-lookup buy prices
    final productIds = <int>{};
    for (final tx in normalTx) {
      final items = _parseItems(tx.items);
      for (final it in items) {
        final pid = it['productId'] as int?;
        if (pid != null) productIds.add(pid);
      }
    }
    // Batch lookup
    final products = await (db.select(db.products)
      ..where((p) => p.id.isIn(productIds))).get();
    final priceMap = {for (final p in products) p.id: p.buyPrice};

    for (final tx in normalTx) {
      final items = _parseItems(tx.items);
      for (final it in items) {
        final pid = it['productId'] as int?;
        final qty = it['qty'] as int? ?? 0;
        if (pid != null) {
          hpp += (priceMap[pid] ?? 0) * qty;
        }
      }
    }

    final labaKotor = pendapatan - hpp;

    // ── Expenses (pengeluaran) ────────────────────────────────────
    final expenses = await _filtered(db.select(db.expenses), from: from, to: to);
    final totalExpenses = expenses.fold(0, (int s, e) => s + e.amount);

    // ── Payroll ───────────────────────────────────────────────────
    final payroll = await _filtered(db.select(db.payroll), from: from, to: to);
    final totalPayroll =
        payroll.fold(0, (int s, p) => s + p.salary + p.bonus - p.deduction);

    // ── Waste (loss from spoiled goods) ───────────────────────────
    final waste = await _filtered(db.select(db.waste), from: from, to: to);
    int totalWaste = 0;
    for (final w in waste) {
      final prod = priceMap[w.productId] ??
          (await (db.select(db.products)
            ..where((p) => p.id.equals(w.productId)))
              .getSingleOrNull())?.buyPrice ?? 0;
      totalWaste += prod * w.qty;
    }

    // ── Liquidity ─────────────────────────────────────────────────
    final liquidity =
        await _filtered(db.select(db.liquidity), from: from, to: to);
    final liquidityIn =
        liquidity.where((l) => l.type == 'in').fold(0, (int s, l) => s + l.amount);
    final liquidityOut =
        liquidity.where((l) => l.type == 'out').fold(0, (int s, l) => s + l.amount);

    // ── Totals ────────────────────────────────────────────────────
    final totalBeban = totalExpenses + totalPayroll + totalWaste + liquidityOut;
    final labaBersih = labaKotor - totalBeban + liquidityIn;

    return {
      'pendapatan': pendapatan,
      'hpp': hpp,
      'labaKotor': labaKotor,
      'expenses': totalExpenses,
      'payroll': totalPayroll,
      'waste': totalWaste,
      'liquidityIn': liquidityIn,
      'liquidityOut': liquidityOut,
      'totalBeban': totalBeban,
      'labaBersih': labaBersih,
      'txCount': normalTx.length,
    };
  }

  List<Map<String, dynamic>> _parseItems(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Helper: apply date filter to a query.
  Future<List<T>> _filtered<T>(
    Selectable<T> query, {
    DateTime? from,
    DateTime? to,
  }) async {
    // We rely on the generated query being filtered by the caller
    // This is a simpler approach — fetch all then filter in Dart
    final list = await query.get();
    return list.where((item) {
      // Drift data classes have a `date` field convention — use dynamic
      final d = (item as dynamic).date as DateTime?;
      if (d == null) return true;
      if (from != null && d.isBefore(from)) return false;
      if (to != null && d.isAfter(to.add(const Duration(days: 1)))) return false;
      return true;
    }).toList().cast<T>();
  }
}
