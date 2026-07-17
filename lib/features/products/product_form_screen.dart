import 'dart:convert';
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
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/nusa_form_field.dart';
import 'package:nusa_kasir/shared/widgets/nusa_toggle_card.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Variant data model (stored as JSON in variantsJson)
class _ProductVariant {
  String name;
  int priceAdjustment;
  int stock;
  _ProductVariant({this.name = '', this.priceAdjustment = 0, this.stock = 0});

  Map<String, dynamic> toJson() => {'name': name, 'priceAdjustment': priceAdjustment, 'stock': stock};
  factory _ProductVariant.fromJson(Map<String, dynamic> j) => _ProductVariant(
    name: j['name'] ?? '', priceAdjustment: j['priceAdjustment'] ?? 0, stock: j['stock'] ?? 0,
  );
}

/// Wholesale tier data model (stored as JSON in wholesaleJson)
class _WholesaleTier {
  int minQty;
  int price;
  _WholesaleTier({this.minQty = 1, this.price = 0});

  Map<String, dynamic> toJson() => {'minQty': minQty, 'price': price};
  factory _WholesaleTier.fromJson(Map<String, dynamic> j) => _WholesaleTier(
    minQty: j['minQty'] ?? 1, price: j['price'] ?? 0,
  );
}

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
  late String _barcode;
  Product? _existing;
  bool _loading = true;
  bool _barcodeOn = false;
  bool _isOnline = false;
  String? _imagePath;
  DateTime? _expiryDate;

  // Toggle-based product type
  bool _hasVarian = false;
  bool _hasGrosir = false;

  // Dynamic lists
  List<_ProductVariant> _variants = [];
  List<_WholesaleTier> _wholesaleTiers = [];

  bool get _isEdit => widget.productId != null;

  @override
  void initState() {
    super.initState();
    _barcode = ActivationKey.generateSerial();
    _init();
  }

  @override
  void dispose() {
    _name.dispose(); _sku.dispose(); _buy.dispose();
    _sell.dispose(); _stock.dispose(); _min.dispose();
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
      _category = NusaConfig.categories.contains(p.category) ? p.category : NusaConfig.categories.first;
      _imagePath = p.imagePath;
      _isOnline = p.isOnline;
      _expiryDate = p.expiryDate;

      // Load variants
      if (p.variantsJson != null && p.variantsJson!.isNotEmpty) {
        try {
          final list = jsonDecode(p.variantsJson!) as List;
          _variants = list.map((e) => _ProductVariant.fromJson(e as Map<String, dynamic>)).toList();
          _hasVarian = _variants.isNotEmpty;
        } catch (_) {}
      }
      // Load wholesale tiers
      if (p.wholesaleJson != null && p.wholesaleJson!.isNotEmpty) {
        try {
          final list = jsonDecode(p.wholesaleJson!) as List;
          _wholesaleTiers = list.map((e) => _WholesaleTier.fromJson(e as Map<String, dynamic>)).toList();
          _hasGrosir = _wholesaleTiers.isNotEmpty;
        } catch (_) {}
      }

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
      if (v && _existing?.barcode != null && _existing!.barcode!.isNotEmpty) {
        _barcode = _existing!.barcode!;
      } else if (v && _barcode.isEmpty) {
        _barcode = ActivationKey.generateSerial();
      }
    });
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image, allowMultiple: false);
    if (result == null || result.files.single.path == null) return;
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

  String? _serializeVariants() {
    if (!_hasVarian || _variants.isEmpty) return null;
    return jsonEncode(_variants.map((v) => v.toJson()).toList());
  }

  String? _serializeWholesale() {
    if (!_hasGrosir || _wholesaleTiers.isEmpty) return null;
    return jsonEncode(_wholesaleTiers.map((w) => w.toJson()).toList());
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final sell = _toInt(_sell.text);
    if (name.isEmpty) { TopToast.error(context, 'Nama produk wajib diisi'); return; }
    if (sell == null) { TopToast.error(context, 'Harga jual wajib diisi'); return; }
    final db = ref.read(databaseProvider);
    final buy = _toInt(_buy.text) ?? 0;
    final stock = _toInt(_stock.text) ?? 0;
    final min = _toInt(_min.text) ?? 0;
    final sku = _sku.text.trim().isEmpty ? null : _sku.text.trim();
    final variants = _serializeVariants();
    final wholesale = _serializeWholesale();
    final pType = _hasVarian ? 'Varian' : (_hasGrosir ? 'Grosir' : 'Regular');

    if (_isEdit) {
      await (db.update(db.products)..where((t) => t.id.equals(widget.productId!)))
          .write(ProductsCompanion(
            name: Value(name), category: Value(_category), buyPrice: Value(buy),
            sellPrice: Value(sell), minStock: Value(min), sku: Value(sku),
            stock: Value(stock), barcode: Value(_barcodeOn ? _barcode : null),
            imagePath: Value(_imagePath), isOnline: Value(_isOnline),
            expiryDate: Value(_expiryDate),
            productType: Value(pType == 'Regular' ? null : pType),
            variantsJson: Value(variants), wholesaleJson: Value(wholesale),
          ));
    } else {
      final id = await db.into(db.products).insert(ProductsCompanion.insert(
        name: name, sellPrice: sell, category: Value(_category),
        buyPrice: Value(buy), stock: Value(stock), minStock: Value(min),
        sku: Value(sku), imagePath: Value(_imagePath),
        barcode: Value(_barcodeOn ? _barcode : null),
        isOnline: Value(_isOnline), expiryDate: Value(_expiryDate),
        productType: Value(pType == 'Regular' ? null : pType),
        variantsJson: Value(variants), wholesaleJson: Value(wholesale),
      ));
    }
    if (mounted) context.pop();
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ScreenScaffold(
      _isEdit ? 'Edit Produk' : 'Tambah Produk',
      _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(NusaConfig.spaceMD),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // ── Product image ──
                _buildImagePicker(isDark),
                const SizedBox(height: NusaConfig.spaceMD),
                // ── Form fields using shared NusaFormField ──
                NusaFormField(label: 'Nama Produk', controller: _name),
                const SizedBox(height: NusaConfig.spaceSM),
                NusaFormField(label: 'SKU (opsional)', controller: _sku),
                const SizedBox(height: NusaConfig.spaceSM),
                NusaDropdownField<String>(
                  label: 'Kategori',
                  value: _category,
                  items: NusaConfig.categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => _category = v!),
                ),
                const SizedBox(height: NusaConfig.spaceSM),
                NusaFormField(label: 'Harga Beli', controller: _buy, keyboardType: TextInputType.number),
                const SizedBox(height: NusaConfig.spaceSM),
                NusaFormField(label: 'Harga Jual', controller: _sell, keyboardType: TextInputType.number),
                const SizedBox(height: NusaConfig.spaceSM),
                NusaFormField(label: 'Stok Awal', controller: _stock, keyboardType: TextInputType.number),
                const SizedBox(height: NusaConfig.spaceSM),
                NusaFormField(label: 'Stok Minimum', controller: _min, keyboardType: TextInputType.number),
                const SizedBox(height: NusaConfig.spaceMD),

                // ── Tipe Produk: Toggle Varian ──
                NusaToggleCard(
                  title: 'Varian (Rasa/Ukuran)',
                  value: _hasVarian,
                  icon: Icons.layers_outlined,
                  onChanged: (v) => setState(() { _hasVarian = v; if (!v) _variants.clear(); }),
                  expandedChild: _buildVariantList(isDark),
                ),
                const SizedBox(height: NusaConfig.spaceSM),

                // ── Tipe Produk: Toggle Grosir ──
                NusaToggleCard(
                  title: 'Harga Grosir',
                  value: _hasGrosir,
                  icon: Icons.inventory_2_outlined,
                  onChanged: (v) => setState(() { _hasGrosir = v; if (!v) _wholesaleTiers.clear(); }),
                  expandedChild: _buildWholesaleList(isDark),
                ),
                const SizedBox(height: NusaConfig.spaceMD),

                // ── Expiry Date ──
                GestureDetector(
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context, initialDate: _expiryDate ?? now,
                      firstDate: now, lastDate: DateTime(now.year + 10),
                      helpText: 'Pilih Tanggal Kadaluarsa',
                    );
                    if (picked != null) setState(() => _expiryDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Kadaluarsa (opsional)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5)),
                          const SizedBox(height: 6),
                          Text(
                            _expiryDate != null
                                ? '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}'
                                : 'Pilih tanggal',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                              color: _expiryDate != null ? NusaConfig.textPrimary : NusaConfig.textTertiary),
                          ),
                        ]),
                      ),
                      if (_expiryDate != null)
                        GestureDetector(
                          onTap: () => setState(() => _expiryDate = null),
                          child: const Icon(Icons.close, size: 18, color: NusaConfig.textTertiary),
                        ),
                      const SizedBox(width: 4),
                      const Icon(Icons.calendar_today, size: 18, color: NusaConfig.textSecondary),
                    ]),
                  ),
                ),
                const SizedBox(height: NusaConfig.spaceMD),

                // ── Barcode toggle ──
                NusaToggleCard(
                  title: 'Barcode',
                  value: _barcodeOn,
                  icon: Icons.qr_code_2,
                  onChanged: _toggleBarcode,
                  expandedChild: _barcodeOn
                      ? Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? NusaConfig.darkSurface2 : NusaConfig.dividerColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(children: [
                            BarcodeWidget(data: _barcode, barcode: Barcode.code128(), width: double.infinity, height: 70),
                            const SizedBox(height: 6),
                            Text(_barcode, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: NusaConfig.textSecondary)),
                          ]),
                        )
                      : null,
                ),
                const SizedBox(height: NusaConfig.spaceSM),

                // ── Toko Online toggle ──
                NusaToggleCard(
                  title: 'Tampil di Toko Online',
                  value: _isOnline,
                  icon: Icons.storefront_outlined,
                  onChanged: (v) => setState(() => _isOnline = v),
                  expandedChild: const Text('Produk akan muncul di website toko online Anda.',
                    style: TextStyle(fontSize: 11, color: NusaConfig.textTertiary)),
                ),
                const SizedBox(height: NusaConfig.spaceLG),

                // ── Save button ──
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
              ]),
            ),
    );
  }

  Widget _buildImagePicker(bool isDark) {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: isDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
          borderRadius: BorderRadius.circular(NusaConfig.radiusLG),
          border: Border.all(color: isDark ? NusaConfig.darkInputBorder : const Color(0xFFD1D5DB), width: 2),
        ),
        child: _imagePath != null
            ? Stack(fit: StackFit.expand, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(File(_imagePath!), fit: BoxFit.cover),
                ),
                Positioned(bottom: 12, left: 0, right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                        child: const Text('Ganti Foto', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
              ])
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.cloud_upload_outlined, size: 40, color: NusaConfig.textTertiary),
                const SizedBox(height: 10),
                const Text('TAP UNTUK UPLOAD FOTO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                const Text('atau drag & drop', style: TextStyle(fontSize: 11, color: NusaConfig.textTertiary)),
              ]),
      ),
    );
  }

  Widget _buildVariantList(bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ..._variants.asMap().entries.map((e) {
        final i = e.key;
        final v = e.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? NusaConfig.darkSurface2 : NusaConfig.backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
          ),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: v.name),
                  onChanged: (val) => _variants[i].name = val,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    labelText: 'Nama Varian', labelStyle: TextStyle(fontSize: 10, color: NusaConfig.textSecondary),
                    isDense: true, border: InputBorder.none),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _variants.removeAt(i)),
                child: const Icon(Icons.close, size: 18, color: NusaConfig.error),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: v.priceAdjustment == 0 ? '' : v.priceAdjustment.toString()),
                  keyboardType: TextInputType.number,
                  onChanged: (val) => _variants[i].priceAdjustment = int.tryParse(val) ?? 0,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(labelText: '± Harga', labelStyle: TextStyle(fontSize: 10, color: NusaConfig.textSecondary), isDense: true, border: InputBorder.none,
                    prefixText: '+/- '),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: v.stock == 0 ? '' : v.stock.toString()),
                  keyboardType: TextInputType.number,
                  onChanged: (val) => _variants[i].stock = int.tryParse(val) ?? 0,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Stok', labelStyle: TextStyle(fontSize: 10, color: NusaConfig.textSecondary), isDense: true, border: InputBorder.none),
                ),
              ),
            ]),
          ]),
        );
      }),
      TextButton.icon(
        onPressed: () => setState(() => _variants.add(_ProductVariant())),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Tambah Varian'),
        style: TextButton.styleFrom(foregroundColor: NusaConfig.primaryColor),
      ),
    ]);
  }

  Widget _buildWholesaleList(bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ..._wholesaleTiers.asMap().entries.map((e) {
        final i = e.key;
        final w = e.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? NusaConfig.darkSurface2 : NusaConfig.backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: TextEditingController(text: w.minQty == 1 ? '' : w.minQty.toString()),
                keyboardType: TextInputType.number,
                onChanged: (val) => _wholesaleTiers[i].minQty = int.tryParse(val) ?? 1,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(labelText: 'Min Qty', labelStyle: TextStyle(fontSize: 10, color: NusaConfig.textSecondary), isDense: true, border: InputBorder.none),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: TextEditingController(text: w.price == 0 ? '' : w.price.toString()),
                keyboardType: TextInputType.number,
                onChanged: (val) => _wholesaleTiers[i].price = int.tryParse(val) ?? 0,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(labelText: 'Harga Grosir', labelStyle: TextStyle(fontSize: 10, color: NusaConfig.textSecondary), isDense: true, border: InputBorder.none,
                  prefixText: 'Rp '),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _wholesaleTiers.removeAt(i)),
              child: const Icon(Icons.close, size: 18, color: NusaConfig.error),
            ),
          ]),
        );
      }),
      TextButton.icon(
        onPressed: () => setState(() => _wholesaleTiers.add(_WholesaleTier())),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Tambah Harga Grosir'),
        style: TextButton.styleFrom(foregroundColor: NusaConfig.primaryColor),
      ),
    ]);
  }
}
