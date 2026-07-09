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
}
