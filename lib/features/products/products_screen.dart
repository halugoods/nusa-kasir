import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/skeleton_list.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';

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

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});
  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _search = TextEditingController();
  String _category = 'Semua';
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
    final repo = ProductRepository(ref.read(databaseProvider));
    final all = await repo.getProducts(
      category: _category == 'Semua' ? null : _category,
    );
    final q = _search.text.toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all.where((p) => p.name.toLowerCase().contains(q)).toList();
    if (mounted) setState(() { _products = filtered; _loading = false; });
  }

  List<String> get _chips => ['Semua', ...NusaConfig.categories];

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      'Produk',
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: NusaInput('Cari produk...',
                controller: _search, type: TextInputType.text,
                prefixIcon: const Icon(Icons.search, color: NusaConfig.textSecondary)),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _chips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final chip = _chips[i];
                final selected = chip == _category;
                return FilterChip(
                  label: Text(chip),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: NusaConfig.primaryColor,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : NusaConfig.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: NusaConfig.surfaceColor,
                  onSelected: (_) {
                    if (chip == _category) return;
                    setState(() => _category = chip);
                    _load();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // Summary chip
          if (!_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: NusaConfig.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Total: ${_products.length} produk',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: NusaConfig.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const SkeletonList()
                : _products.isEmpty
                    ? EmptyState(
                        icon: Icons.inventory_2_outlined,
                        message: 'Belum ada produk',
                        actionLabel: 'Tambah Produk',
                        onAction: () => context.push('/produk/tambah'),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _products.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            return _ProductTile(
                              product: _products[i],
                              onTap: () =>
                                  context.push('/produk/edit/${_products[i].id}'),
                            );
                          },
                        ),
                      ),
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
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const _ProductTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final low = product.stock <= product.minStock;
    final outOfStock = product.stock == 0;
    final hasImage = product.imagePath != null && product.imagePath!.isNotEmpty && File(product.imagePath!).existsSync();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: NusaCard(
        Row(
          children: [
            // ── Product thumbnail ──
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
            // ── Center: name, category, price ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
                  const SizedBox(height: 2),
                  Text(product.category,
                      style: const TextStyle(
                          fontSize: 12, color: NusaConfig.textSecondary)),
                  const SizedBox(height: 4),
                  Text(formatRupiah(product.sellPrice),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: NusaConfig.primaryColor)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ── Right column: stock badge + chevron ──
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Stock badge
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
                    outOfStock
                        ? 'Habis'
                        : low
                            ? '⚠ Menipis'
                            : 'Aktif',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: outOfStock
                          ? const Color(0xFFDC2626)
                          : low
                              ? const Color(0xFFD97706)
                              : const Color(0xFF16A34A),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('Stok: ${product.stock}',
                    style: const TextStyle(
                        fontSize: 12, color: NusaConfig.textSecondary)),
                const SizedBox(height: 4),
                const Icon(Icons.chevron_right, color: NusaConfig.textTertiary, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
