import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/attendance_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  final _roles = const ['Owner', 'Manager', 'Kasir', 'Gudang', 'Finance'];
  List<Employee> _employees = [];
  Map<int, AttendanceData?> _today = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = AttendanceRepository(ref.read(databaseProvider));
    final emps = await repo.getEmployees();
    final map = <int, AttendanceData?>{};
    for (final e in emps) {
      map[e.id] = await repo.getToday(e.id);
    }
    if (mounted) {
      setState(() {
        _employees = emps;
        _today = map;
      });
    }
  }

  Future<void> _checkIn(Employee e) async {
    final repo = AttendanceRepository(ref.read(databaseProvider));
    await repo.checkIn(e.id);
    _load();
  }

  Future<void> _checkOut(Employee e) async {
    final repo = AttendanceRepository(ref.read(databaseProvider));
    await repo.checkOut(e.id);
    _load();
  }

  void _setPettyCash(Employee e) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kas Kecil'),
        content: NusaInput('Jumlah kas kecil (Rp)',
            controller: controller, type: TextInputType.number),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal')),
          NusaButton('Simpan', fullWidth: false, onPressed: () async {
            final amount = int.tryParse(controller.text.trim()) ?? 0;
            final repo = AttendanceRepository(ref.read(databaseProvider));
            await repo.setPettyCashForToday(e.id, amount);
            if (mounted) Navigator.of(context).pop();
            _load();
          }),
        ],
      ),
    );
  }

  void _addEmployee() {
    final nameC = TextEditingController();
    final pinC = TextEditingController();
    String role = _roles.first;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Tambah Karyawan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NusaInput('Nama', controller: nameC),
              const SizedBox(height: 12),
              NusaInput('PIN', controller: pinC, type: TextInputType.number),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14))),
                ),
                items: _roles
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setSt(() => role = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Batal')),
            NusaButton('Simpan', fullWidth: false, onPressed: () async {
              final name = nameC.text.trim();
              final pin = pinC.text.trim();
              if (name.isEmpty || pin.isEmpty) return;
              final repo = AttendanceRepository(ref.read(databaseProvider));
              await repo.addEmployee(name: name, pin: pin, role: role);
              if (mounted) Navigator.of(context).pop();
              _load();
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      'Presensi',
      _employees.isEmpty
          ? const Center(
              child: Text('Belum ada karyawan. Tambah lewat tombol +',
                  style: TextStyle(color: Colors.grey)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _employees.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) =>
                  _EmployeeAttendance(employee: _employees[i], today: _today[_employees[i].id], onIn: () => _checkIn(_employees[i]), onOut: () => _checkOut(_employees[i]), onCash: () => _setPettyCash(_employees[i])),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NusaConfig.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Karyawan'),
        onPressed: _addEmployee,
      ),
    );
  }
}

class _EmployeeAttendance extends StatelessWidget {
  final Employee employee;
  final AttendanceData? today;
  final VoidCallback onIn;
  final VoidCallback onOut;
  final VoidCallback onCash;
  const _EmployeeAttendance(
      {required this.employee,
      required this.today,
      required this.onIn,
      required this.onOut,
      required this.onCash});

  @override
  Widget build(BuildContext context) {
    final inTime = today?.checkIn;
    final outTime = today?.checkOut;
    final cash = today?.pettyCash;
    return NusaCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(employee.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: NusaConfig.primaryColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(employee.role,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: NusaConfig.primaryColor)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _Info('Masuk', inTime ?? '-',
                      color: inTime != null ? Colors.green : null)),
              Expanded(
                  child: _Info('Pulang', outTime ?? '-',
                      color: outTime != null ? Colors.green : null)),
              Expanded(
                  child: _Info('Kas Kecil',
                      cash != null ? formatRupiah(cash) : '-')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: inTime != null ? null : onIn,
                  child: const Text('Absen Masuk'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      (inTime != null && outTime == null) ? onOut : null,
                  child: const Text('Absen Pulang'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onCash,
                  child: const Text('Kas Kecil'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Info(this.label, this.value, {this.color});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: NusaConfig.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color ?? NusaConfig.textPrimary)),
        ],
      );
}
