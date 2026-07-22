import 'package:drift/drift.dart';
import 'package:nusa_kasir/data/database/app_database.dart';

class ShiftRepository {
  final AppDatabase db;
  ShiftRepository(this.db);

  /// Open a new shift session.
  Future<int> openShift({
    required int employeeId,
    required int startingCash,
    int? branchId,
    int? cashierSessionId,
  }) {
    return db.into(db.shiftSessions).insert(
          ShiftSessionsCompanion.insert(
            employeeId: employeeId,
            startingCash: Value(startingCash),
            branchId: Value(branchId),
            cashierSessionId: Value(cashierSessionId),
          ),
        );
  }

  /// Close an active shift, calculating expected cash from transactions
  /// and computing the difference (actual - expected).
  Future<void> closeShift({
    required int shiftId,
    required int actualCash,
    String? notes,
  }) async {
    final shift = await (db.select(db.shiftSessions)
          ..where((t) => t.id.equals(shiftId)))
        .getSingle();

    if (shift.status != 'Open') return;

    final now = DateTime.now();

    // Calculate expected cash from transactions during this shift
    final expectedCash = await _calculateExpectedCash(
      from: shift.openedAt,
      to: now,
      branchId: shift.branchId,
    );

    final difference = actualCash - expectedCash;

    await (db.update(db.shiftSessions)..where((t) => t.id.equals(shiftId)))
        .write(ShiftSessionsCompanion(
      status: const Value('Closed'),
      closedAt: Value(now),
      actualCash: Value(actualCash),
      expectedCash: Value(expectedCash),
      difference: Value(difference),
      notes: Value(notes),
    ));
  }

  /// Calculate expected cash total from transactions in a time range.
  Future<int> _calculateExpectedCash({
    required DateTime from,
    required DateTime to,
    int? branchId,
  }) async {
    // Sum totals from transactions within the shift period
    // We filter by date range and optionally branchId
    final query = db.select(db.transactions)
      ..where((t) => t.date.isBetweenValues(from, to) & t.status.equals('Normal'));

    if (branchId != null) {
      // Can't add another where clause easily with generated aliases,
      // so we'll filter in Dart
    }

    final txs = await query.get();
    final filtered = branchId != null
        ? txs.where((tx) => tx.branchId == branchId)
        : txs;

    int expected = 0;
    for (final tx in filtered) {
      expected += tx.total;
    }
    return expected;
  }

  /// Get the currently active (open) shift for the given employee.
  Future<ShiftSession?> getActiveShift(int employeeId) async {
    final list = await (db.select(db.shiftSessions)
          ..where((t) => t.employeeId.equals(employeeId) & t.status.equals('Open'))
          ..orderBy([
            (t) => OrderingTerm(expression: t.openedAt, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .get();
    return list.isNotEmpty ? list.first : null;
  }

  /// Get shifts within a date range (history).
  Future<List<ShiftSession>> getShiftsByDate(DateTime from, DateTime to) {
    return (db.select(db.shiftSessions)
          ..where((t) => t.openedAt.isBetweenValues(from, to))
          ..orderBy([
            (t) => OrderingTerm(expression: t.openedAt, mode: OrderingMode.desc)
          ]))
        .get();
  }

  /// Get shift summary for a date range.
  Future<Map<String, dynamic>> getShiftSummary(DateTime from, DateTime to) async {
    final list = await getShiftsByDate(from, to);
    int totalStarting = 0, totalExpected = 0, totalActual = 0, totalDiff = 0;
    for (final s in list) {
      totalStarting += s.startingCash;
      totalExpected += s.expectedCash;
      totalActual += s.actualCash;
      totalDiff += s.difference;
    }
    return {
      'totalShifts': list.length,
      'totalStarting': totalStarting,
      'totalExpected': totalExpected,
      'totalActual': totalActual,
      'totalDifference': totalDiff,
    };
  }
}
