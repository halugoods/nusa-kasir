import 'dart:io';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/activation/activation_key.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import "package:nusa_kasir/shared/widgets/top_toast.dart";
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  bool _barcodeOn = false; // toggle — default off
  bool _isOnline = false; // toko online toggle
  String? _imagePath; // local image path
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
      _imagePath = p.imagePath;
      _isOnline = p.isOnline;
      // If the product already has a barcode, turn toggle on
      if (p.barcode != null && p.barcode!.isNotEmpty) {
        _barcodeOn = true;
        _barcode = p.barcode!;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  int? _toInt(String v) {
    if (v.trim().isEmpty) return null;
    return int.tryParse(v.trim());
  }

  void _toggleBarcode(bool v) {
    setState(() {
      _barcodeOn = v;
      if (v && _existing == null) {
        _barcode = ActivationKey.generateSerial();
      }
    });
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;

    // Copy to app documents dir so it survives temp cleanup
    try {
      final src = File(result.files.single.path!);
      final dir = await getApplicationDocumentsDirectory();
      final ext = p.extension(src.path);
      final destName = 'product_${DateTime.now().millisecondsSinceEpoch}$ext';
      final dest = File(p.join(dir.path, destName));
      await src.copy(dest.path);
      setState(() => _imagePath = dest.path);
      TopToast.success(context, 'Gambar ditambahkan');
    } catch (_) {
      TopToast.error(context, 'Gagal menyimpan gambar');
    }
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
    final db = ref.read(databaseProvider);
    final buy = _toInt(_buy.text) ?? 0;
    final stock = _toInt(_stock.text) ?? 0;
    final min = _toInt(_min.text) ?? 0;
    final sku = _sku.text.trim().isEmpty ? null : _sku.text.trim();

    if (_isEdit) {
      // Single atomic update — all fields in one write, no partial state.
      await (db.update(db.products)..where((t) => t.id.equals(widget.productId!)))
          .write(ProductsCompanion(
            name: Value(name),
            category: Value(_category),
            buyPrice: Value(buy),
            sellPrice: Value(sell),
            minStock: Value(min),
            sku: Value(sku),
            stock: Value(stock),
            barcode: Value(_barcodeOn ? _barcode : null),
            imagePath: Value(_imagePath),
            isOnline: Value(_isOnline),
          ));
    } else {
      await _addProductWithAll(
        name: name,
        category: _category,
        buyPrice: buy,
        sellPrice: sell,
        stock: stock,
        minStock: min,
        sku: sku,
        imagePath: _imagePath,
        barcode: _barcodeOn ? _barcode : null,
        isOnline: _isOnline,
      );
    }
    if (mounted) context.pop();
  }

  /// Cleaner approach: single add with all fields
  Future<int> _addProductWithAll({
    required String name,
    required String category,
    required int buyPrice,
    required int sellPrice,
    required int stock,
    required int minStock,
    String? sku,
    String? imagePath,
    String? barcode,
    bool isOnline = false,
  }) async {
    final db = ref.read(databaseProvider);
    final id = await db.into(db.products).insert(ProductsCompanion.insert(
      name: name,
      sellPrice: sellPrice,
      category: Value(category),
      buyPrice: Value(buyPrice),
      stock: Value(stock),
      minStock: Value(minStock),
      sku: Value(sku),
      imagePath: Value(imagePath),
      barcode: Value(barcode),
      isOnline: Value(isOnline),
    ));
    return id;
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      _isEdit ? 'Edit Produk' : 'Tambah Produk',
      _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Product image ──
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      height: 140,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? NusaConfig.darkSurface2
                            : NusaConfig.backgroundColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? NusaConfig.darkBorder
                              : NusaConfig.borderColor,
                        ),
                      ),
                      child: _imagePath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.file(
                                File(_imagePath!),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 140,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    size: 40, color: NusaConfig.textTertiary),
                                const SizedBox(height: 8),
                                Text('Tambah Gambar Produk',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: NusaConfig.textTertiary)),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
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

                  // ── Barcode toggle ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? NusaConfig.darkSurface
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? NusaConfig.darkBorder
                            : const Color(0xFFF3F4F6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Barcode',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: NusaConfig.textSecondary)),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _barcodeOn ? 'ON' : 'OFF',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _barcodeOn
                                        ? NusaConfig.accentGreen
                                        : NusaConfig.textTertiary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Switch(
                                  key: const ValueKey('barcode_switch'),
                                  value: _barcodeOn,
                                  activeColor: NusaConfig.primaryColor,
                                  onChanged: _toggleBarcode,
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (_barcodeOn) ...[
                          const SizedBox(height: 8),
                          BarcodeWidget(
                            data: _barcode,
                            barcode: Barcode.code128(),
                            width: double.infinity,
                            height: 80,
                          ),
                          const SizedBox(height: 4),
                          Text(_barcode,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Toko Online toggle ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? NusaConfig.darkSurface
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? NusaConfig.darkBorder
                            : const Color(0xFFF3F4F6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Tampil di Toko Online',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: NusaConfig.textSecondary)),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _isOnline ? 'ON' : 'OFF',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _isOnline
                                        ? NusaConfig.accentGreen
                                        : NusaConfig.textTertiary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Switch(
                                  key: const ValueKey('online_switch'),
                                  value: _isOnline,
                                  activeColor: NusaConfig.primaryColor,
                                  onChanged: (v) => setState(() => _isOnline = v),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (_isOnline)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'Produk akan muncul di website toko online Anda.',
                              style: TextStyle(fontSize: 11, color: NusaConfig.textTertiary),
                            ),
                          ),
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
