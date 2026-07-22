import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/core/utils/report_export.dart';
import 'package:nusa_kasir/core/utils/report_pdf.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/report_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
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
  int _tab = 0; // 0 = Penjualan, 1 = Laba Rugi
  int _refreshKey = 0;
  bool _exporting = false;

  // Period state
  String _period = 'Hari Ini';
  DateTime? _customFrom;
  DateTime? _customTo;
  static const _periodOptions = ['Hari Ini', '7 Hr', '30 Hr', 'Bln Ini', 'Custom', 'Semua'];
  static const _periodLabels = {
    'Hari Ini': 'Hari Ini', '7 Hr': '7 Hari', '30 Hr': '30 Hari',
    'Bln Ini': 'Bulan Ini', 'Custom': 'Custom', 'Semua': 'Semua',
  };

  (DateTime?, DateTime?) _range() {
    final actual = _periodLabels[_period] ?? _period;
    if (actual == 'Custom') return (_customFrom, _customTo);
    final now = DateTime.now();
    switch (actual) {
      case 'Hari Ini':
        return (DateTime(now.year, now.month, now.day), now);
      case '7 Hari':
        return (now.subtract(const Duration(days: 7)), now);
      case '30 Hari':
        return (now.subtract(const Duration(days: 30)), now);
      case 'Bulan Ini':
        return (DateTime(now.year, now.month, 1), now);
      default:
        return (null, null);
    }
  }

  String _periodLabel() {
    final actual = _periodLabels[_period] ?? _period;
    if (actual == 'Custom' && _customFrom != null && _customTo != null) {
      return '${_customFrom!.day}/${_customFrom!.month} – ${_customTo!.day}/${_customTo!.month}/${_customTo!.year}';
    }
    return actual;
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customFrom != null && _customTo != null
          ? DateTimeRange(start: _customFrom!, end: _customTo!)
          : null,
      helpText: 'Pilih Rentang Tanggal',
      cancelText: 'BATAL',
      confirmText: 'PILIH',
    );
    if (range != null) {
      setState(() {
        _customFrom = range.start;
        _customTo = range.end;
        _period = 'Custom';
        _refreshKey++;
      });
    }
  }

  // ── Export ─────────────────────────────────────────────────────────

  Future<String?> _pickFormat() async {
    return showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: const Text('Export PDF (.pdf)'),
            onTap: () => Navigator.of(context).pop('pdf'),
          ),
        ]),
      ),
    );
  }

  Future<void> _doExport(List<Transaction> items, Map<String, dynamic> sum,
      List<Map<String, dynamic>> top, List<Map<String, dynamic>> cats,
      Map<String, int> pays) async {
    final format = await _pickFormat();
    if (format == null) return;
    setState(() => _exporting = true);
    try {
      final stamp =
          '${DateTime.now().year}${DateTime.now().month}${DateTime.now().day}_${DateTime.now().hour}${DateTime.now().minute}';
      final name = 'laporan_${_periodLabel().replaceAll(' ', '').toLowerCase()}_$stamp';
      if (format == 'pdf') {
        final file = await exportReportPdf(
            period: _periodLabel(),
            summary: sum,
            topProducts: top,
            categories: cats,
            payments: pays);
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      } else {
        final file = format == 'excel'
            ? await exportExcel(items, name)
            : await exportCsv(items, name);
        await Share.shareXFiles([XFile(file.path)],
            subject: 'Laporan NUSA Kasir',
            text: 'Laporan penjualan NUSA Kasir (${_periodLabel()})');
      }
    } catch (e) {
      if (mounted) TopToast.error(context, 'Gagal ekspor: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── PENJUALAN TAB ──────────────────────────────────────────────────

  Widget _penjualanTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (from, to) = _range();
    final repo = ReportRepository(ref.read(databaseProvider));
    final labelClr =
        isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary;
    final textSec =
        isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary;
    final textTer =
        isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary;
    final surf = isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor;
    final border = isDark ? NusaConfig.darkBorder : NusaConfig.borderColor;

    return RefreshIndicator(
      onRefresh: () async => setState(() => _refreshKey++),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(children: [
          const SizedBox(height: 8),
          // ── Comparison cards ──
          FutureBuilder<Map<String, dynamic>>(
            key: ValueKey('comp_$_refreshKey'),
            future: repo.summaryWithPrevious(from, to),
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                    padding: EdgeInsets.all(20),
                    child: SkeletonList());
              }
              final d = snap.data ?? {};
              final omzet = d['omzet'] as int? ?? 0;
              final count = d['count'] as int? ?? 0;
              final avg = d['avg'] as int? ?? 0;
              final hasPrev = d['hasPrevious'] as bool? ?? false;
              final omzetG = d['omzetGrowth'] as double? ?? 0;
              final countG = d['countGrowth'] as double? ?? 0;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: _StatCard('Omzet', formatRupiah(omzet),
                        isDark: isDark)),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard('Transaksi', count.toString(),
                        isDark: isDark)),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard('Rata-rata', formatRupiah(avg),
                        isDark: isDark)),
                  ]),
                  if (hasPrev) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      _GrowthBadge('Omzet', omzetG, isDark: isDark),
                      const SizedBox(width: 10),
                      _GrowthBadge('Transaksi', countG, isDark: isDark),
                    ]),
                  ],
                ]),
              );
            },
          ),
          const SizedBox(height: 12),
          // ── Bar Chart ──
          FutureBuilder<Map<String, int>>(
            key: ValueKey('chart_$_refreshKey'),
            future: repo.dailyRevenue(from: from, to: to),
            builder: (ctx, snap) {
              final daily = snap.data ?? {};
              if (daily.isEmpty) return const SizedBox.shrink();
              final entries = daily.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key));
              final maxVal = entries.fold<int>(0, (m, e) => e.value > m ? e.value : m);
              final show7 = entries.length > 7;
              final bars = show7 ? _buildDailyBars(entries, maxVal) : _buildDayBars(entries, maxVal);
              return Container(
                height: 220,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: surf,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: border)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pendapatan Harian',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: labelClr)),
                      const SizedBox(height: 16),
                      Expanded(
                        child: BarChart(BarChartData(
                          barGroups: bars,
                          gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: maxVal > 0 ? (maxVal / 4).ceilToDouble() : 50000),
                          titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (v, meta) {
                                        final idx = v.toInt();
                                        if (idx < 0 || idx >= entries.length) return const SizedBox.shrink();
                                        return _barLabel(idx, entries, isDark: isDark);
                                      },
                                      reservedSize: 28)),
                              leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 52,
                                      getTitlesWidget: (v, meta) => Text(
                                          formatRupiah(v.toInt()),
                                          style: TextStyle(
                                              fontSize: 11, color: textTer)))),
                              topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false))),
                          borderData: FlBorderData(show: false),
                        )),
                      ),
                    ]),
              );
            },
          ),
          // ── Best-Seller ──
          FutureBuilder<List<Map<String, dynamic>>>(
            key: ValueKey('top_$_refreshKey'),
            future: repo.topProducts(from: from, to: to, limit: 5),
            builder: (ctx, snap) {
              final list = snap.data ?? [];
              if (list.isEmpty) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: surf,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: border)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Produk Terlaris',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: labelClr)),
                      const SizedBox(height: 12),
                      ...list.asMap().entries.map((e) {
                        final p = e.value;
                        final qty = (p['qty'] as int?) ?? 0;
                        final rev = (p['revenue'] as int?) ?? 0;
                        final maxQty =
                            list.isNotEmpty ? (list.first['qty'] as int?) ?? 1 : 1;
                        final ratio = maxQty > 0 ? qty / maxQty : 0.0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Expanded(
                                        child: Text('${p['name']}',
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: labelClr)),
                                      ),
                                      Text(formatRupiah(rev),
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: NusaConfig
                                                  .primaryColor)),
                                    ]),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: LinearProgressIndicator(
                                        value: ratio.clamp(0.0, 1.0),
                                        backgroundColor: NusaConfig
                                            .primaryColor
                                            .withValues(alpha: 0.12),
                                        valueColor:
                                            AlwaysStoppedAnimation(
                                                NusaConfig.primaryColor),
                                        minHeight: 4,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text('${qty}x terjual',
                                        style: TextStyle(
                                            fontSize: 11, color: textTer)),
                                  ]),
                            ),
                          ]),
                        );
                      }),
                    ]),
              );
            },
          ),
          // ── Pie: Kategori ──
          FutureBuilder<List<Map<String, dynamic>>>(
            key: ValueKey('cat_$_refreshKey'),
            future: repo.salesByCategory(from: from, to: to),
            builder: (ctx, snap) {
              final list = snap.data ?? [];
              if (list.isEmpty) return const SizedBox.shrink();
              final totalRev = list.fold<int>(
                  0, (s, c) => s + ((c['revenue'] as int?) ?? 0));
              return Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: surf,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: border)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Penjualan per Kategori',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: labelClr)),
                      const SizedBox(height: 12),
                      Row(children: [
                        SizedBox(
                          width: 130,
                          height: 130,
                          child: PieChart(PieChartData(
                            sections: list.asMap().entries.map((e) {
                              final cat = e.value;
                              final pct = totalRev > 0
                                  ? ((cat['revenue'] as int) / totalRev) * 100
                                  : 0.0;
                              return PieChartSectionData(
                                  value: (cat['revenue'] as int).toDouble(),
                                  title: '${pct.toStringAsFixed(0)}%',
                                  titleStyle: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white),
                                  color: _catColors[e.key %
                                      _catColors.length],
                                  radius: 55);
                            }).toList(),
                            sectionsSpace: 2,
                            centerSpaceRadius: 0,
                          )),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                              children: list.take(6).map((c) {
                            final pct = totalRev > 0
                                ? ((c['revenue'] as int) / totalRev) * 100
                                : 0.0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(children: [
                                Container(
                                    width: 10,
                                    height: 10,
                                    margin:
                                        const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                        color: _catColors[list.indexOf(c) %
                                            _catColors.length],
                                        borderRadius:
                                            BorderRadius.circular(2))),
                                Expanded(
                                    child: Text('${c['category']}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: textSec))),
                                Text('${pct.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: labelClr)),
                              ]),
                            );
                          }).toList()),
                        ),
                      ]),
                    ]),
              );
            },
          ),
          // ── Pie: Metode Pembayaran ──
          FutureBuilder<Map<String, int>>(
            key: ValueKey('pay_$_refreshKey'),
            future: repo.salesByPaymentMethod(from: from, to: to),
            builder: (ctx, snap) {
              final pays = snap.data ?? {};
              if (pays.isEmpty || pays.values.every((v) => v == 0)) {
                return const SizedBox.shrink();
              }
              final totalPay = pays.values.fold(0, (s, v) => s + v);
              final sorted = pays.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              return Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: surf,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: border)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Metode Pembayaran',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: labelClr)),
                      const SizedBox(height: 12),
                      Row(children: [
                        SizedBox(
                          width: 130,
                          height: 130,
                          child: PieChart(PieChartData(
                            sections: sorted.asMap().entries.map((e) {
                              final method = e.value.key;
                              final amt = e.value.value;
                              final pct = totalPay > 0
                                  ? (amt / totalPay) * 100
                                  : 0.0;
                              return PieChartSectionData(
                                  value: amt.toDouble(),
                                  title: '${pct.toStringAsFixed(0)}%',
                                  titleStyle: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white),
                                  color: _payColor(method),
                                  radius: 55);
                            }).toList(),
                            sectionsSpace: 2,
                            centerSpaceRadius: 0,
                          )),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                              children: sorted.map((e) {
                            final pct = totalPay > 0
                                ? (e.value / totalPay) * 100
                                : 0.0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(children: [
                                Container(
                                    width: 10,
                                    height: 10,
                                    margin:
                                        const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                        color: _payColor(e.key),
                                        borderRadius:
                                            BorderRadius.circular(2))),
                                Expanded(
                                    child: Text(e.key,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: textSec))),
                                Text('${pct.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: labelClr)),
                              ]),
                            );
                          }).toList()),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text('${formatRupiah(totalPay)} total',
                          style: TextStyle(fontSize: 11, color: textTer)),
                    ]),
              );
            },
          ),
          // ── Export button ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: NusaButton(
              _exporting ? 'Memproses...' : 'Export Laporan',
              fullWidth: true,
              onPressed: _exporting
                  ? null
                  : () async {
                      final data = await repo.summary(from: from, to: to);
                      final items =
                          (data['items'] as List<Transaction>?) ?? [];
                      final top =
                          await repo.topProducts(from: from, to: to);
                      final cats =
                          await repo.salesByCategory(from: from, to: to);
                      final pays = await repo.salesByPaymentMethod(
                          from: from, to: to);
                      await _doExport(items, data, top, cats, pays);
                    },
            ),
          ),
          const SizedBox(height: 12),
          // ── Transaction list ──
          FutureBuilder<List<Transaction>>(
            key: ValueKey('list_$_refreshKey'),
            future: repo.getTransactions(from: from, to: to),
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                    padding: EdgeInsets.all(16), child: SkeletonList());
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                      child: Text('Gagal memuat: ${snap.error}',
                          style: TextStyle(color: textSec))),
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _TxCard(tx: list[i], isDark: isDark),
              );
            },
          ),
        ]),
      ),
    );
  }

  static const _catColors = [
    Color(0xFFE63946),
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
  ];

  Color _payColor(String method) {
    switch (method) {
      case 'Tunai':
        return NusaConfig.payCash;
      case 'QRIS':
        return NusaConfig.payQris;
      case 'Transfer':
        return NusaConfig.payTransfer;
      default:
        return NusaConfig.textSecondary;
    }
  }

  List<BarChartGroupData> _buildDailyBars(List<MapEntry<String, int>> entries, int maxVal) {
    return List.generate(entries.length, (i) {
      return BarChartGroupData(x: i, barRods: [
        BarChartRodData(
            toY: entries[i].value.toDouble(),
            color: NusaConfig.primaryColor.withValues(alpha: 0.85),
            width: entries.length > 15 ? 8 : 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5))),
      ]);
    });
  }

  List<BarChartGroupData> _buildDayBars(List<MapEntry<String, int>> entries, int maxVal) {
    return List.generate(entries.length, (i) {
      return BarChartGroupData(x: i, barRods: [
        BarChartRodData(
            toY: entries[i].value.toDouble(),
            color: NusaConfig.primaryColor.withValues(alpha: 0.85),
            width: 22,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
      ]);
    });
  }

  Widget _barLabel(int idx, List<MapEntry<String, int>> entries, {bool isDark = false}) {
    final key = entries[idx].key;
    // Parse "YYYY-MM-DD" → "DD/MM" or day name
    final parts = key.split('-');
    if (parts.length == 3) {
      if (entries.length <= 7) {
        // Show day names
        final dt = DateTime.tryParse(key);
        if (dt != null) {
          final names = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
          final wd = dt.weekday - 1;
          if (wd >= 0 && wd < 7) {
            return Text(names[wd],
                style: TextStyle(fontSize: 11, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary));
          }
        }
      }
      return Text('${parts[2]}/${parts[1]}',
          style: TextStyle(fontSize: 11, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary));
    }
    return const SizedBox.shrink();
  }

  // ── LABA RUGI TAB ──────────────────────────────────────────────────

  Widget _labaRugiTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (from, to) = _range();
    final repo = ReportRepository(ref.read(databaseProvider));
    final textSec =
        isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary;
    final textTer =
        isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary;

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
                  style: TextStyle(color: textSec)));
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
          child: ListView(padding: const EdgeInsets.all(16), children: [
            // Header card
            NusaCard(Column(children: [
              Text(
                labaBersih >= 0 ? 'Laba Bersih' : 'Rugi Bersih',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textSec),
              ),
              const SizedBox(height: 6),
              Text(formatRupiah(labaBersih.abs()),
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: labaBersih >= 0
                          ? NusaConfig.accentGreenDark
                          : NusaConfig.primaryColor)),
              const SizedBox(height: 4),
              Text('$txCount transaksi',
                  style: TextStyle(fontSize: 12, color: textTer)),
            ])),
            const SizedBox(height: 16),
            _plSection('Pendapatan', [
              _plRow('Pendapatan Penjualan', formatRupiah(pendapatan),
                  isHighlight: true, isDark: isDark),
              _plRow('HPP (Harga Pokok Penjualan)', '${formatRupiah(hpp)}',
                  isDeduct: true, isDark: isDark),
              _plDivider(isDark: isDark),
              _plRow('Laba Kotor', formatRupiah(labaKotor),
                  isBold: true,
                  color: labaKotor >= 0
                      ? NusaConfig.accentGreenDark
                      : NusaConfig.primaryColor,
                  isDark: isDark),
            ], isDark: isDark),
            const SizedBox(height: 12),
            _plSection('Beban', [
              _plRow('Pengeluaran Operasional', formatRupiah(expenses),
                  isDeduct: true, isDark: isDark),
              _plRow('Payroll / Gaji', formatRupiah(payroll),
                  isDeduct: true, isDark: isDark),
              _plRow('Waste / Barang Rusak', formatRupiah(waste),
                  isDeduct: true, isDark: isDark),
              _plRow('Likuiditas Keluar', formatRupiah(liqOut),
                  isDeduct: true, isDark: isDark),
              _plRow('Likuiditas Masuk', formatRupiah(liqIn),
                  isAdd: true, isDark: isDark),
              _plDivider(isDark: isDark),
              _plRow('Total Beban', formatRupiah(totalBeban),
                  isBold: true, isDeduct: true, isDark: isDark),
            ], isDark: isDark),
            const SizedBox(height: 12),
            NusaCard(Column(children: [
              _plRow(
                  'Laba / Rugi Bersih', formatRupiah(labaBersih.abs()),
                  isBold: true,
                  isHighlight: true,
                  color: labaBersih >= 0
                      ? NusaConfig.accentGreenDark
                      : NusaConfig.primaryColor,
                  isDark: isDark),
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
            ])),
            const SizedBox(height: 16),
            Text(
              '* Perhitungan berdasarkan data yang tersedia. HPP dihitung dari harga beli produk.',
              style: TextStyle(
                  fontSize: 11, color: textTer, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ]),
        );
      },
    );
  }

  Widget _plSection(String title, List<Widget> rows, {bool isDark = false}) =>
      NusaCard(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? NusaConfig.darkTextPrimary
                      : NusaConfig.textPrimary)),
          const SizedBox(height: 12),
          ...rows,
        ],
      ));

  Widget _plRow(String label, String value,
      {bool isBold = false,
      bool isDeduct = false,
      bool isAdd = false,
      bool isHighlight = false,
      Color? color,
      bool isDark = false}) {
    final prefix = isDeduct ? '− ' : (isAdd ? '+ ' : '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w500,
                color: isHighlight
                    ? (isDark
                        ? NusaConfig.darkTextPrimary
                        : NusaConfig.textPrimary)
                    : (isDark
                        ? NusaConfig.darkTextSecondary
                        : NusaConfig.textSecondary))),
        Text('$prefix$value',
            style: TextStyle(
                fontSize: 14,
                fontWeight:
                    isBold || isHighlight ? FontWeight.w700 : FontWeight.w600,
                color: color ??
                    (isDeduct
                        ? Colors.red.shade400
                        : isAdd
                            ? Colors.green
                            : (isDark
                                ? NusaConfig.darkTextPrimary
                                : NusaConfig.textPrimary)))),
      ]),
    );
  }

  Widget _plDivider({bool isDark = false}) => Divider(
      height: 16,
      thickness: 1,
      color: isDark ? NusaConfig.darkDivider : NusaConfig.dividerColor);

  // ── MAIN BUILD ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ScreenScaffold(
      'Laporan',
      Column(children: [
        const SizedBox(height: 6),
        // Row: Tabs (left, in 1 card) + period dropdown (right, card style)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            // Segmented toggle in 1 card
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: isDark ? NusaConfig.darkSurface : NusaConfig.backgroundColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
                ),
                child: Row(children: [
                  _segBtn('Penjualan', 0, isDark: isDark),
                  _segBtn('Laba Rugi', 1, isDark: isDark),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            // Period dropdown card-style
            _periodDropdown(isDark),
          ]),
        ),
        const SizedBox(height: 2),
        // Date label for custom
        if (_period == 'Custom')
          Text(_periodLabel(),
              style: TextStyle(
                  fontSize: 12, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
        Expanded(child: _tab == 0 ? _penjualanTab() : _labaRugiTab()),
      ]),
    );
  }

  Widget _periodDropdown(bool isDark) {
    final items = _periodOptions.map((p) => DropdownMenuItem(
      value: p,
      child: Text(p, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    )).toList();

    return Container(
      height: 36,
      constraints: const BoxConstraints(maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface : NusaConfig.backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _periodOptions.contains(_period) ? _period : 'Custom',
          isExpanded: true,
          isDense: true,
          icon: Icon(Icons.expand_more_rounded, size: 18,
              color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
          dropdownColor: isDark ? NusaConfig.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(12),
          underline: const SizedBox.shrink(),
          items: items,
          onChanged: (v) {
            if (v == null) return;
            if (v == 'Custom') {
              _pickDateRange();
              return;
            }
            setState(() {
              _period = v;
              _customFrom = null;
              _customTo = null;
              _refreshKey++;
            });
          },
        ),
      ),
    );
  }

  Widget _segBtn(String label, int idx, {bool isDark = false}) {
    final sel = idx == _tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = idx),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? NusaConfig.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: sel
                    ? Colors.white
                    : (isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
              )),
        ),
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final bool isDark;
  const _StatCard(this.title, this.value, {required this.isDark});

  @override
  Widget build(BuildContext context) => NusaCard(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? NusaConfig.darkTextSecondary
                      : NusaConfig.textSecondary)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: NusaConfig.primaryColor)),
        ]),
      );
}

