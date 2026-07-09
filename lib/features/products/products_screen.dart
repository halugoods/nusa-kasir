import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';

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
    if (mounted) setState(() => _products = filtered);
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
                controller: _search, type: TextInputType.text),
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? const Center(
                        child: Text('Belum ada produk',
                            style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _products.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _ProductTile(
                          product: _products[i],
                          onTap: () => context
                              .push('/produk/edit/${_products[i].id}'),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: NusaCard(
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(formatRupiah(product.sellPrice),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: NusaConfig.primaryColor)),
                  const SizedBox(height: 4),
                  Text('Stok: ${product.stock}',
                      style: const TextStyle(
                          fontSize: 13, color: NusaConfig.textSecondary)),
                  if (low)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Stok menipis!',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: NusaConfig.primaryDark)),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
