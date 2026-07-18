import 'package:drift/drift.dart';
import 'package:nusa_kasir/data/database/app_database.dart';

class CategoryRepository {
  final AppDatabase db;
  CategoryRepository(this.db);

  /// Get all category names, seeding defaults if empty.
  Future<List<String>> getAll() async {
    final rows = await db.select(db.categories).get();
    if (rows.isEmpty) {
      await _seedDefaults();
      final seeded = await db.select(db.categories).get();
      return seeded.map((r) => r.name).toList();
    }
    return rows.map((r) => r.name).toList();
  }

  /// Seed default categories (idempotent — skips if any exist).
  Future<void> _seedDefaults() async {
    final count = await db.select(db.categories).get();
    if (count.isNotEmpty) return;
    for (final name in _defaults) {
      await db.into(db.categories).insert(
        CategoriesCompanion.insert(name: name),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  /// Add a new category; returns the name on success.
  Future<String> add(String name) async {
    final trimmed = name.trim();
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(name: trimmed),
      mode: InsertMode.insertOrIgnore,
    );
    return trimmed;
  }

  /// Delete a category by name.
  Future<void> delete(String name) async {
    await (db.delete(db.categories)..where((t) => t.name.equals(name))).go();
  }

  /// Rename a category.
  Future<void> rename(String oldName, String newName) async {
    await (db.update(db.categories)..where((t) => t.name.equals(oldName)))
        .write(CategoriesCompanion(name: Value(newName.trim())));
  }

  static const _defaults = ['Makanan', 'Minuman', 'Sembako', 'Lainnya'];
}
