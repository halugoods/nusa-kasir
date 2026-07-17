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
import 'package:nusa_kasir/shared/widgets/nusa_status_badge.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/skeleton_list.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';

/// Sort options.
enum _SortBy { nameAsc, nameDesc, priceHigh, priceLow }

const _sortLabels = <_SortBy, String>{
  _SortBy.nameAsc: 'Nama (A-Z)',
  _SortBy.nameDesc: 'Nama (Z-A)',
  _SortBy.priceHigh: 'Harga (Tertinggi)',
  _SortBy.priceLow: 'Harga (Terendah)',
};

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});
  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _search = TextEditingController();
  String _statusFilter = 'Semua';
  _SortBy _sortBy = _SortBy.nameAsc;
  List<Product> _products = [];
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
    all = _sort(all);

    if (mounted) {
      setState(() { _products = all; _loading = false; });
    }
  }

  List<Product> _sort(List<Product> list) {
    switch (_sortBy) {
      case _SortBy.nameAsc: list.sort((a, b) => a.name.compareTo(b.name));
      case _SortBy.nameDesc: list.sort((a, b) => b.name.compareTo(a.name));
      case _SortBy.priceHigh: list.sort((a, b) => b.sellPrice.compareTo(a.sellPrice));
      case _SortBy.priceLow: list.sort((a, b) => a.sellPrice.compareTo(b.sellPrice));
    }
    return list;
  }

  // ── Export ──

  void _showExportPopup() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(NusaConfig.spaceLG),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Ekspor Daftar Produk', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: NusaConfig.spaceMD),
            _exportTile(Icons.table_chart_outlined, NusaConfig.accentGreen, 'CSV (Excel)', 'File spreadsheet, bisa dibuka di Excel', _exportCSV),
            const SizedBox(height: NusaConfig.spaceXS),
            _exportTile(Icons.picture_as_pdf_outlined, NusaConfig.primaryColor, 'PDF', 'Dokumen PDF siap cetak', _exportPDF),
          ]),
        ),
      ),
    );
  }

  Widget _exportTile(IconData icon, Color color, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(subtitle),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NusaConfig.radiusMD)),
      tileColor: color.withValues(alpha: 0.06),
      onTap: () { Navigator.pop(context); onTap(); },
    );
  }

  Future<void> _exportCSV() async {
    try {
      final rows = <List<String>>[
        ['Nama', 'SKU', 'Barcode', 'Kategori', 'Harga Beli', 'Harga Jual', 'Stok', 'Tipe', 'Kadaluarsa'],
      ];
      for (final p in _products) {
        rows.add([
          p.name, p.sku ?? '', p.barcode ?? '', p.category,
          p.buyPrice.toString(), p.sellPrice.toString(), p.stock.toString(),
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

  // ── Barcode scan ──

  Future<void> _scanBarcode() async {
    final controller = MobileScannerController();
    String? scanned;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Scan Barcode Produk'),
        content: SizedBox(width: 280, height: 280,
          child: MobileScanner(controller: controller, onDetect: (capture) {
            final barcode = capture.barcodes.firstOrNull;
            if (barcode != null && barcode.rawValue != null) {
              scanned = barcode.rawValue;
              Navigator.pop(context);
            }
          }),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal'))],
      ),
    );
    controller.dispose();
    if (scanned == null || !mounted) return;

    final repo = ref.read(productRepoProvider);
    final product = await repo.byBarcode(scanned!);
    if (product != null && mounted) { context.push('/produk/edit/${product.id}'); return; }
    if (mounted) { _search.text = scanned!; TopToast.info(context, 'Produk tidak ditemukan. Coba cari manual.'); }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NusaConfig.radiusXL)),
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
    if (mounted) { TopToast.success(context, 'Produk dihapus'); _load(); }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScreenScaffold(
      'Daftar Produk',
      Column(children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            const Expanded(child: Text('Daftar Produk',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary))),
            _HeaderIcon(icon: Icons.print_outlined, label: 'Ekspor', onTap: _showExportPopup),
            const SizedBox(width: 6),
            _HeaderIcon(icon: Icons.qr_code_scanner, label: 'Scan', onTap: _scanBarcode),
          ]),
        ),
        const SizedBox(height: 10),
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: NusaInput('Cari nama atau barcode...',
            controller: _search, hint: 'Cari nama atau barcode...',
            prefixIcon: const Icon(Icons.search, color: NusaConfig.textSecondary)),
        ),
        // Status chips + kategori button row
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 4, // 3 status + "Kategori"
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              const labels = ['Semua', 'Aktif', 'Non Aktif'];
              if (i < 3) {
                final label = labels[i];
                final selected = label == _statusFilter;
                return FilterChip(
                  label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : NusaConfig.textPrimary)),
                  selected: selected, showCheckmark: false,
                  selectedColor: NusaConfig.primaryColor,
                  backgroundColor: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) { if (label != _statusFilter) { setState(() => _statusFilter = label); _load(); } },
                );
              }
              // Kategori button
              return ActionChip(
                label: const Text('Kategori', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NusaConfig.primaryColor)),
                avatar: const Icon(Icons.category, size: 16, color: NusaConfig.primaryColor),
                backgroundColor: NusaConfig.primarySoft,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () => context.push('/produk/kategori'),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Sort + count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const Icon(Icons.sort, size: 18, color: NusaConfig.textSecondary),
            const SizedBox(width: 8),
            DropdownButtonHideUnderline(
              child: DropdownButton<_SortBy>(
                value: _sortBy, isDense: true,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: NusaConfig.textPrimary),
                items: _sortLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) { if (v != null) { setState(() => _sortBy = v); _load(); } },
              ),
            ),
            const Spacer(),
            if (!_loading)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: NusaConfig.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(NusaConfig.radiusFull)),
                child: Text('${_products.length} produk',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NusaConfig.primaryColor)),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        // Product list
        Expanded(
          child: _loading
              ? const SkeletonList()
              : _products.isEmpty
                  ? EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: _search.text.isNotEmpty ? 'Produk tidak ditemukan' : 'Belum ada produk',
                      actionLabel: 'Tambah Produk',
                      onAction: () => context.push('/produk/tambah'))
                  : RefreshIndicator(
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
                    ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NusaConfig.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Produk'),
        onPressed: () => context.push('/produk/tambah'),
      ),
    );
  }
}