class _GrowthBadge extends StatelessWidget {
  final String label;
  final double pct;
  final bool isDark;
  const _GrowthBadge(this.label, this.pct, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    final up = pct >= 0;
    final color = up ? NusaConfig.accentGreenDark : NusaConfig.primaryColor;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: up
              ? NusaConfig.successSoft.withValues(alpha: 0.5)
              : NusaConfig.errorSoft.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(up ? Icons.trending_up : Icons.trending_down,
              size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? NusaConfig.darkTextSecondary
                              : NusaConfig.textSecondary)),
                  Text('${up ? "+" : ""}${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ]),
          ),
        ]),
      ),
    );
  }
}

class _TxCard extends StatelessWidget {
  final Transaction tx;
  final bool isDark;
  const _TxCard({required this.tx, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${tx.date.day}/${tx.date.month}/${tx.date.year} ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}';
    final isVoided = tx.status == 'Void';
    final textPri =
        isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary;
    final textSec =
        isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary;

    return NusaCard(
      Opacity(
        opacity: isVoided ? 0.55 : 1.0,
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(tx.invoice,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textPri)),
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
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: NusaConfig.primaryColor)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Text('$dateStr • ${tx.paymentMethod}',
                      style: TextStyle(fontSize: 13, color: textSec)),
                ]),
          ),
          Text(formatRupiah(tx.total),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: NusaConfig.primaryColor)),
        ]),
      ),
    );
  }
}
