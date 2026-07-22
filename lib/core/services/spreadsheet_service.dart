import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:drift/drift.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/data/repositories/report_repository.dart';
import 'package:nusa_kasir/data/repositories/transaction_repository.dart';
import 'package:nusa_kasir/data/repositories/finance_repository.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';

class SpreadsheetService {
  final GoogleSignIn _signIn = GoogleSignIn(
    scopes: [SheetsApi.spreadsheetsScope],
  );

  final AppDatabase db;
  SpreadsheetService(this.db);

  Future<GoogleSignInAccount?> signIn() => _signIn.signIn();
  Future<void> signOut() => _signIn.disconnect();
  bool get isSignedIn => _signIn.currentUser != null;

  Future<SheetsApi?> _client() async {
    final authClient = await _signIn.authenticatedClient();
    if (authClient == null) return null;
    return SheetsApi(authClient);
  }

  /// Find spreadsheet by title, or create one with tabs.
  Future<String?> findOrCreate(String title) async {
    final api = await _client();
    if (api == null) return null;
    try {
      final sheet = await api.spreadsheets.create(Spreadsheet(
        properties: SpreadsheetProperties(title: title),
        sheets: [
          Sheet(properties: SheetProperties(title: 'Produk')),
          Sheet(properties: SheetProperties(title: 'Transaksi')),
          Sheet(properties: SheetProperties(title: 'Stok')),
          Sheet(properties: SheetProperties(title: 'Laporan')),
          Sheet(properties: SheetProperties(title: 'Keuangan')),
        ],
      ));
      return sheet.spreadsheetId;
    } catch (_) {
      return null;
    }
  }

  Future<bool> syncProducts(String spreadsheetId) async {
    final api = await _client();
    if (api == null) return false;
    try {
      final repo = ProductRepository(db);
      final products = await repo.getProducts();
      final rows = <List<dynamic>>[
        ['ID', 'Nama', 'SKU', 'Barcode', 'Kategori', 'Harga Beli', 'Harga Jual', 'Stok', 'Stok Min'],
        for (final p in products)
          [p.id, p.name, p.sku ?? '', p.barcode ?? '', p.category, p.buyPrice, p.sellPrice, p.stock, p.minStock],
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Produk!A1', values: rows), spreadsheetId, 'Produk!A1',
        valueInputOption: 'USER_ENTERED',
      );
      return true;
    } catch (_) { return false; }
  }

  Future<bool> syncTransactions(String spreadsheetId) async {
    final api = await _client();
    if (api == null) return false;
    try {
      final repo = TransactionRepository(db);
      final txs = await repo.getTransactions();
      final rows = <List<dynamic>>[
        ['Invoice', 'Tanggal', 'Total', 'Diskon', 'Metode', 'Bayar', 'Kembali', 'Kasir'],
        for (final t in txs)
          [t.invoice, '${t.date.day}/${t.date.month}/${t.date.year}', t.total, t.discount, t.paymentMethod, t.cashGiven ?? 0, t.cashReturn ?? 0, t.cashierName ?? '-'],
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Transaksi!A1', values: rows), spreadsheetId, 'Transaksi!A1',
        valueInputOption: 'USER_ENTERED',
      );
      return true;
    } catch (_) { return false; }
  }

  /// Sync stock movements to 'Stok' sheet.
  Future<bool> syncStock(String spreadsheetId) async {
    final api = await _client();
    if (api == null) return false;
    try {
      final movements = await (db.select(db.stockMovements)
            ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]))
          .get();
      final products = await ProductRepository(db).getProducts();
      final nameOf = {for (final p in products) p.id: p.name};
      final rows = <List<dynamic>>[
        ['Tanggal', 'Produk', 'Tipe', 'Qty'],
        for (final m in movements)
          ['${m.date.day}/${m.date.month}/${m.date.year} ${m.date.hour}:${m.date.minute}', nameOf[m.productId] ?? '#${m.productId}', m.type, m.qty],
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Stok!A1', values: rows), spreadsheetId, 'Stok!A1',
        valueInputOption: 'USER_ENTERED',
      );
      return true;
    } catch (_) { return false; }
  }

  /// Sync financial summary to 'Laporan' sheet.
  Future<bool> syncLaporan(String spreadsheetId) async {
    final api = await _client();
    if (api == null) return false;
    try {
      final reportRepo = ReportRepository(db);
      final summary = await reportRepo.summary();
      final rows = <List<dynamic>>[
        ['Metrik', 'Nilai'],
        ['Omzet', summary['omzet']],
        ['Jumlah Transaksi', summary['count']],
        ['Rata-rata Transaksi', summary['avg']],
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Laporan!A1', values: rows), spreadsheetId, 'Laporan!A1',
        valueInputOption: 'USER_ENTERED',
      );
      return true;
    } catch (_) { return false; }
  }

  /// Sync keuangan (expenses, payroll, liquidity) to 'Keuangan' sheet.
  Future<bool> syncKeuangan(String spreadsheetId) async {
    final api = await _client();
    if (api == null) return false;
    try {
      final repo = FinanceRepository(db);
      final expenses = await repo.getExpenses();
      final payroll = await repo.getPayroll();
      final recurring = await repo.getRecurring();
      final rows = <List<dynamic>>[
        ['TIPE', 'KATEGORI', 'KETERANGAN', 'JUMLAH', 'TANGGAL'],
        // Section: Expenses
        ...expenses.map((e) => ['Pengeluaran', e.category, e.description, formatRupiah(e.amount), '${e.date.day}/${e.date.month}/${e.date.year}']),
        // Section: Payroll
        ...payroll.map((p) => ['Payroll', 'Karyawan ID ${p.employeeId}', p.period, formatRupiah(p.salary + p.bonus - p.deduction), '']),
        // Section: Recurring
        ...recurring.where((r) => r.active).map((r) => ['Berulang', r.category, r.description, formatRupiah(r.amount), r.frequency]),
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Keuangan!A1', values: rows), spreadsheetId, 'Keuangan!A1',
        valueInputOption: 'USER_ENTERED',
      );
      return true;
    } catch (_) { return false; }
  }

  Future<bool> syncAll(String spreadsheetId) async {
    final p = await syncProducts(spreadsheetId);
    final t = await syncTransactions(spreadsheetId);
    final s = await syncStock(spreadsheetId);
    final l = await syncLaporan(spreadsheetId);
    final k = await syncKeuangan(spreadsheetId);
    return p && t && s && l && k;
  }
}