// ── Header icon ──

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HeaderIcon({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: NusaConfig.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NusaConfig.textSecondary)),
        ]),
      ),
    );
  }
}

// ── Product Card ──

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ProductCard({required this.product, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final hasImage = product.imagePath != null && product.imagePath!.isNotEmpty && File(product.imagePath!).existsSync();

    return NusaCard(
      onTap: onEdit,
      Row(children: [
        // Thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(NusaConfig.radiusMD),
          child: SizedBox(width: 60, height: 60,
            child: hasImage
                ? Image.file(File(product.imagePath!), fit: BoxFit.cover)
                : Container(
                    decoration: BoxDecoration(gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: NusaConfig.catGradientFor(product.category))),
                    child: Center(child: Text(NusaConfig.catEmojiFor(product.category), style: const TextStyle(fontSize: 26))),
                  ),
          ),
        ),
        const SizedBox(width: NusaConfig.spaceSM),
        // Info
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
            const SizedBox(height: 2),
            Text(product.category, style: const TextStyle(fontSize: 11, color: NusaConfig.textSecondary)),
            const SizedBox(height: 3),
            Text(formatRupiah(product.sellPrice), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: NusaConfig.primaryColor)),
            // Tags row
            if (product.productType != null || product.expiryDate != null) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 4, children: [
                if (product.productType != null)
                  _Tag(label: product.productType!, color: NusaConfig.accentPurple),
                if (product.expiryDate != null)
                  _Tag(label: 'Exp: ${DateFormat('MM/yy').format(product.expiryDate!)}', color: NusaConfig.accentGold),
              ]),
            ],
          ]),
        ),
        const SizedBox(width: NusaConfig.spaceXS),
        // Right side: stock badge + actions
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          NusaStatusBadge(stock: product.stock, minStock: product.minStock),
          const SizedBox(height: 4),
          Text('Stok: ${product.stock}', style: const TextStyle(fontSize: 12, color: NusaConfig.textSecondary)),
          const SizedBox(height: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _ActionButton(icon: Icons.edit_outlined, color: NusaConfig.textSecondary, onTap: onEdit),
            const SizedBox(width: 4),
            _ActionButton(icon: Icons.delete_outline, color: NusaConfig.error, onTap: onDelete),
          ]),
        ]),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

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
        width: 32, height: 32,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
