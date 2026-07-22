import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:drift/drift.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/finance_repository.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/data/repositories/report_repository.dart';
import 'package:nusa_kasir/data/repositories/transaction_repository.dart';
import 'package:nusa_kasir/data/repositories/supplier_repository.dart';
import 'package:nusa_kasir/data/repositories/customer_repository.dart';
import 'package:nusa_kasir/data/repositories/promo_repository.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';

class SpreadsheetService {
  final GoogleSignIn _signIn = GoogleSignIn(
    scopes: [SheetsApi.spreadsheetsScope],
  );

  final AppDatabase db;
  SpreadsheetService(this.db);

  Future<GoogleSignInAccount?> signIn() => _signIn.signIn();

  /// Try to restore previous session silently.
  Future<GoogleSignInAccount?> signInSilently() => _signIn.signInSilently();

  Future<void> signOut() => _signIn.disconnect();

  bool get isSignedIn => _signIn.currentUser != null;

  Future<SheetsApi?> _client() async {
    final authClient = await _signIn.authenticatedClient();
    if (authClient == null) return null;
    return SheetsApi(authClient);
  }

  /// Find or create a per-user spreadsheet.
  Future<String?> findOrCreate(String email) async {
    final api = await _client();
    if (api == null) return null;
    try {
      // Use email prefix as sheet name for uniqueness
      final shortName = email.split('@').first;
      final title = 'NUSA Kasir - $shortName';
      final sheet = await api.spreadsheets.create(Spreadsheet(
        properties: SpreadsheetProperties(title: title),
        sheets: [
          Sheet(properties: SheetProperties(title: 'Produk')),
          Sheet(properties: SheetProperties(title: 'Transaksi')),
          Sheet(properties: SheetProperties(title: 'Stok')),
          Sheet(properties: SheetProperties(title: 'Laporan')),
          Sheet(properties: SheetProperties(title: 'Keuangan')),
          Sheet(properties: SheetProperties(title: 'Karyawan')),
          Sheet(properties: SheetProperties(title: 'Pelanggan')),
          Sheet(properties: SheetProperties(title: 'Supplier')),
          Sheet(properties: SheetProperties(title: 'Promo')),
          Sheet(properties: SheetProperties(title: 'Presensi')),
        ],
      ));
      return sheet.spreadsheetId;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  SYNC PER TAB
  // ═══════════════════════════════════════════════════════════

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
        ['Invoice', 'Tanggal', 'Total', 'Diskon', 'Metode', 'Bayar', 'Kembali', 'Kasir', 'Status'],
        for (final t in txs)
          [t.invoice, '${t.date.day}/${t.date.month}/${t.date.year} ${t.date.hour.toString().padLeft(2, '0')}:${t.date.minute.toString().padLeft(2, '0')}', t.total, t.discount, t.paymentMethod, t.cashGiven ?? 0, t.cashReturn ?? 0, t.cashierName ?? '-', t.status],
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Transaksi!A1', values: rows), spreadsheetId, 'Transaksi!A1',
        valueInputOption: 'USER_ENTERED',
      );
      return true;
    } catch (_) { return false; }
  }

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
        ['Tanggal', 'Produk', 'Tipe', 'Qty', 'Catatan'],
        for (final m in movements)
          ['${m.date.day}/${m.date.month}/${m.date.year} ${m.date.hour}:${m.date.minute}', nameOf[m.productId] ?? '#${m.productId}', m.type, m.qty, m.note ?? ''],
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Stok!A1', values: rows), spreadsheetId, 'Stok!A1',
        valueInputOption: 'USER_ENTERED',
      );
      return true;
    } catch (_) { return false; }
  }

  Future<bool> syncLaporan(String spreadsheetId) async {
    final api = await _client();
    if (api == null) return false;
    try {
      final reportRepo = ReportRepository(db);
      final summary = await reportRepo.summary();
      final pl = await reportRepo.profitLoss();
      final rows = <List<dynamic>>[
        ['Metrik', 'Nilai'],
        ['Omzet', summary['omzet']],
        ['Jumlah Transaksi', summary['count']],
        ['Rata-rata Transaksi', summary['avg']],
        ['', ''],
        ['--- Laba Rugi ---', ''],
        ['Pendapatan', pl['pendapatan']],
        ['HPP', pl['hpp']],
        ['Laba Kotor', pl['labaKotor']],
        ['Pengeluaran', pl['expenses']],
        ['Payroll', pl['payroll']],
        ['Waste', pl['waste']],
        ['Likuiditas Masuk', pl['liquidityIn']],
        ['Likuiditas Keluar', pl['liquidityOut']],
        ['Total Beban', pl['totalBeban']],
        ['Laba Bersih', pl['labaBersih']],
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Laporan!A1', values: rows), spreadsheetId, 'Laporan!A1',
        valueInputOption: 'USER_ENTERED',
      );
      return true;
    } catch (_) { return false; }
  }

  Future<bool> syncKeuangan(String spreadsheetId) async {
    final api = await _client();
    if (api == null) return false;
    try {
      final repo = FinanceRepository(db);
      final expenses = await repo.getExpenses();
      final payroll = await repo.getPayroll();
      final waste = await repo.getWaste();
      final recurring = await repo.getRecurring();
      final liquidity = await repo.getLiquidity();
      final rows = <List<dynamic>>[
        ['TIPE', 'KATEGORI', 'KETERANGAN', 'JUMLAH', 'TANGGAL / INFO'],
        // Pengeluaran
        ...expenses.map((e) => ['Pengeluaran', e.category, e.description, e.amount, '${e.date.day}/${e.date.month}/${e.date.year}']),
        // Payroll
        ...payroll.map((p) => ['Payroll', 'Karyawan #${p.employeeId}', p.period, p.salary + p.bonus - p.deduction, p.status]),
        // Waste
        ...waste.map((w) => ['Waste', 'Produk #${w.productId}', w.reason ?? '', w.qty, '${w.date.day}/${w.date.month}/${w.date.year}']),
        // Recurring
        ...recurring.where((r) => r.active).map((r) => ['Berulang', r.category, r.description, r.amount, 'Next: ${r.nextDate.day}/${r.nextDate.month}/${r.nextDate.year}']),
        // Liquidity
        ...liquidity.map((l) => [l.type == 'in' ? 'Likuiditas Masuk' : 'Likuiditas Keluar', l.category, l.description, l.amount, '${l.date.day}/${l.date.month}/${l.date.year}']),
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Keuangan!A1', values: rows), spreadsheetId, 'Keuangan!A1',
        valueInputOption: 'USER_ENTERED',
      );
      return true;
    } catch (_) { return false; }
  }

  Future<bool> syncKaryawan(String spreadsheetId) async {
    final api = await _client();
    if (api == null) return false;
    try {
      final emps = await (db.select(db.employees)
            ..orderBy([(t) => OrderingTerm(expression: t.name, mode: OrderingMode.asc)]))
          .get();
      final rows = <List<dynamic>>[
        ['ID', 'Nama', 'Role', 'Status', 'No WA', 'Gaji Pokok', 'Mulai Kerja'],
        for (final e in emps)
          [e.id, e.name, e.role, e.status ?? 'Aktif', e.phone ?? '',
           e.baseSalary != null ? formatRupiah(e.baseSalary!) : '',
           e.startDate != null ? '${e.startDate!.day}/${e.startDate!.month}/${e.startDate!.year}' : ''],
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Karyawan!A1', values: rows), spreadsheetId, 'Karyawan!A1',
        valueInputOption: 'USER_ENTERED',
      );
      return true;
    } catch (_) { return false; }
  }

  Future<bool> syncPelanggan(String spreadsheetId) async {
    final api = await _client();
    if (api == null) return false;
    try {
      final custRepo = CustomerRepository(db);
      final customers = await custRepo.getCustomers();
      final rows = <List<dynamic>>[
        ['ID', 'Nama', 'No HP', 'Level', 'Total Belanja', 'Poin'],
        for (final c in customers)
          [c.id, c.name, c.phone ?? '', c.level, c.totalSpent, c.points],
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Pelanggan!A1', values: rows), spreadsheetId, 'Pelanggan!A1',
        valueInputOption: 'USER_ENTERED',
      );
      return true;
    } catch (_) { return false; }
  }

  Future<bool> syncSupplier(String spreadsheetId) async {
    final api = await _client();
    if (api == null) return false;
    try {
      final suppRepo = SupplierRepository(db);
      final suppliers = await suppRepo.getSuppliers();
      final rows = <List<dynamic>>[
        ['ID', 'Nama', 'Kontak', 'No HP', 'Alamat', 'Catatan'],
        for (final s in suppliers)
          [s.id, s.name, s.contactPerson ?? '', s.phone ?? '', s.address ?? '', s.note ?? ''],
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Supplier!A1', values: rows), spreadsheetId, 'Supplier!A1',
        valueInputOption: 'USER_ENTERED',
      );
      return true;
    } catch (_) { return false; }
  }

  Future<bool> syncPromo(String spreadsheetId) async {
    final api = await _client();
    if (api == null) return false;
    try {
      final promoRepo = PromoRepository(db);
      final promos = await promoRepo.getPromos();
      final rows = <List<dynamic>>[
        ['ID', 'Nama', 'Kode', 'Tipe', 'Nilai', 'Min Belanja', 'Berlaku', 'Kadaluarsa', 'Status', 'Terpakai'],
        for (final p in promos)
          [p.id, p.name, p.code, p.type, p.value, p.minBelanja,
           p.startDate != null ? '${p.startDate!.day}/${p.startDate!.month}/${p.startDate!.year}' : '',
           p.endDate != null ? '${p.endDate!.day}/${p.endDate!.month}/${p.endDate!.year}' : '',
           p.status, p.usedCount],
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Promo!A1', values: rows), spreadsheetId, 'Promo!A1',
        valueInputOption: 'USER_ENTERED',
      );
      return true;
    } catch (_) { return false; }
  }

  Future<bool> syncPresensi(String spreadsheetId) async {
    final api = await _client();
    if (api == null) return false;
    try {
      final atts = await (db.select(db.attendance)
            ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]))
          .get();
      final emps = await (db.select(db.employees)).get();
      final nameOf = {for (final e in emps) e.id: e.name};
      final rows = <List<dynamic>>[
        ['Tanggal', 'Karyawan', 'Role', 'Jam Masuk', 'Jam Pulang', 'Kas Awal', 'Kas Akhir', 'Status'],
        for (final a in atts)
          ['${a.date.day}/${a.date.month}/${a.date.year}', nameOf[a.employeeId] ?? '#${a.employeeId}',
           emps.where((e) => e.id == a.employeeId).firstOrNull?.role ?? '',
           a.checkIn ?? '-', a.checkOut ?? '-',
           a.pettyCash != null ? formatRupiah(a.pettyCash!) : '-',
           a.finalCash != null ? formatRupiah(a.finalCash!) : '-',
           a.status ?? 'Hadir'],
      ];
      await api.spreadsheets.values.update(
        ValueRange(range: 'Presensi!A1', values: rows), spreadsheetId, 'Presensi!A1',
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
    final e = await syncKaryawan(spreadsheetId);
    final c = await syncPelanggan(spreadsheetId);
    final sp = await syncSupplier(spreadsheetId);
    final pr = await syncPromo(spreadsheetId);
    final at = await syncPresensi(spreadsheetId);
    return p && t && s && l && k && e && c && sp && pr && at;
  }
}
