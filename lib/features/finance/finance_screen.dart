import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/attendance_repository.dart';
import 'package:nusa_kasir/data/repositories/finance_repository.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';

class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});
  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  final _tabs = const ['Pengeluaran', 'Payroll', 'Waste', 'Likuiditas'];
  int _tab = 0;
  List<Expense> _expenses = [];
  List<PayrollData> _payroll = [];
  List<WasteData> _waste = [];
  List<LiquidityData> _liquidity = [];
  List<Employee> _employees = [];
  List<Product> _products = [];

  int _totalExpenseThisMonth = 0;
  int _totalPayroll = 0;
  int _totalWasteCost = 0;
  int _runningBalance = 0;
  int _periodFilter = 0; // 0: Bulan Ini, 1: Minggu Ini, 2: Semua

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = FinanceRepository(ref.read(databaseProvider));
    final empRepo = AttendanceRepository(ref.read(databaseProvider));
    final prodRepo = ProductRepository(ref.read(databaseProvider));
    final results = await Future.wait([
      f.getExpenses(),
      f.getPayroll(),
      f.getWaste(),
      f.getLiquidity(),
      empRepo.getEmployees(),
      prodRepo.getProducts(),
    ]);
    if (mounted) {
      final now = DateTime.now();
      final expThisMonth = results[0] is List<Expense>
          ? (results[0] as List<Expense>)
              .where((e) => e.date.year == now.year && e.date.month == now.month)
              .fold<int>(0, (sum, e) => sum + e.amount)
          : 0;
      final allPayroll = results[1] is List<PayrollData>
          ? (results[1] as List<PayrollData>)
              .fold<int>(0, (sum, p) => sum + p.salary + p.bonus - p.deduction)
          : 0;
      final allWasteCost = results[2] is List<WasteData>
          ? (results[2] as List<WasteData>).length // count-based, or sum qty
          : 0;
      int balance = 0;
      if (results[3] is List<LiquidityData>) {
        for (final l in results[3] as List<LiquidityData>) {
          balance += l.type == 'in' ? l.amount : -l.amount;
        }
      }
      setState(() {
        _expenses = results[0] as List<Expense>;
        _payroll = results[1] as List<PayrollData>;
        _waste = results[2] as List<WasteData>;
        _liquidity = results[3] as List<LiquidityData>;
        _employees = results[4] as List<Employee>;
        _products = results[5] as List<Product>;
        _totalExpenseThisMonth = expThisMonth;
        _totalPayroll = allPayroll;
        _totalWasteCost = allWasteCost;
        _runningBalance = balance;
      });
    }
  }

  String _empName(int id) {
    for (final e in _employees) {
      if (e.id == id) return e.name;
    }
    return 'ID $id';
  }

  String _prodName(int id) {
    for (final p in _products) {
      if (p.id == id) return p.name;
    }
    return 'ID $id';
  }

  IconData _iconForCategory(String cat) => switch (cat.toLowerCase()) {
    'operasional' => Icons.settings,
    'listrik' || 'air' || 'internet' => Icons.electrical_services,
    'belanja' || 'bahan' => Icons.shopping_cart,
    'gaji' || 'payroll' => Icons.people,
    _ => Icons.money_off,
  };

  List<Expense> get _filteredExpenses {
    final now = DateTime.now();
    if (_periodFilter == 1) {
      // Minggu ini
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      return _expenses.where((e) => e.date.isAfter(weekStart.subtract(const Duration(days: 1)))).toList();
    } else if (_periodFilter == 0) {
      // Bulan ini
      return _expenses.where((e) => e.date.year == now.year && e.date.month == now.month).toList();
    }
    return _expenses; // Semua
  }

  Widget _chip(int i, bool isDark) {
    final sel = i == _tab;
    return FilterChip(
      label: Text(_tabs[i]),
      selected: sel,
      showCheckmark: false,
      selectedColor: NusaConfig.primaryColor,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: sel ? Colors.white : isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: NusaConfig.surfaceColor,
      onSelected: (_) => setState(() => _tab = i),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ScreenScaffold(
      'Keuangan',
      Column(
        children: [
          // ── Summary cards ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              _SummaryCard(
                label: 'Pengeluaran Bulan Ini',
                value: formatRupiah(_totalExpenseThisMonth),
                icon: Icons.money_off,
                color: NusaConfig.primaryColor,
              ),
              const SizedBox(width: 10),
              _SummaryCard(
                label: 'Total Payroll',
                value: formatRupiah(_totalPayroll),
                icon: Icons.people,
                color: const Color(0xFF8B5CF6),
              ),
              const SizedBox(width: 10),
              _SummaryCard(
                label: 'Total Waste',
                value: '$_totalWasteCost item',
                icon: Icons.delete_outline,
                color: const Color(0xFFEF4444),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // ── Tab chips ──
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _chip(i, isDark),
            ),
          ),
          // ── Period filter (only for Pengeluaran) ──
          if (_tab == 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                _PeriodChip('Bulan Ini', 0, isDark),
                const SizedBox(width: 8),
                _PeriodChip('Minggu Ini', 1, isDark),
                const SizedBox(width: 8),
                _PeriodChip('Semua', 2, isDark),
              ]),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: _body(isDark),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NusaConfig.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text('Tambah ${_tabs[_tab]}'),
        onPressed: _showAdd,
      ),
    );
  }

  Widget _PeriodChip(String label, int idx, bool isDark) {
    final sel = _periodFilter == idx;
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
      selected: sel,
      showCheckmark: false,
      selectedColor: NusaConfig.primaryColor,
      backgroundColor: NusaConfig.surfaceColor,
      onSelected: (_) => setState(() => _periodFilter = idx),
    );
  }

  Widget _body(bool isDark) {
    final f = FinanceRepository(ref.read(databaseProvider));
    switch (_tab) {
      case 0:
        final filtered = _filteredExpenses;
        return _listView(
          filtered.isEmpty,
          filtered
              .map((e) => NusaCard(
                    Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: NusaConfig.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(_iconForCategory(e.category), size: 20, color: NusaConfig.primaryColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.category,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(e.description,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                              const SizedBox(height: 2),
                              Text(_date(e.date),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                            ],
                          ),
                        ),
                        Text(formatRupiah(e.amount),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.red)),
                      ],
                    ),
                  ))
              .toList(),
          onDelete: (i) async { await f.deleteExpense(filtered[i].id); await _load(); },
        );
      case 1:
        return _listView(
          _payroll.isEmpty,
          _payroll
              .map((p) => NusaCard(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(_empName(p.employeeId),
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final next = p.status == 'Paid' ? 'Pending' : 'Paid';
                                await f.updatePayrollStatus(p.id, next);
                                await _load();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: p.status == 'Paid'
                                      ? Colors.green.withOpacity(0.15)
                                      : NusaConfig.primaryColor
                                          .withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(p.status,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: p.status == 'Paid'
                                            ? Colors.green
                                            : NusaConfig.primaryColor)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Periode: ${p.period}',
                            style: TextStyle(
                                fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                        const SizedBox(height: 4),
                        Text(
                            'Gaji: ${formatRupiah(p.salary)} • Bonus: ${formatRupiah(p.bonus)} • Potong: ${formatRupiah(p.deduction)}',
                            style: TextStyle(
                                fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                      ],
                    ),
                  ))
              .toList(),
          onDelete: (i) async { await f.deletePayroll(_payroll[i].id); await _load(); },
        );
      case 2:
        return _listView(
          _waste.isEmpty,
          _waste
              .map((w) => NusaCard(
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_prodName(w.productId),
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('${w.qty} pcs • ${w.type}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                              if (w.reason != null && w.reason!.isNotEmpty)
                                Text(w.reason!,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                            ],
                          ),
                        ),
                        Text(_date(w.date),
                            style: TextStyle(
                                fontSize: 12, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                      ],
                    ),
                  ))
              .toList(),
          onDelete: (i) async { await f.deleteWaste(_waste[i].id); await _load(); },
        );
      default:
        return Column(
          children: [
            // Running balance header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Text('Saldo Berjalan: ', style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                  Text(
                    formatRupiah(_runningBalance),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _runningBalance >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _listView(
                _liquidity.isEmpty,
                _liquidity
                    .map((l) => NusaCard(
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(l.category,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text(l.description,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                                    if (l.method != null)
                                      Text('Metode: ${l.method}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                                  ],
                                ),
                              ),
                              Text(
                                '${l.type == 'in' ? '+ ' : '- '}${formatRupiah(l.amount)}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: l.type == 'in' ? Colors.green : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
                onDelete: (i) async { await f.deleteLiquidity(_liquidity[i].id); await _load(); },
              ),
            ),
          ],
        );
    }
  }

  Widget _listView(bool empty, List<Widget> children, {Future<void> Function(int)? onDelete}) {
    if (empty) {
      return const EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        message: 'Belum ada data',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: children.length,
        itemBuilder: (_, i) {
          final child = children[i];
          if (onDelete == null) return Padding(padding: const EdgeInsets.only(bottom: 12), child: child);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Dismissible(
              key: ValueKey(i),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) async {
                return await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Hapus'),
                    content: const Text('Yakin hapus data ini?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ) ?? false;
              },
              onDismissed: (_) => onDelete(i),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: NusaConfig.primaryColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

  void _showAdd() {
    switch (_tab) {
      case 0:
        _addExpense();
        break;
      case 1:
        _addPayroll();
        break;
      case 2:
        _addWaste();
        break;
      default:
        _addLiquidity();
    }
  }

  void _addExpense() {
    final catC = TextEditingController();
    final descC = TextEditingController();
    final amtC = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tambah Pengeluaran'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NusaInput('Kategori', controller: catC),
            const SizedBox(height: 12),
            NusaInput('Keterangan', controller: descC),
            const SizedBox(height: 12),
            NusaInput('Jumlah (Rp)', controller: amtC, type: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal')),
          NusaButton('Simpan', fullWidth: false, onPressed: () async {
            final cat = catC.text.trim();
            final desc = descC.text.trim();
            final amt = int.tryParse(amtC.text.trim()) ?? 0;
            if (cat.isEmpty) return;
            final f = FinanceRepository(ref.read(databaseProvider));
            await f.addExpense(category: cat, description: desc, amount: amt);
            if (mounted) Navigator.of(context).pop();
            _load();
          }),
        ],
      ),
    );
  }

  void _addPayroll() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final periodC = TextEditingController();
    final salaryC = TextEditingController();
    final bonusC = TextEditingController();
    final dedC = TextEditingController();
    int empId = _employees.isNotEmpty ? _employees.first.id : 0;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Tambah Payroll'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_employees.isEmpty)
                Text('Belum ada karyawan.',
                    style: TextStyle(color: isDark ? NusaConfig.darkTextSecondary : Colors.grey))
              else
                DropdownButtonFormField<int>(
                  value: empId,
                  decoration: const InputDecoration(
                    labelText: 'Karyawan',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14))),
                  ),
                  items: _employees
                      .map((e) =>
                          DropdownMenuItem(value: e.id, child: Text(e.name)))
                      .toList(),
                  onChanged: (v) => setSt(() => empId = v!),
                ),
              const SizedBox(height: 12),
              NusaInput('Periode (cth: Jun 26)', controller: periodC),
              const SizedBox(height: 12),
              NusaInput('Gaji (Rp)', controller: salaryC, type: TextInputType.number),
              const SizedBox(height: 12),
              NusaInput('Bonus (Rp)', controller: bonusC, type: TextInputType.number),
              const SizedBox(height: 12),
              NusaInput('Potongan (Rp)', controller: dedC, type: TextInputType.number),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Batal')),
            NusaButton('Simpan', fullWidth: false, onPressed: () async {
              if (_employees.isEmpty) return;
              final f = FinanceRepository(ref.read(databaseProvider));
              await f.addPayroll(
                employeeId: empId,
                period: periodC.text.trim(),
                salary: int.tryParse(salaryC.text.trim()) ?? 0,
                bonus: int.tryParse(bonusC.text.trim()) ?? 0,
                deduction: int.tryParse(dedC.text.trim()) ?? 0,
              );
              if (mounted) Navigator.of(context).pop();
              _load();
            }),
          ],
        ),
      ),
    );
  }

  void _addWaste() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final qtyC = TextEditingController();
    final reasonC = TextEditingController();
    String type = 'Expired';
    int prodId = _products.isNotEmpty ? _products.first.id : 0;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Tambah Waste'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_products.isEmpty)
                Text('Belum ada produk.',
                    style: TextStyle(color: isDark ? NusaConfig.darkTextSecondary : Colors.grey))
              else
                DropdownButtonFormField<int>(
                  value: prodId,
                  decoration: const InputDecoration(
                    labelText: 'Produk',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14))),
                  ),
                  items: _products
                      .map((p) =>
                          DropdownMenuItem(value: p.id, child: Text(p.name)))
                      .toList(),
                  onChanged: (v) => setSt(() => prodId = v!),
                ),
              const SizedBox(height: 12),
              NusaInput('Jumlah (pcs)', controller: qtyC, type: TextInputType.number),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(
                  labelText: 'Tipe',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14))),
                ),
                items: const [
                  DropdownMenuItem(value: 'Expired', child: Text('Expired')),
                  DropdownMenuItem(value: 'Rusak', child: Text('Rusak')),
                  DropdownMenuItem(value: 'Lainnya', child: Text('Lainnya')),
                ],
                onChanged: (v) => setSt(() => type = v!),
              ),
              const SizedBox(height: 12),
              NusaInput('Alasan', controller: reasonC),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Batal')),
            NusaButton('Simpan', fullWidth: false, onPressed: () async {
              if (_products.isEmpty) return;
              final f = FinanceRepository(ref.read(databaseProvider));
              final qty = int.tryParse(qtyC.text.trim()) ?? 0;
              await f.addWaste(
                productId: prodId,
                qty: qty,
                reason: reasonC.text.trim(),
                type: type,
              );
              // Auto-reduce stock
              if (qty > 0) {
                await ProductRepository(ref.read(databaseProvider))
                    .adjustStock(prodId, -qty);
              }
              if (mounted) Navigator.of(context).pop();
              _load();
            }),
          ],
        ),
      ),
    );
  }

  void _addLiquidity() {
    final catC = TextEditingController();
    final descC = TextEditingController();
    final amtC = TextEditingController();
    final methodC = TextEditingController();
    String type = 'in';
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Tambah Likuiditas'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(
                  labelText: 'Tipe',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14))),
                ),
                items: const [
                  DropdownMenuItem(value: 'in', child: Text('Masuk')),
                  DropdownMenuItem(value: 'out', child: Text('Keluar')),
                ],
                onChanged: (v) => setSt(() => type = v!),
              ),
              const SizedBox(height: 12),
              NusaInput('Kategori', controller: catC),
              const SizedBox(height: 12),
              NusaInput('Keterangan', controller: descC),
              const SizedBox(height: 12),
              NusaInput('Jumlah (Rp)', controller: amtC, type: TextInputType.number),
              const SizedBox(height: 12),
              NusaInput('Metode (opsional)', controller: methodC),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Batal')),
            NusaButton('Simpan', fullWidth: false, onPressed: () async {
              final f = FinanceRepository(ref.read(databaseProvider));
              await f.addLiquidity(
                type: type,
                category: catC.text.trim(),
                description: descC.text.trim(),
                amount: int.tryParse(amtC.text.trim()) ?? 0,
                method: methodC.text.trim().isEmpty ? null : methodC.text.trim(),
              );
              if (mounted) Navigator.of(context).pop();
              _load();
            }),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryCard({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? NusaConfig.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? NusaConfig.darkBorder : const Color(0xFFF3F4F6)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
        ]),
      ),
    );
  }
}
