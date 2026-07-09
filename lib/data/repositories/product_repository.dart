import 'package:drift/drift.dart';
import 'package:nusa_kasir/core/activation/activation_key.dart';
import 'package:nusa_kasir/data/database/app_database.dart';

class ProductRepository {
  final AppDatabase db;
  ProductRepository(this.db);

  Future<int> addProduct({
    required String name,
    required String category,
    required int buyPrice,
    required int sellPrice,
    required int stock,
    required int minStock,
    String? sku,
    String? imagePath,
  }) async {
    final barcode = ActivationKey.generateSerial();
    return db.into(db.products).insert(ProductsCompanion.insert(
      name: name,
      sellPrice: sellPrice,
      category: Value(category),
      buyPrice: Value(buyPrice),
      stock: Value(stock),
      minStock: Value(minStock),
      sku: Value(sku),
      imagePath: Value(imagePath),
      barcode: Value<String?>(barcode),
    ));
  }

  Future<Product?> byId(int id) =>
    (db.select(db.products)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Product?> byBarcode(String barcode) =>
    (db.select(db.products)..where((t) => t.barcode.equals(barcode))).getSingleOrNull();

  Future<List<Product>> getProducts({String? category}) async {
    final q = db.select(db.products);
    if (category != null && category != 'Semua') {
      q.where((t) => t.category.equals(category));
    }
    return q.get();
  }

  Future<void> adjustStock(int id, int delta) async {
    final p = await byId(id);
    if (p == null) return;
    final next = (p.stock + delta).clamp(0, 1000000000);
    await (db.update(db.products)..where((t) => t.id.equals(id)))
        .write(ProductsCompanion(stock: Value(next)));
  }

  Future<void> updateProduct(int id,
    {String? name, String? category, int? buyPrice, int? sellPrice, int? minStock}) async {
    var companion = const ProductsCompanion();
    if (name != null) companion = companion.copyWith(name: Value(name));
    if (category != null) companion = companion.copyWith(category: Value(category));
    if (buyPrice != null) companion = companion.copyWith(buyPrice: Value(buyPrice));
    if (sellPrice != null) companion = companion.copyWith(sellPrice: Value(sellPrice));
    if (minStock != null) companion = companion.copyWith(minStock: Value(minStock));
    await (db.update(db.products)..where((t) => t.id.equals(id))).write(companion);
  }

  Future<void> deleteProduct(int id) async {
    await (db.delete(db.products)..where((t) => t.id.equals(id))).go();
  }
}
