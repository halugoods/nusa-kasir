import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/features/auth/rbac.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_icon.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _storeName = 'NUSA';

  final List<Map<String, String>> _items = const [
    {'id': 'produk', 'label': 'Produk', 'icon': 'product'},
    {'id': 'stok', 'label': 'Stok', 'icon': 'inventory'},
    {'id': 'transaksi', 'label': 'Transaksi', 'icon': 'transaction'},
    {'id': 'pelanggan', 'label': 'Pelanggan', 'icon': 'customer'},
    {'id': 'promo', 'label': 'Promo', 'icon': 'promotion'},
    {'id': 'laporan', 'label': 'Laporan', 'icon': 'finance'},
    {'id': 'presensi', 'label': 'Presensi', 'icon': 'notification'},
    {'id': 'keuangan', 'label': 'Keuangan', 'icon': 'finance'},
    {'id': 'pengaturan', 'label': 'Pengaturan', 'icon': 'settings'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = await ref.read(settingsRepoProvider).getStoreName();
    if (mounted) {
      setState(() => _storeName = name.isNotEmpty ? name : 'NUSA');
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider) ?? 'Owner';
    final visible =
        _items.where((i) => hasAccess(role, i['id']!)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_storeName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NusaCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Penjualan',
                      style:
                          TextStyle(fontSize: 14, color: NusaConfig.textSecondary)),
                  const SizedBox(height: 8),
                  Text('Rp 0',
                      style: Theme.of(context).textTheme.displaySmall),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: visible.length,
              itemBuilder: (_, i) {
                final item = visible[i];
                return InkWell(
                  onTap: () => context.go('/${item['id']}'),
                  borderRadius: BorderRadius.circular(20),
                  child: NusaCard(
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          NusaIcons.icon(item['icon']!, size: 28),
                          const SizedBox(height: 8),
                          Text(item['label']!,
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            NusaButton('Buka Kasir', onPressed: () => context.go('/kasir')),
          ],
        ),
      ),
    );
  }
}
