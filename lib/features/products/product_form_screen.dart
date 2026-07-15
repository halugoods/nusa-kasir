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
                      height: 160,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFD1D5DB), width: 2),
                      ),
                      child: _imagePath != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.file(
                                    File(_imagePath!),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  bottom: 12,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: GestureDetector(
                                      onTap: _pickImage,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Text(
                                          'Ganti Foto',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.cloud_upload_outlined,
                                    size: 40, color: Color(0xFF9CA3AF)),
                                const SizedBox(height: 10),
                                const Text('TAP UNTUK UPLOAD FOTO',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF6B7280),
                                        letterSpacing: 0.5)),
                                const SizedBox(height: 4),
                                const Text('atau drag & drop',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF9CA3AF))),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'Nama Produk',
                      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _sku,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'SKU (opsional)',
                      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _category,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: NusaConfig.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Kategori',
                      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    items: NusaConfig.categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _buy,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'Harga Beli',
                      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _sell,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'Harga Jual',
                      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _stock,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'Stok Awal',
                      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _min,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'Stok Minimum',
                      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
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
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                BarcodeWidget(
                                  data: _barcode,
                                  barcode: Barcode.code128(),
                                  width: double.infinity,
                                  height: 70,
                                ),
                                const SizedBox(height: 6),
                                Text(_barcode,
                                    style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: NusaConfig.textSecondary)),
                              ],
                            ),
                          ),
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
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NusaConfig.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      child: Text(_isEdit ? 'Simpan Perubahan' : 'Simpan Produk ke Database'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
