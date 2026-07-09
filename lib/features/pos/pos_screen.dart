import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/features/pos/cart.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/nusa_snackbar.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});
  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _search = TextEditingController();
  String _category = 'Semua';

  List<String> get _chips => ['Semua', ...NusaConfig.categories];

  Future<List<Product>> _loadProducts() async {
    final repo = ProductRepository(ref.read(databaseProvider));
    final all = await repo.getProducts(
      category: _category == 'Semua' ? null : _category,
    );
    final q = _search.text.toLowerCase();
    if (q.isEmpty) return all;
    return all.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _scanBarcode(BuildContext context) async {
    final ctx = context;
    String? scannedCode;
    final controller = MobileScannerController();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pindai Barcode'),
        contentPadding: const EdgeInsets.all(8),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              controller: controller,
              onDetect: (capture) {
                if (scannedCode != null) return;
                final code = capture.barcodes.firstWhere(
                  (b) => b.rawValue != null,
                  orElse: () => capture.barcodes.first,
                ).rawValue;
                if (code == null || code.isEmpty) return;
                scannedCode = code;
                Navigator.of(dialogContext).pop(code);
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
    await controller.dispose();
    if (scannedCode == null || !ctx.mounted) return;

    final db = ref.read(databaseProvider);
    final product = await ProductRepository(db).byBarcode(scannedCode!);
    if (product != null) {
      ref.read(cartProvider.notifier).addProduct(
            product.id,
            product.name,
            product.sellPrice,
          );
    } else if (ctx.mounted) {
      NusaSnackbar.error(ctx, 'Produk tidak ditemukan');
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return ScreenScaffold(
      'Kasir',
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
                  onSelected: (_) => setState(() => _category = chip),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Product>>(
              key: ValueKey('$_category|${_search.text}'),
              future: _loadProducts(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final products = snap.data ?? [];
                if (products.isEmpty) {
                  return const Center(
                    child: Text('Tidak ada produk',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return GridView.count(
                  crossAxisCount: 3,
                  padding: const EdgeInsets.all(16),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1,
                  children: products
                      .map((p) => _ProductTile(
                            product: p,
                            onTap: () => ref
                                .read(cartProvider.notifier)
                                .addProduct(p.id, p.name, p.sellPrice),
                          ))
                      .toList(),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: NusaConfig.surfaceColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🛒 ${cart.fold(0, (s, e) => s + e.qty)} item',
                          style: const TextStyle(
                              fontSize: 14, color: NusaConfig.textSecondary)),
                      const SizedBox(height: 2),
                      Text(
                        formatRupiah(
                            cart.fold(0, (s, e) => s + e.subtotal)),
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: NusaConfig.primaryColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: NusaButton(
                    'Bayar',
                    onPressed: cart.isEmpty
                        ? null
                        : () => context.go('/checkout'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: NusaConfig.primaryColor,
        foregroundColor: Colors.white,
        tooltip: 'Pindai',
        onPressed: () => _scanBarcode(context),
        child: const Icon(Icons.qr_code_2_outlined),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: NusaCard(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const Spacer(),
            Text(formatRupiah(product.sellPrice),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: NusaConfig.primaryColor)),
            const SizedBox(height: 4),
            Text('Stok: ${product.stock}',
                style: const TextStyle(
                    fontSize: 12, color: NusaConfig.textSecondary)),
          ],
        ),
      ),
    );
  }
}
