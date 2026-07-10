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
import 'package:nusa_kasir/shared/widgets/empty_state.dart';

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Kas Kecil',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: NusaInput('Jumlah kas kecil (Rp)',
            controller: controller, type: TextInputType.number),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal',
                  style: TextStyle(color: NusaConfig.textSecondary))),
          ElevatedButton(
            onPressed: () async {
              final amount = int.tryParse(controller.text.trim()) ?? 0;
              final repo = AttendanceRepository(ref.read(databaseProvider));
              await repo.setPettyCashForToday(e.id, amount);
              if (mounted) Navigator.of(context).pop();
              _load();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: NusaConfig.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _addEmployee() {
    final nameC = TextEditingController();
    final pinC = TextEditingController();
    String role = _roles.first;
    String? error;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Tambah Karyawan',
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NusaInput('Nama', controller: nameC),
              const SizedBox(height: 12),
              NusaInput('PIN (4-6 digit)',
                  controller: pinC,
                  type: TextInputType.number,
                  obscure: true),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: InputDecoration(
                  labelText: 'Role',
                  filled: true,
                  fillColor: NusaConfig.backgroundColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: NusaConfig.borderColor)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: NusaConfig.borderColor)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: NusaConfig.primaryColor, width: 1.5)),
                ),
                items: _roles
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setSt(() => role = v!),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: NusaConfig.primaryColor, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Batal',
                    style: TextStyle(color: NusaConfig.textSecondary))),
            ElevatedButton(
              onPressed: () async {
                final name = nameC.text.trim();
                final pin = pinC.text.trim();
                if (name.isEmpty || pin.isEmpty) {
                  setSt(() => error = 'Nama dan PIN wajib diisi');
                  return;
                }
                if (pin.length < 4 || pin.length > 6 || int.tryParse(pin) == null) {
                  setSt(() => error = 'PIN harus 4-6 digit angka');
                  return;
                }
                final repo = AttendanceRepository(ref.read(databaseProvider));
                await repo.addEmployee(name: name, pin: pin, role: role);
                if (mounted) Navigator.of(context).pop();
                _load();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: NusaConfig.primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ScreenScaffold(
      'Presensi',
      _employees.isEmpty
          ? const EmptyState(
              icon: Icons.person_outline,
              message: 'Belum ada karyawan. Tambah lewat tombol +',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _employees.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _EmployeeCard(
                  employee: _employees[i],
                  today: _today[_employees[i].id],
                  isDark: isDark,
                  onIn: () => _checkIn(_employees[i]),
                  onOut: () => _checkOut(_employees[i]),
                  onCash: () => _setPettyCash(_employees[i]),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NusaConfig.primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Karyawan',
            style: TextStyle(fontWeight: FontWeight.w600)),
        onPressed: _addEmployee,
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final Employee employee;
  final AttendanceData? today;
  final bool isDark;
  final VoidCallback onIn;
  final VoidCallback onOut;
  final VoidCallback onCash;

  const _EmployeeCard({
    required this.employee,
    required this.today,
    required this.isDark,
    required this.onIn,
    required this.onOut,
    required this.onCash,
  });

  @override
  Widget build(BuildContext context) {
    final inTime = today?.checkIn;
    final outTime = today?.checkOut;
    final cash = today?.pettyCash;
    final isCheckedIn = inTime != null;
    final isCheckedOut = outTime != null;

    return NusaCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: NusaConfig.primaryColor.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: Text(
                  employee.name.isNotEmpty
                      ? employee.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: NusaConfig.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(employee.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: NusaConfig.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(employee.role,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: NusaConfig.primaryColor)),
                        ),
                        const SizedBox(width: 10),
                        // Status indicator
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCheckedIn
                                ? (isCheckedOut
                                    ? const Color(0xFF9CA3AF)
                                    : const Color(0xFF10B981))
                                : const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isCheckedIn
                              ? (isCheckedOut ? 'Selesai' : 'Aktif')
                              : 'Belum absen',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isCheckedIn
                                ? (isCheckedOut
                                    ? const Color(0xFF9CA3AF)
                                    : const Color(0xFF10B981))
                                : const Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Times row
          Row(
            children: [
              Expanded(
                child: _Info(
                  icon: Icons.login_rounded,
                  label: 'Masuk',
                  value: inTime ?? '-',
                  color: inTime != null ? NusaConfig.accentGreen : null,
                ),
              ),
              Expanded(
                child: _Info(
                  icon: Icons.logout_rounded,
                  label: 'Pulang',
                  value: outTime ?? '-',
                  color: outTime != null ? NusaConfig.accentGreen : null,
                ),
              ),
              Expanded(
                child: _Info(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Kas Kecil',
                  value: cash != null ? formatRupiah(cash) : '-',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  label: 'Absen Masuk',
                  color: NusaConfig.accentGreen,
                  enabled: !isCheckedIn,
                  onTap: onIn,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionBtn(
                  label: 'Absen Pulang',
                  color: const Color(0xFFEF4444),
                  enabled: isCheckedIn && !isCheckedOut,
                  onTap: onOut,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionBtn(
                  label: 'Kas Kecil',
                  color: NusaConfig.accentPurple,
                  enabled: true,
                  onTap: onCash,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: enabled ? onTap : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.3),
        disabledForegroundColor: Colors.white54,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _Info extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _Info({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color ?? NusaConfig.textSecondary),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: NusaConfig.textSecondary)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: color ?? NusaConfig.textPrimary)),
            ],
          ),
        ],
      );
}
