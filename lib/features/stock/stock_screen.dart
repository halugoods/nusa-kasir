import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/nusa_snackbar.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/skeleton_list.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});
  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  List<Product> _products = [];
  List<StockMovement> _movements = [];
  int? _inProductId;
  final _inQty = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inQty.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final repo = ProductRepository(db);
    final products = await repo.getProducts();
    final movements = await (db.select(db.stockMovements)
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)
          ]))
        .get();
    if (mounted) {
      setState(() {
        _products = products;
        _movements = movements;
        _loading = false;
      });
    }
  }

  List<Product> get _lowStock =>
      _products.where((p) => p.stock <= p.minStock).toList();

  Future<void> _addStock() async {
    if (_inProductId == null) {
      NusaSnackbar.error(context, 'Pilih produk terlebih dahulu');
      return;
    }
    final qty = int.tryParse(_inQty.text.trim());
    if (qty == null || qty <= 0) {
      NusaSnackbar.error(context, 'Jumlah stok harus lebih dari 0');
      return;
    }
    final db = ref.read(databaseProvider);
    final repo = ProductRepository(db);
    await repo.adjustStock(_inProductId!, qty);
    await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
          productId: _inProductId!,
          type: 'in',
          qty: qty,
        ));
    _inQty.clear();
    if (mounted) {
      NusaSnackbar.error(context, 'Stok berhasil ditambah');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      'Stok',
      _loading
          ? const SkeletonList()
          : DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  const TabBar(
                    labelColor: NusaConfig.primaryColor,
                    unselectedLabelColor: NusaConfig.textSecondary,
                    indicatorColor: NusaConfig.primaryColor,
                    tabs: [
                      Tab(text: 'Stok Menipis'),
                      Tab(text: 'Masuk'),
                      Tab(text: 'Riwayat'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _LowStockTab(products: _lowStock, onRefresh: _load, onTap: (p) {
                          context.push('/produk/edit/${p.id}');
                        }),
                        _InTab(
                          products: _products,
                          qtyController: _inQty,
                          selectedId: _inProductId,
                          onChanged: (id) => setState(() => _inProductId = id),
                          onSave: _addStock,
                        ),
                        _HistoryTab(movements: _movements, products: _products, onRefresh: _load),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _LowStockTab extends StatelessWidget {
  final List<Product> products;
  final void Function(Product) onTap;
  final Future<void> Function()? onRefresh;
  const _LowStockTab({required this.products, required this.onTap, this.onRefresh});

  @override
  Widget build(BuildContext context) => products.isEmpty
      ? const EmptyState(
          icon: Icons.inventory_outlined,
          message: 'Tidak ada stok menipis',
        )
      : RefreshIndicator(
          onRefresh: onRefresh ?? () async {},
          child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: products.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final p = products[i];
            return InkWell(
              onTap: () => onTap(p),
              borderRadius: BorderRadius.circular(20),
              child: NusaCard(
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('Stok: ${p.stock} / min ${p.minStock}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: NusaConfig.textSecondary)),
                        ],
                      ),
                    ),
                    Text('Menipis',
                        style: TextStyle(
                            color: NusaConfig.primaryDark,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          },
          ),
        );
}

class _InTab extends StatelessWidget {
  final List<Product> products;
  final TextEditingController qtyController;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  final VoidCallback onSave;
  const _InTab({
    required this.products,
    required this.qtyController,
    required this.selectedId,
    required this.onChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              value: selectedId,
              hint: const Text('Pilih produk'),
              decoration: const InputDecoration(
                labelText: 'Produk',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14))),
              ),
              items: products
                  .map((p) =>
                      DropdownMenuItem(value: p.id, child: Text(p.name)))
                  .toList(),
              onChanged: onChanged,
            ),
            const SizedBox(height: 12),
            NusaInput('Jumlah stok masuk',
                controller: qtyController, type: TextInputType.number),
            const SizedBox(height: 20),
            NusaButton('Tambah Stok', onPressed: onSave),
          ],
        ),
      );
}

class _HistoryTab extends StatelessWidget {
  final List<StockMovement> movements;
  final List<Product> products;
  final Future<void> Function()? onRefresh;
  const _HistoryTab({required this.movements, required this.products, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final nameOf = {
      for (final p in products) p.id: p.name,
    };
    return movements.isEmpty
        ? const EmptyState(
            icon: Icons.history,
            message: 'Belum ada riwayat',
          )
        : RefreshIndicator(
            onRefresh: onRefresh ?? () async {},
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
            itemCount: movements.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final m = movements[i];
              final name = nameOf[m.productId] ?? '#${m.productId}';
              final isIn = m.type == 'in';
              return NusaCard(
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                              '${isIn ? 'Masuk' : 'Keluar'} • ${m.date.day}/${m.date.month}/${m.date.year}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: NusaConfig.textSecondary)),
                        ],
                      ),
                    ),
                    Text('${isIn ? '+' : '-'}${m.qty}',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isIn
                                ? NusaConfig.primaryDark
                                : NusaConfig.textSecondary)),
                  ],
                ),
              );
            },
          ),
        );
  }
}
