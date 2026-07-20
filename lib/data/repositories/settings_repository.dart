import 'dart:convert' as dart_convert;
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:drift/drift.dart';

class SettingsRepository {
  final AppDatabase db;
  SettingsRepository(this.db);

  Future<String> getStoreName() async {
    final row = await db.select(db.settings).getSingleOrNull();
    return row?.storeName ?? '';
  }

  Future<void> ensureRow() async {
    if (await db.select(db.settings).getSingleOrNull() == null) {
      await db.into(db.settings).insert(SettingsCompanion.insert());
    }
  }

  Future<void> setStoreName(String name) async {
    await ensureRow();
    await (db.update(db.settings)..where((t) => t.id.equals(1)))
        .write(SettingsCompanion(storeName: Value(name)));
  }

  Future<void> setQris(String v) async {
    await ensureRow();
    await (db.update(db.settings)..where((t) => t.id.equals(1)))
        .write(SettingsCompanion(qrisString: Value(v)));
  }

  Future<String?> getQris() async =>
      (await db.select(db.settings).getSingleOrNull())?.qrisString;

  Future<String?> getThemeMode() async =>
      (await db.select(db.settings).getSingleOrNull())?.themeMode;

  Future<void> setThemeMode(String mode) async {
    await ensureRow();
    await (db.update(db.settings)..where((t) => t.id.equals(1)))
        .write(SettingsCompanion(themeMode: Value(mode)));
  }

  Future<String?> getPrinterAddress() async =>
      (await db.select(db.settings).getSingleOrNull())?.posPrefix;

  Future<void> setPrinterAddress(String address) async {
    await ensureRow();
    await (db.update(db.settings)..where((t) => t.id.equals(1)))
        .write(SettingsCompanion(posPrefix: Value(address)));
  }

  // Grid columns for POS screen (1, 2, or 3)
  Future<int> getPosGridColumns() async =>
      (await db.select(db.settings).getSingleOrNull())?.posGridColumns ?? 2;

  Future<void> setPosGridColumns(int cols) async {
    await ensureRow();
    await (db.update(db.settings)..where((t) => t.id.equals(1)))
        .write(SettingsCompanion(posGridColumns: Value(cols)));
  }

  // Grid columns for Products screen (1 or 2)
  Future<int> getProductsGridColumns() async {
    // Reuse the posGridColumns field for simplicity, default to 2
    final row = await db.select(db.settings).getSingleOrNull();
    return row?.posGridColumns != null ? (row!.posGridColumns > 2 ? 2 : row.posGridColumns) : 2;
  }

  Future<void> setProductsGridColumns(int cols) async {
    await ensureRow();
    // Store products grid in the same field — they share the same preference
    // but we limit to 1-2 for products screen
    final clamped = cols.clamp(1, 2);
    await (db.update(db.settings)..where((t) => t.id.equals(1)))
        .write(SettingsCompanion(posGridColumns: Value(clamped)));
  }

  // Bank transfer settings
  Future<String?> getBankName() async =>
      (await db.select(db.settings).getSingleOrNull())?.bankName;

  Future<String?> getBankAccount() async =>
      (await db.select(db.settings).getSingleOrNull())?.bankAccount;

  Future<String?> getBankHolder() async =>
      (await db.select(db.settings).getSingleOrNull())?.bankHolder;

  Future<void> setBankInfo({String? name, String? account, String? holder}) async {
    await ensureRow();
    final c = SettingsCompanion(
      bankName: name != null ? Value(name) : const Value.absent(),
      bankAccount: account != null ? Value(account) : const Value.absent(),
      bankHolder: holder != null ? Value(holder) : const Value.absent(),
    );
    await (db.update(db.settings)..where((t) => t.id.equals(1))).write(c);
  }

  // ── Receipt footer ──
  Future<String?> getReceiptFooter() async =>
      (await db.select(db.settings).getSingleOrNull())?.receiptFooter;

  Future<void> setReceiptFooter(String text) async {
    await ensureRow();
    await (db.update(db.settings)..where((t) => t.id.equals(1)))
        .write(SettingsCompanion(receiptFooter: Value(text)));
  }

  // ── Store logo path ──
  Future<String?> getStoreLogoPath() async =>
      (await db.select(db.settings).getSingleOrNull())?.storeLogoPath;

  Future<void> setStoreLogoPath(String path) async {
    await ensureRow();
    await (db.update(db.settings)..where((t) => t.id.equals(1)))
        .write(SettingsCompanion(storeLogoPath: Value(path)));
  }

  // ── WA Templates ──
  Future<List<Map<String, String>>> getWaTemplates() async {
    final row = await db.select(db.settings).getSingleOrNull();
    final json = row?.waTemplates;
    if (json == null || json.isEmpty) return _defaultTemplates();
    try {
      final list = (dart_convert.jsonDecode(json) as List)
          .cast<Map<String, dynamic>>();
      return list.map((m) => {
        'name': '${m['name'] ?? ''}',
        'body': '${m['body'] ?? ''}',
      }).toList();
    } catch (_) {
      return _defaultTemplates();
    }
  }

  List<Map<String, String>> _defaultTemplates() => [
    {'name': 'Pesanan Siap', 'body': 'Halo {nama}, pesanan Anda dengan invoice {invoice} sudah siap! Total: {total}. Terima kasih sudah berbelanja di {toko} 🥟'},
    {'name': 'Info Toko', 'body': 'Halo {nama}, terima kasih sudah berkunjung ke {toko}. Ada promo terbaru nih, jangan sampai kelewatan! 🎉'},
    {'name': 'Promo', 'body': 'Halo {nama}, dapatkan promo spesial di {toko}! Buruan check out sebelum kehabisan 🏃'},
  ];

  Future<void> saveWaTemplates(List<Map<String, String>> templates) async {
    await ensureRow();
    final json = dart_convert.jsonEncode(templates);
    await (db.update(db.settings)..where((t) => t.id.equals(1)))
        .write(SettingsCompanion(waTemplates: Value(json)));
  }

  // ── Point system config ──
  Future<Map<String, int>> getPointConfig() async {
    final row = await db.select(db.settings).getSingleOrNull();
    return {
      'pointsPerRupiah': row?.pointsPerRupiah ?? 100,
      'silverThreshold': row?.silverThreshold ?? 0,
      'goldThreshold': row?.goldThreshold ?? 1000,
      'platinumThreshold': row?.platinumThreshold ?? 5000,
    };
  }

  Future<void> savePointConfig({
    required int pointsPerRupiah,
    required int silverThreshold,
    required int goldThreshold,
    required int platinumThreshold,
  }) async {
    await ensureRow();
    await (db.update(db.settings)..where((t) => t.id.equals(1)))
        .write(SettingsCompanion(
      pointsPerRupiah: Value(pointsPerRupiah),
      silverThreshold: Value(silverThreshold),
      goldThreshold: Value(goldThreshold),
      platinumThreshold: Value(platinumThreshold),
    ));
  }
}
