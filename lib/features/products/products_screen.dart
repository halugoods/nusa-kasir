import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/skeleton_list.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';

/// Mapping category → emoji for image placeholder.
const _catEmoji = <String, String>{
  'Makanan': '🍜',
  'Minuman': '🥤',
  'Sembako': '📦',
  'Lainnya': '🧴',
};
const _catGradients = <String, List<Color>>{
  'Makanan': [Color(0xFFFEF3C7), Color(0xFFFDE68A), Color(0xFFFEF9C3)],
  'Minuman': [Color(0xFFDBEAFE), Color(0xFFBFDBFE), Color(0xFFEFF6FF)],
  'Sembako': [Color(0xFFFEE2E2), Color(0xFFFECACA), Color(0xFFFEF2F2)],
  'Lainnya': [Color(0xFFF3E8FF), Color(0xFFE9D5FF), Color(0xFFFAF5FF)],
};

/// Sort options.
enum _SortBy { nameAsc, nameDesc, priceHigh, priceLow }

const _sortLabels = <_SortBy, String>{
  _SortBy.nameAsc: 'Nama (A-Z)',
  _SortBy.nameDesc: 'Nama (Z-A)',
  _SortBy.priceHigh: 'Harga (Tertinggi)',
  _SortBy.priceLow: 'Harga (Terendah)',
};

