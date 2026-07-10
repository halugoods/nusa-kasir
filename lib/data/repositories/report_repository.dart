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
          conds.add(t.date.isAfter(from.subtract(const Duration(days: 1))));
        }
        if (to != null) {
          conds.add(t.date.isBefore(to.add(const Duration(days: 1))));
        }
        return conds.reduce((a, b) => a & b);
      });
    }
    q.orderBy([(t) => OrderingMode.desc(t.date)]);
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
}
