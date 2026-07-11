import 'package:barcode_widget/barcode_widget.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/activation/activation_key.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import "package:nusa_kasir/shared/widgets/top_toast.dart";
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final int? productId;
  const ProductFormScreen({this.productId, super.key});
  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _buy = TextEditingController();
  final _sell = TextEditingController();
  final _stock = TextEditingController();
  final _min = TextEditingController();
  String _category = NusaConfig.categories.first;
  late final String _barcode;
  Product? _existing;
  bool _loading = true;
  bool get _isEdit => widget.productId != null;

  @override
  void initState() {
    super.initState();
    _barcode = ActivationKey.generateSerial();
    _init();
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _buy.dispose();
    _sell.dispose();
    _stock.dispose();
    _min.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (!_isEdit) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final repo = ProductRepository(ref.read(databaseProvider));
    final p = await repo.byId(widget.productId!);
    if (p != null && mounted) {
      _existing = p;
      _name.text = p.name;
      _sku.text = p.sku ?? '';
      _buy.text = p.buyPrice.toString();
      _sell.text = p.sellPrice.toString();
      _stock.text = p.stock.toString();
      _min.text = p.minStock.toString();
      _category = NusaConfig.categories.contains(p.category)
          ? p.category
          : NusaConfig.categories.first;
    }
    if (mounted) setState(() => _loading = false);
  }

  int? _toInt(String v) {
    if (v.trim().isEmpty) return null;
    return int.tryParse(v.trim());
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final sell = _toInt(_sell.text);
    if (name.isEmpty) {
      TopToast.error(context, 'Nama produk wajib diisi');
      return;
    }
    if (sell == null) {
      TopToast.error(context, 'Harga jual wajib diisi');
      return;
    }
    final repo = ProductRepository(ref.read(databaseProvider));
    final db = ref.read(databaseProvider);
    final buy = _toInt(_buy.text) ?? 0;
    final stock = _toInt(_stock.text) ?? 0;
    final min = _toInt(_min.text) ?? 0;
    final sku = _sku.text.trim().isEmpty ? null : _sku.text.trim();

    if (_isEdit) {
      await repo.updateProduct(widget.productId!,
          name: name,
          category: _category,
          buyPrice: buy,
          sellPrice: sell,
          minStock: min);
      // Update SKU & stock separately since updateProduct doesn't support them
      if (sku != null) {
        await (db.update(db.products)..where((t) => t.id.equals(widget.productId!)))
            .write(ProductsCompanion(sku: Value(sku)));
      }
      await (db.update(db.products)..where((t) => t.id.equals(widget.productId!)))
          .write(ProductsCompanion(stock: Value(stock)));
    } else {
      await repo.addProduct(
        name: name,
        category: _category,
        buyPrice: buy,
        sellPrice: sell,
        stock: stock,
        minStock: min,
        sku: sku,
      );
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final displayBarcode = _isEdit && _existing?.barcode != null
        ? _existing!.barcode!
        : _barcode;

    return ScreenScaffold(
      _isEdit ? 'Edit Produk' : 'Tambah Produk',
      _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NusaInput('Nama Produk', controller: _name),
                  const SizedBox(height: 12),
                  NusaInput('SKU (opsional)', controller: _sku),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _category,
                    decoration: const InputDecoration(
                      labelText: 'Kategori',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.all(Radius.circular(14))),
                    ),
                    items: NusaConfig.categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v!),
                  ),
                  const SizedBox(height: 12),
                  NusaInput('Harga Beli',
                      controller: _buy, type: TextInputType.number),
                  const SizedBox(height: 12),
                  NusaInput('Harga Jual',
                      controller: _sell, type: TextInputType.number),
                  const SizedBox(height: 12),
                  NusaInput('Stok Awal',
                      controller: _stock, type: TextInputType.number),
                  const SizedBox(height: 12),
                  NusaInput('Stok Minimum',
                      controller: _min, type: TextInputType.number),
                  const SizedBox(height: 16),
                  NusaCard(
                    Column(
                      children: [
                        const Text('Barcode',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: NusaConfig.textSecondary)),
                        const SizedBox(height: 8),
                        BarcodeWidget(
                          data: displayBarcode,
                          barcode: Barcode.code128(),
                          width: double.infinity,
                          height: 80,
                        ),
                        const SizedBox(height: 4),
                        Text(displayBarcode,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  NusaButton(_isEdit ? 'Simpan' : 'Simpan', onPressed: _save),
                ],
              ),
            ),
    );
  }
}
