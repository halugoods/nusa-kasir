import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/core/utils/report_export.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/report_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import "package:nusa_kasir/shared/widgets/top_toast.dart";
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/skeleton_list.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _period = 'Hari Ini';
  int _refreshKey = 0;
  static const _periods = ['Hari Ini', '7 Hari', '30 Hari', 'Semua'];
  bool _exporting = false;

  (DateTime?, DateTime?) _range() {
    final now = DateTime.now();
    switch (_period) {
      case 'Hari Ini':
        return (DateTime(now.year, now.month, now.day), now);
      case '7 Hari':
        return (now.subtract(const Duration(days: 7)), now);
      case '30 Hari':
        return (now.subtract(const Duration(days: 30)), now);
      default:
        return (null, null);
    }
  }

  Future<void> _doExport(List<Transaction> items) async {
    final format = await _pickFormat();
    if (format == null) return;
    setState(() => _exporting = true);
    try {
      final name =
          'laporan_${_period.replaceAll(' ', '').toLowerCase()}_${DateTime.now().year}${DateTime.now().month}${DateTime.now().day}';
      final file = format == 'excel'
          ? await exportExcel(items, name)
          : await exportCsv(items, name);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Laporan NUSA Kasir',
        text: 'Laporan penjualan NUSA Kasir ($_period)',
      );
    } catch (e) {
      if (mounted) TopToast.error(context, 'Gagal ekspor: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<String?> _pickFormat() async {
    return showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Export Excel (.xlsx)'),
              onTap: () => Navigator.of(context).pop('excel'),
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Export CSV (.csv)'),
              onTap: () => Navigator.of(context).pop('csv'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _range();
    final repo = ReportRepository(ref.read(databaseProvider));
    return ScreenScaffold(
      'Laporan',
      Column(
        children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _periods.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _chip(_periods[i]),
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, dynamic>>(
            key: ValueKey('sum_$_refreshKey'),
            future: repo.summary(from: from, to: to),
            builder: (context, snap) {
              final omzet = snap.data?['omzet'] as int? ?? 0;
              final count = snap.data?['count'] as int? ?? 0;
              final avg = snap.data?['avg'] as int? ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: _StatCard('Omzet', formatRupiah(omzet))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _StatCard('Transaksi', count.toString())),
                    const SizedBox(width: 12),
                    Expanded(child: _StatCard('Rata-rata', formatRupiah(avg))),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _exporting
                    ? null
                    : () async {
                        final data = await repo.summary(from: from, to: to);
                        final items = data['items'] as List<Transaction>;
                        await _doExport(items);
                      },
                icon: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.share),
                label: Text(_exporting ? 'Memproses...' : 'Export Laporan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NusaConfig.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Transaction>>(
              key: ValueKey('list_$_refreshKey'),
              future: repo.getTransactions(from: from, to: to),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SkeletonList();
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Gagal memuat: ${snap.error}',
                        style: const TextStyle(color: Colors.grey)),
                  );
                }
                final list = snap.data ?? [];
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.bar_chart_outlined,
                    message: 'Belum ada transaksi',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => setState(() => _refreshKey++),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _TxCard(tx: list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    final isSel = label == _period;
    return FilterChip(
      label: Text(label),
      selected: isSel,
      showCheckmark: false,
      selectedColor: NusaConfig.primaryColor,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSel ? Colors.white : NusaConfig.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: NusaConfig.surfaceColor,
      onSelected: (_) {
        if (_period == label) return;
        setState(() { _period = label; _refreshKey++; });
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  const _StatCard(this.title, this.value);
  @override
  Widget build(BuildContext context) => NusaCard(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 12, color: NusaConfig.textSecondary)),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: NusaConfig.primaryColor)),
          ],
        ),
      );
}

class _TxCard extends StatelessWidget {
  final Transaction tx;
  const _TxCard({required this.tx});
  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${tx.date.day}/${tx.date.month}/${tx.date.year} ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}';
    return NusaCard(
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.invoice,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('$dateStr • ${tx.paymentMethod}',
                    style: const TextStyle(
                        fontSize: 13, color: NusaConfig.textSecondary)),
              ],
            ),
          ),
          Text(formatRupiah(tx.total),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: NusaConfig.primaryColor)),
        ],
      ),
    );
  }
}
