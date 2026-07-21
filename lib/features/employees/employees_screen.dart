import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/attendance_repository.dart';
import 'package:nusa_kasir/data/repositories/role_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';
import 'package:url_launcher/url_launcher.dart';

const _avatarColors = [
  Color(0xFFE63946),
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFF8B5CF6),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
];

Color _avatarColor(String name) {
  final hash = name.runes.fold(0, (a, b) => a + b);
  return _avatarColors[hash % _avatarColors.length];
}

const _roleColors = {
  'Owner': Color(0xFF8B5CF6),
  'Manager': Color(0xFF3B82F6),
  'Kasir': Color(0xFF10B981),
  'Gudang': Color(0xFFF59E0B),
  'Finance': Color(0xFFEC4899),
};

Widget _roleBadge(String role) {
  final color = _roleColors[role] ?? const Color(0xFF3B82F6);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      role,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});
  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  List<String> _roles = const ['Owner', 'Manager', 'Kasir', 'Gudang', 'Finance'];
  List<Employee> _employees = [];
  bool _loading = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.toLowerCase()));
    _load();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    final repo = RoleRepository();
    final roles = await repo.getRoles();
    if (mounted) {
      setState(() => _roles = roles.map((r) => r['name'] as String).toList());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Employee> get _filtered => _query.isEmpty
      ? _employees
      : _employees.where((e) =>
          e.name.toLowerCase().contains(_query) ||
          e.role.toLowerCase().contains(_query)).toList();

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = AttendanceRepository(ref.read(databaseProvider));
    final emps = await repo.getEmployees();
    if (mounted) {
      setState(() {
        _employees = emps;
        _loading = false;
      });
    }
  }

  void _showForm({Employee? employee}) {
    final nameC = TextEditingController(text: employee?.name ?? '');
    final pinC = TextEditingController(text: employee?.pin ?? '');
    final phoneC = TextEditingController(text: employee?.phone ?? '');
    String role = employee?.role ?? _roles.first;
    String? error;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(employee == null ? 'Tambah Karyawan' : 'Edit Karyawan',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
              )),
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
              NusaInput('No. WA (opsional)',
                  controller: phoneC,
                  type: TextInputType.phone,
                  hint: 'Cth: 08123456789',
                  prefixIcon: Icon(Icons.phone, size: 18,
                      color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _roles.contains(role) ? role : _roles.first,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: 'Role',
                  labelStyle: TextStyle(
                    color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                  ),
                  filled: true,
                  fillColor: isDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder)),
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
                Text(error!,
                    style: const TextStyle(
                        color: NusaConfig.primaryColor, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Batal',
                    style: TextStyle(color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary))),
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
                final phone = phoneC.text.trim();
                if (phone.isNotEmpty) {
                  final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
                  if (clean.length < 10 || !clean.startsWith('0')) {
                    setSt(() => error = 'No. WA harus valid (08xx, min 10 digit)');
                    return;
                  }
                }
                final repo = AttendanceRepository(ref.read(databaseProvider));
                if (employee == null) {
                  await repo.addEmployee(
                      name: name, pin: pin, role: role,
                      phone: phone.isNotEmpty ? phone : null);
                } else {
                  await repo.updateEmployee(
                      id: employee.id, name: name, pin: pin, role: role,
                      phone: phone.isNotEmpty ? phone : null);
                }
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

  Future<void> _delete(Employee e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Karyawan'),
        content: Text('Hapus ${e.name}? Data presensi tetap tersimpan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus',
                style: TextStyle(color: NusaConfig.primaryColor)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final repo = AttendanceRepository(ref.read(databaseProvider));
      await repo.deleteEmployee(e.id);
      _load();
    }
  }

  Future<void> _openWA(Employee e) async {
    if (e.phone == null || e.phone!.isEmpty) return;
    final phone = e.phone!.replaceAll(RegExp(r'[^0-9]'), '');
    var num = phone;
    if (num.startsWith('0')) num = '62${num.substring(1)}';
    final uri = Uri.parse('https://wa.me/$num');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final employees = _filtered;

    return ScreenScaffold(
      'Karyawan',
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: NusaInput(
              'Cari karyawan...',
              controller: _searchCtrl,
              type: TextInputType.text,
              prefixIcon: Icon(Icons.search, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _employees.isEmpty
                    ? const EmptyState(
                        icon: Icons.people_outline,
                        message: 'Belum ada karyawan. Tambah lewat tombol +',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: employees.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final e = employees[i];
                            return NusaCard(
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: _avatarColor(e.name),
                                      child: Text(
                                        e.name.isNotEmpty
                                            ? e.name[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            e.name,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          _roleBadge(e.role),
                                          if (e.phone != null && e.phone!.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            GestureDetector(
                                              onTap: () => _openWA(e),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.phone_android, size: 14,
                                                      color: const Color(0xFF25D366)),
                                                  const SizedBox(width: 4),
                                                  Text(e.phone!,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                                                      )),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      color: isDark ? NusaConfig.darkSurface : null,
                                      onSelected: (v) {
                                        if (v == 'edit') _showForm(employee: e);
                                        if (v == 'delete') _delete(e);
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                            value: 'edit', child: Text('Edit')),
                                        const PopupMenuItem(
                                            value: 'delete', child: Text('Hapus')),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NusaConfig.primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Karyawan',
            style: TextStyle(fontWeight: FontWeight.w600)),
        onPressed: () => _showForm(),
      ),
    );
  }
}