/// View mode: product list or category accordion.
enum _ViewMode { products, categories }

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});
  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _search = TextEditingController();
  String _statusFilter = 'Semua'; // Semua | Aktif | Non Aktif
  _ViewMode _viewMode = _ViewMode.products;
  _SortBy _sortBy = _SortBy.nameAsc;
  List<Product> _products = [];
  Map<String, int> _catCounts = {};
  Set<String> _expandedCategories = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() => _load();

  Future<void> _load() async {
    final repo = ref.read(productRepoProvider);
    final q = _search.text.trim().toLowerCase();

    List<Product> all;
    if (q.isNotEmpty) {
      all = await repo.searchProducts(q);
    } else {
      all = await repo.getProducts(
        status: _statusFilter == 'Semua' ? null : _statusFilter,
      );
    }

    // Sort
    all = _sort(all);

    // Category counts (of the current filtered set)
    final counts = <String, int>{};
    for (final p in all) {
      final cat = p.category;
      counts[cat] = (counts[cat] ?? 0) + 1;
    }

    if (mounted) {
      setState(() {
        _products = all;
        _catCounts = counts;
        _loading = false;
      });
    }
  }

  List<Product> _sort(List<Product> list) {
    switch (_sortBy) {
      case _SortBy.nameAsc:
        list.sort((a, b) => a.name.compareTo(b.name));
      case _SortBy.nameDesc:
        list.sort((a, b) => b.name.compareTo(a.name));
      case _SortBy.priceHigh:
        list.sort((a, b) => b.sellPrice.compareTo(a.sellPrice));
      case _SortBy.priceLow:
        list.sort((a, b) => a.sellPrice.compareTo(b.sellPrice));
    }
    return list;
  }

  /// ── Export / Print ──

  void _showExportPopup() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Ekspor Daftar Produk',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined, color: NusaConfig.accentGreen),
                title: const Text('CSV (Excel)'),
                subtitle: const Text('File spreadsheet, bisa dibuka di Excel'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: NusaConfig.accentGreen.withValues(alpha: 0.06),
                onTap: () {
                  Navigator.pop(context);
                  _exportCSV();
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined, color: NusaConfig.primaryColor),
                title: const Text('PDF'),
                subtitle: const Text('Dokumen PDF siap cetak'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: NusaConfig.primaryColor.withValues(alpha: 0.06),
                onTap: () {
                  Navigator.pop(context);
                  _exportPDF();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportCSV() async {
    try {
      final rows = <List<String>>[
        ['Nama', 'SKU', 'Barcode', 'Kategori', 'Harga Beli', 'Harga Jual', 'Stok', 'Tipe', 'Kadaluarsa'],
      ];
      for (final p in _products) {
        rows.add([
          p.name,
          p.sku ?? '',
          p.barcode ?? '',
          p.category,
          p.buyPrice.toString(),
          p.sellPrice.toString(),
          p.stock.toString(),
          p.productType ?? 'Regular',
          p.expiryDate != null ? DateFormat('dd/MM/yyyy').format(p.expiryDate!) : '',
        ]);
      }
      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/produk_nusa_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path)], text: 'Daftar Produk NUSA Kasir');
    } catch (e) {
      if (mounted) TopToast.error(context, 'Gagal ekspor CSV');
    }
  }

  Future<void> _exportPDF() async {
    try {
      // Generate a text-based report and share it
      final buf = StringBuffer('DAFTAR PRODUK - NUSA KASIR\n');
      buf.writeln('=' * 60);
      buf.writeln('Nama | SKU | Kategori | Harga Jual | Stok | Tipe | Kadaluarsa');
      buf.writeln('-' * 60);
      for (final p in _products) {
        buf.writeln('${p.name} | ${p.sku ?? '-'} | ${p.category} | ${formatRupiah(p.sellPrice)} | ${p.stock} | ${p.productType ?? 'Regular'} | ${p.expiryDate != null ? DateFormat('dd/MM/yyyy').format(p.expiryDate!) : '-'}');
      }
      buf.writeln('=' * 60);
      buf.writeln('Total: ${_products.length} produk');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/produk_nusa_${DateTime.now().millisecondsSinceEpoch}.txt');
      await file.writeAsString(buf.toString());
      await Share.shareXFiles([XFile(file.path)], text: 'Daftar Produk NUSA Kasir');
    } catch (e) {
      if (mounted) TopToast.error(context, 'Gagal ekspor');
    }
  }

  /// ── Barcode scan ──

  Future<void> _scanBarcode() async {
    final controller = MobileScannerController();
    String? scanned;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Scan Barcode Produk'),
        content: SizedBox(
          width: 280,
          height: 280,
          child: MobileScanner(controller: controller, onDetect: (barcodeCapture) {
            final barcode = barcodeCapture.barcodes.firstOrNull;
            if (barcode != null && barcode.rawValue != null) {
              scanned = barcode.rawValue;
              Navigator.pop(context);
            }
          }),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ],
      ),
    );
    controller.dispose();
    if (scanned == null || !mounted) return;

    final repo = ref.read(productRepoProvider);
    final product = await repo.byBarcode(scanned!);
    if (product != null && mounted) {
      context.push('/produk/edit/${product.id}');
      return;
    }
    if (mounted) {
      _search.text = scanned!;
      TopToast.info(context, 'Produk tidak ditemukan. Coba cari manual.');
    }
  }

  /// ── Delete ──

  Future<void> _deleteProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hapus Produk'),
        content: Text('Hapus "${product.name}"?\nTindakan ini tidak dapat dibatalkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: NusaConfig.primaryColor),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(productRepoProvider).deleteProduct(product.id);
    if (mounted) {
      TopToast.success(context, 'Produk dihapus');
      _load();
    }
  }

  /// ── Build ──

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      'Daftar Produk',
      Column(
        children: [
          // Header actions row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Daftar Produk',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
                ),
                _HeaderIcon(icon: Icons.print_outlined, label: 'Ekspor', onTap: _showExportPopup),
                const SizedBox(width: 6),
                _HeaderIcon(icon: Icons.qr_code_scanner, label: 'Scan', onTap: _scanBarcode),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: NusaInput('Cari nama atau barcode...',
                controller: _search,
                type: TextInputType.text,
                hint: 'Cari nama atau barcode...',
                prefixIcon: const Icon(Icons.search, color: NusaConfig.textSecondary)),
          ),
          // Status filter chips
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                const labels = ['Semua', 'Aktif', 'Non Aktif'];
                final label = labels[i];
                final selected = label == _statusFilter;
                return FilterChip(
                  label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : NusaConfig.textPrimary)),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: NusaConfig.primaryColor,
                  backgroundColor: Theme.of(context).brightness == Brightness.dark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) {
                    if (label == _statusFilter) return;
                    setState(() => _statusFilter = label);
                    _load();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // Segmented control: Produk | Kategori
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? NusaConfig.darkSurface : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_viewMode != _ViewMode.products) setState(() => _viewMode = _ViewMode.products);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.all(3),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _viewMode == _ViewMode.products ? NusaConfig.primaryColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text('Produk',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _viewMode == _ViewMode.products ? Colors.white : NusaConfig.textSecondary)),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_viewMode != _ViewMode.categories) setState(() => _viewMode = _ViewMode.categories);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.all(3),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _viewMode == _ViewMode.categories ? NusaConfig.primaryColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text('Kategori',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _viewMode == _ViewMode.categories ? Colors.white : NusaConfig.textSecondary)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Sort dropdown
          if (_viewMode == _ViewMode.products || _viewMode == _ViewMode.categories)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.sort, size: 18, color: NusaConfig.textSecondary),
                  const SizedBox(width: 8),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<_SortBy>(
                      value: _sortBy,
                      isDense: true,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: NusaConfig.textPrimary),
                      items: _sortLabels.entries
                          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _sortBy = v);
                          _load();
                        }
                      },
                    ),
                  ),
                  const Spacer(),
                  if (_viewMode == _ViewMode.products && !_loading)
                    _SummaryBadge(count: _products.length),
                ],
              ),
            ),
          const SizedBox(height: 8),
          // Main content
          Expanded(
            child: _loading
                ? const SkeletonList()
                : _viewMode == _ViewMode.products
                    ? _buildProductList()
                    : _buildCategoryAccordion(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NusaConfig.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Produk'),
        onPressed: () => context.push('/produk/tambah'),
      ),
    );
  }

  Widget _buildProductList() {
    if (_products.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        message: _search.text.isNotEmpty ? 'Produk tidak ditemukan' : 'Belum ada produk',
        actionLabel: 'Tambah Produk',
        onAction: () => context.push('/produk/tambah'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        itemCount: _products.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _ProductCard(
          product: _products[i],
          onEdit: () => context.push('/produk/edit/${_products[i].id}'),
          onDelete: () => _deleteProduct(_products[i]),
        ),
      ),
    );
  }

  Widget _buildCategoryAccordion() {
    if (_catCounts.isEmpty) {
      return const Center(
        child: Text('Tidak ada produk', style: TextStyle(color: NusaConfig.textSecondary)),
      );
    }
    final cats = _catCounts.keys.toList()..sort();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        itemCount: cats.length,
        itemBuilder: (_, i) {
          final cat = cats[i];
          final count = _catCounts[cat] ?? 0;
          final expanded = _expandedCategories.contains(cat);
          final catProducts = _products.where((p) => p.category == cat).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (expanded) {
                      _expandedCategories.remove(cat);
                    } else {
                      _expandedCategories.add(cat);
                    }
                  });
                },
                child: NusaCard(
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Text(_catEmoji[cat] ?? '📦', style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cat,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
                              const SizedBox(height: 2),
                              Text('$count Produk',
                                  style: const TextStyle(fontSize: 12, color: NusaConfig.textSecondary)),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(Icons.keyboard_arrow_down, color: NusaConfig.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (expanded)
                ...catProducts.map((p) => Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: _ProductCard(
                        product: p,
                        onEdit: () => context.push('/produk/edit/${p.id}'),
                        onDelete: () => _deleteProduct(p),
                      ),
                    )),
              const SizedBox(height: 4),
            ],
          );
        },
      ),
    );
  }
}

