import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/app.dart';
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
      setState(() {
        _expenses = results[0] as List<Expense>;
        _payroll = results[1] as List<PayrollData>;
        _waste = results[2] as List<WasteData>;
        _liquidity = results[3] as List<LiquidityData>;
        _employees = results[4] as List<Employee>;
        _products = results[5] as List<Product>;
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

  Widget _chip(int i) {
    final sel = i == _tab;
    return FilterChip(
      label: Text(_tabs[i]),
      selected: sel,
      showCheckmark: false,
      selectedColor: NusaConfig.primaryColor,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: sel ? Colors.white : NusaConfig.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: NusaConfig.surfaceColor,
      onSelected: (_) => setState(() => _tab = i),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      'Keuangan',
      Column(
        children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _chip(i),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _body(),
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

  Widget _body() {
    switch (_tab) {
      case 0:
        return _listView(
          _expenses.isEmpty,
          _expenses
              .map((e) => NusaCard(
                    Row(
                      children: [
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
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: NusaConfig.textSecondary)),
                              const SizedBox(height: 2),
                              Text(_date(e.date),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: NusaConfig.textSecondary)),
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
                            Container(
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
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Periode: ${p.period}',
                            style: const TextStyle(
                                fontSize: 13, color: NusaConfig.textSecondary)),
                        const SizedBox(height: 4),
                        Text(
                            'Gaji: ${formatRupiah(p.salary)} • Bonus: ${formatRupiah(p.bonus)} • Potong: ${formatRupiah(p.deduction)}',
                            style: const TextStyle(
                                fontSize: 13, color: NusaConfig.textSecondary)),
                      ],
                    ),
                  ))
              .toList(),
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
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: NusaConfig.textSecondary)),
                              if (w.reason != null && w.reason!.isNotEmpty)
                                Text(w.reason!,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: NusaConfig.textSecondary)),
                            ],
                          ),
                        ),
                        Text(_date(w.date),
                            style: const TextStyle(
                                fontSize: 12, color: NusaConfig.textSecondary)),
                      ],
                    ),
                  ))
              .toList(),
        );
      default:
        return _listView(
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
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: NusaConfig.textSecondary)),
                              if (l.method != null)
                                Text('Metode: ${l.method}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: NusaConfig.textSecondary)),
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
        );
    }
  }

  Widget _listView(bool empty, List<Widget> children) {
    if (empty) {
      return const EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        message: 'Belum ada data',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => children[i],
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
                const Text('Belum ada karyawan.',
                    style: TextStyle(color: Colors.grey))
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
                const Text('Belum ada produk.',
                    style: TextStyle(color: Colors.grey))
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
              await f.addWaste(
                productId: prodId,
                qty: int.tryParse(qtyC.text.trim()) ?? 0,
                reason: reasonC.text.trim(),
                type: type,
              );
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
