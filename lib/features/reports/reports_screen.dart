import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:nusa_kasir/core/providers.dart';
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
  int _tab = 0; // 0 = Penjualan, 1 = Laba Rugi
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

  // ── PENJUALAN TAB ─────────────────────────────────────────────

  Widget _penjualanTab() {
    final (from, to) = _range();
    final repo = ReportRepository(ref.read(databaseProvider));
    return RefreshIndicator(
      onRefresh: () async => setState(() => _refreshKey++),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            const SizedBox(height: 12),
            // ── Bar Chart ──
            Container(
              height: 220,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF3F4F6))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Tren Pendapatan 7 Hari', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
                const SizedBox(height: 16),
                Expanded(
                  child: BarChart(
                    BarChartData(
                      barGroups: _chartBars(),
                      gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 50000),
                      titlesData: FlTitlesData(show: true, bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: _bottomTitle, reservedSize: 28)), leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 52, getTitlesWidget: (v, meta) => Text(formatRupiah(v.toInt()), style: const TextStyle(fontSize: 10, color: NusaConfig.textTertiary)))), topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
              ]),
            ),
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
            FutureBuilder<List<Transaction>>(
              key: ValueKey('list_$_refreshKey'),
              future: repo.getTransactions(from: from, to: to),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  );
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Gagal memuat: ${snap.error}',
                        style: const TextStyle(color: Colors.grey)),
                  );
                }
                final list = snap.data ?? [];
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: EmptyState(
                      icon: Icons.bar_chart_outlined,
                      message: 'Belum ada transaksi',
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _TxCard(tx: list[i]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<BarChartGroupData> _chartBars() {
    // Generate mock chart data for now — 7 days
    return List.generate(7, (i) => BarChartGroupData(x: i, barRods: [
      BarChartRodData(toY: (i + 1) * 15000 + (i * 5000).toDouble(), color: NusaConfig.primaryColor, width: 22, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
    ]));
  }
  Widget _bottomTitle(double v, TitleMeta meta) {
    final days = ['Sen','Sel','Rab','Kam','Jum','Sab','Min'];
    final idx = v.toInt();
    if (idx < 0 || idx >= 7) return const SizedBox.shrink();
    return Text(days[idx], style: const TextStyle(fontSize: 10, color: NusaConfig.textTertiary));
  }

  // ── LABA RUGI TAB ─────────────────────────────────────────────

  Widget _labaRugiTab() {
    final (from, to) = _range();
    final repo = ReportRepository(ref.read(databaseProvider));
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('pl_$_refreshKey'),
      future: repo.profitLoss(from: from, to: to),
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
        final d = snap.data ?? {};
        final pendapatan = d['pendapatan'] as int? ?? 0;
        final hpp = d['hpp'] as int? ?? 0;
        final labaKotor = d['labaKotor'] as int? ?? 0;
        final expenses = d['expenses'] as int? ?? 0;
        final payroll = d['payroll'] as int? ?? 0;
        final waste = d['waste'] as int? ?? 0;
        final liqIn = d['liquidityIn'] as int? ?? 0;
        final liqOut = d['liquidityOut'] as int? ?? 0;
        final totalBeban = d['totalBeban'] as int? ?? 0;
        final labaBersih = d['labaBersih'] as int? ?? 0;
        final txCount = d['txCount'] as int? ?? 0;

        return RefreshIndicator(
          onRefresh: () async => setState(() => _refreshKey++),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header card
              NusaCard(
                Column(
                  children: [
                    Text(
                      labaBersih >= 0 ? 'Laba Bersih' : 'Rugi Bersih',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: NusaConfig.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatRupiah(labaBersih.abs()),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: labaBersih >= 0
                            ? NusaConfig.accentGreenDark
                            : NusaConfig.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$txCount transaksi',
                      style: const TextStyle(
                          fontSize: 12, color: NusaConfig.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Pendapatan
              _plSection('Pendapatan', [
                _plRow('Pendapatan Penjualan', formatRupiah(pendapatan),
                    isHighlight: true),
                _plRow('HPP (Harga Pokok Penjualan)',
                    '${formatRupiah(hpp)}',
                    isDeduct: true),
                _plDivider(),
                _plRow('Laba Kotor', formatRupiah(labaKotor),
                    isBold: true,
                    color: labaKotor >= 0
                        ? NusaConfig.accentGreenDark
                        : NusaConfig.primaryColor),
              ]),
              const SizedBox(height: 12),

              // Beban
              _plSection('Beban', [
                _plRow('Pengeluaran Operasional', formatRupiah(expenses),
                    isDeduct: true),
                _plRow('Payroll / Gaji', formatRupiah(payroll), isDeduct: true),
                _plRow('Waste / Barang Rusak', formatRupiah(waste),
                    isDeduct: true),
                _plRow('Likuiditas Keluar', formatRupiah(liqOut),
                    isDeduct: true),
                _plRow('Likuiditas Masuk', formatRupiah(liqIn),
                    isAdd: true),
                _plDivider(),
                _plRow('Total Beban', formatRupiah(totalBeban),
                    isBold: true, isDeduct: true),
              ]),
              const SizedBox(height: 12),

              // Result
              NusaCard(
                Column(
                  children: [
                    _plRow('Laba / Rugi Bersih', formatRupiah(labaBersih.abs()),
                        isBold: true,
                        isHighlight: true,
                        color: labaBersih >= 0
                            ? NusaConfig.accentGreenDark
                            : NusaConfig.primaryColor),
                    const SizedBox(height: 4),
                    Text(
                      labaBersih >= 0 ? 'Untung' : 'Rugi',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: labaBersih >= 0
                              ? NusaConfig.accentGreenDark
                              : NusaConfig.primaryColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Text(
                '* Perhitungan berdasarkan data yang tersedia. HPP dihitung dari harga beli produk.',
                style: const TextStyle(
                    fontSize: 11,
                    color: NusaConfig.textTertiary,
                    fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _plSection(String title, List<Widget> rows) {
    return NusaCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }

  Widget _plRow(String label, String value,
      {bool isBold = false,
      bool isDeduct = false,
      bool isAdd = false,
      bool isHighlight = false,
      Color? color}) {
    final prefix = isDeduct ? '− ' : (isAdd ? '+ ' : '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w500,
                  color: isHighlight
                      ? NusaConfig.textPrimary
                      : NusaConfig.textSecondary)),
          Text(
            '$prefix$value',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold || isHighlight ? FontWeight.w700 : FontWeight.w600,
              color: color ??
                  (isDeduct
                      ? Colors.red.shade400
                      : isAdd
                          ? Colors.green
                          : NusaConfig.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _plDivider() =>
      const Divider(height: 16, thickness: 1);

  // ── MAIN BUILD ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      'Laporan',
      Column(
        children: [
          const SizedBox(height: 8),
          // Period chips
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
          const SizedBox(height: 8),
          // Tab: Penjualan | Laba Rugi
          SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 16),
                _tabChip('Penjualan', 0),
                const SizedBox(width: 8),
                _tabChip('Laba Rugi', 1),
              ],
            ),
          ),
          Expanded(child: _tab == 0 ? _penjualanTab() : _labaRugiTab()),
        ],
      ),
    );
  }

  Widget _tabChip(String label, int idx) {
    final sel = idx == _tab;
    return FilterChip(
      label: Text(label),
      selected: sel,
      showCheckmark: false,
      selectedColor: NusaConfig.primaryColor,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: sel ? Colors.white : NusaConfig.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: NusaConfig.surfaceColor,
      onSelected: (_) => setState(() => _tab = idx),
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
    final isVoided = tx.status == 'Void';
    return NusaCard(
      Opacity(
        opacity: isVoided ? 0.55 : 1.0,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(tx.invoice,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      if (isVoided) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: NusaConfig.primaryColor
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('VOID',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: NusaConfig.primaryColor)),
                        ),
                      ],
                    ],
                  ),
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
      ),
    );
  }
}