/// Small summary badge showing product count.
class _SummaryBadge extends StatelessWidget {
  final int count;
  const _SummaryBadge({required this.count});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: NusaConfig.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$count produk',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NusaConfig.primaryColor)),
    );
  }
}

/// Header action icon button (ekspor/scan).
class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HeaderIcon({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? NusaConfig.darkBorder : NusaConfig.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: NusaConfig.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NusaConfig.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Product card widget — used in both "Produk" mode and "Kategori" accordion.
class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ProductCard({required this.product, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final low = product.stock <= product.minStock;
    final outOfStock = product.stock == 0;
    final hasImage = product.imagePath != null &&
        product.imagePath!.isNotEmpty &&
        File(product.imagePath!).existsSync();

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(20),
      child: NusaCard(
        Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 56,
                height: 56,
                child: hasImage
                    ? Image.file(File(product.imagePath!), fit: BoxFit.cover)
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _catGradients[product.category] ?? _catGradients['Lainnya']!,
                          ),
                        ),
                        child: Center(
                          child: Text(_catEmoji[product.category] ?? '📦', style: const TextStyle(fontSize: 24)),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Center info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
                  const SizedBox(height: 2),
                  Text(product.category,
                      style: const TextStyle(fontSize: 11, color: NusaConfig.textSecondary)),
                  const SizedBox(height: 3),
                  Text(formatRupiah(product.sellPrice),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: NusaConfig.primaryColor)),
                  // Tags row: productType + expiry
                  if (product.productType != null || product.expiryDate != null) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        if (product.productType != null)
                          _Tag(label: product.productType!, color: NusaConfig.accentPurple),
                        if (product.expiryDate != null)
                          _Tag(label: 'Exp: ${DateFormat('MM/yy').format(product.expiryDate!)}',
                              color: NusaConfig.accentGold),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right column: stock badge + actions
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: outOfStock
                        ? const Color(0xFFFEE2E2)
                        : low
                            ? const Color(0xFFFEF3C7)
                            : const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    outOfStock ? 'Habis' : low ? '⚠ Menipis' : 'Aktif',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: outOfStock ? const Color(0xFFDC2626) : low ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('Stok: ${product.stock}',
                    style: const TextStyle(fontSize: 12, color: NusaConfig.textSecondary)),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionButton(icon: Icons.edit_outlined, color: NusaConfig.textSecondary, onTap: onEdit),
                    const SizedBox(width: 4),
                    _ActionButton(icon: Icons.delete_outline, color: NusaConfig.primaryColor, onTap: onDelete),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small tag chip (productType / expiry).
class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// Small action icon button (edit / delete).
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
