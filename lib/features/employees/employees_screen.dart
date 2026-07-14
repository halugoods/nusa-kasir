import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/attendance_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});
  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  final _roles = const ['Owner', 'Manager', 'Kasir', 'Gudang', 'Finance'];
  List<Employee> _employees = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

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
    String role = employee?.role ?? _roles.first;
    String? error;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(employee == null ? 'Tambah Karyawan' : 'Edit Karyawan',
              style: const TextStyle(fontWeight: FontWeight.w700)),
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
                Text(error!,
                    style: const TextStyle(
                        color: NusaConfig.primaryColor, fontSize: 13)),
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
                final repo =
                    AttendanceRepository(ref.read(databaseProvider));
                if (employee == null) {
                  await repo.addEmployee(
                      name: name, pin: pin, role: role);
                } else {
                  await repo.updateEmployee(
                      id: employee.id, name: name, pin: pin, role: role);
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

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      'Karyawan',
      _loading
          ? const Center(child: CircularProgressIndicator())
          : _employees.isEmpty
              ? const EmptyState(
                  icon: Icons.people_outline,
                  message: 'Belum ada karyawan. Tambah lewat tombol +',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _employees.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final e = _employees[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: NusaConfig.surfaceColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: NusaConfig.borderColor),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              NusaConfig.primaryColor.withValues(alpha: 0.12),
                          child: Text(
                            e.name.isNotEmpty
                                ? e.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: NusaConfig.primaryColor,
                            ),
                          ),
                        ),
                        title: Text(e.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(e.role,
                            style: const TextStyle(fontSize: 12)),
                        trailing: PopupMenuButton<String>(
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
                      ),
                    );
                  },
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
