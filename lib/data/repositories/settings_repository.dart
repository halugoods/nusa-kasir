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
}
