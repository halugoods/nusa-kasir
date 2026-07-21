import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
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

const _statusOptions = ['Aktif', 'Cuti', 'Nonaktif', 'Resign'];
const _statusColors = {
  'Aktif': Color(0xFF10B981),
  'Cuti': Color(0xFFF59E0B),
  'Nonaktif': Color(0xFF9CA3AF),
  'Resign': Color(0xFFE63946),
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

Widget _statusBadge(String status) {
  final color = _statusColors[status] ?? const Color(0xFF9CA3AF);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      status,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
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
  final _imagePicker = ImagePicker();

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
    final salaryC = TextEditingController(
        text: employee?.baseSalary != null ? '${employee!.baseSalary}' : '');
    String role = employee?.role ?? _roles.first;
    String status = employee?.status ?? 'Aktif';
    DateTime? startDate = employee?.startDate;
    String? photoPath = employee?.photoPath;
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
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Photo picker
                GestureDetector(
                  onTap: () async {
                    final picked = await _imagePicker.pickImage(
                        source: ImageSource.gallery, maxWidth: 512, maxHeight: 512);
                    if (picked != null) {
                      setSt(() => photoPath = picked.path);
                    }
                  },
                  child: Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _avatarColor(nameC.text.isNotEmpty ? nameC.text : '?'),
                      image: photoPath != null && photoPath!.isNotEmpty
                          ? DecorationImage(
                              image: FileImage(File(photoPath!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: photoPath == null || photoPath!.isEmpty
                        ? Text(
                            nameC.text.isNotEmpty ? nameC.text[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await _imagePicker.pickImage(
                        source: ImageSource.gallery, maxWidth: 512, maxHeight: 512);
                    if (picked != null) {
                      setSt(() => photoPath = picked.path);
                    }
                  },
                  icon: Icon(Icons.camera_alt_outlined, size: 16,
                      color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                  label: Text(photoPath != null ? 'Ganti Foto' : 'Tambah Foto',
                      style: TextStyle(fontSize: 12,
                          color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                ),
                const SizedBox(height: 12),
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
                // Role dropdown
                _buildDialogDropdown(
                  label: 'Role',
                  value: _roles.contains(role) ? role : _roles.first,
                  items: _roles,
                  isDark: isDark,
                  onChanged: (v) => setSt(() => role = v!),
                ),
                const SizedBox(height: 12),
                // Status dropdown
                _buildDialogDropdown(
                  label: 'Status',
                  value: status,
                  items: _statusOptions,
                  isDark: isDark,
                  colorFn: (s) => _statusColors[s] ?? Colors.grey,
                  onChanged: (v) => setSt(() => status = v!),
                ),
                const SizedBox(height: 12),
                NusaInput('Gaji Pokok (opsional)',
                    controller: salaryC,
                    type: TextInputType.number,
                    hint: 'Cth: 2500000'),
                const SizedBox(height: 12),
                // Start date picker
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: startDate ?? DateTime.now(),
                      firstDate: DateTime(2015),
                      lastDate: DateTime.now(),
                      helpText: 'Tanggal Mulai Kerja',
                      cancelText: 'BATAL',
                      confirmText: 'PILIH',
                    );
                    if (picked != null) setSt(() => startDate = picked);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder,
                      ),
                    ),
                    child: Row(children: [
                      Icon(Icons.calendar_today_rounded, size: 18,
                          color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          startDate != null
                              ? DateFormat('dd MMM yyyy', 'id').format(startDate!)
                              : 'Tanggal Mulai Kerja (opsional)',
                          style: TextStyle(
                            fontSize: 15,
                            color: startDate != null
                                ? (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)
                                : (isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                          ),
                        ),
                      ),
                      if (startDate != null)
                        GestureDetector(
                          onTap: () => setSt(() => startDate = null),
                          child: Icon(Icons.close, size: 18,
                              color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                        ),
                    ]),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: NusaConfig.primaryColor, fontSize: 13)),
                ],
              ],
            ),
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
                final salary = int.tryParse(salaryC.text.trim());
                final repo = AttendanceRepository(ref.read(databaseProvider));
                if (employee == null) {
                  await repo.addEmployee(
                      name: name, pin: pin, role: role,
                      phone: phone.isNotEmpty ? phone : null,
                      photoPath: photoPath,
                      baseSalary: salary,
                      startDate: startDate,
                      status: status);
                } else {
                  await repo.updateEmployee(
                      id: employee.id, name: name, pin: pin, role: role,
                      phone: phone.isNotEmpty ? phone : null,
                      photoPath: photoPath,
                      baseSalary: salary,
                      startDate: startDate,
                      status: status);
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

  Widget _buildDialogDropdown({
    required String label,
    required String value,
    required List<String> items,
    required bool isDark,
    Color? Function(String)? colorFn,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              isExpanded: true,
              icon: Icon(Icons.expand_more, size: 20,
                  color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
                  color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
              dropdownColor: isDark ? NusaConfig.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(14),
              underline: const SizedBox.shrink(),
              items: items.map((r) {
                final c = colorFn?.call(r);
                return DropdownMenuItem(
                  value: r,
                  child: Row(children: [
                    if (c != null) ...[
                      Container(width: 10, height: 10,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                    ],
                    Text(r),
                  ]),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
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

  String _fmtDate(DateTime? d) {
    if (d == null) return '';
    return DateFormat('dd MMM yyyy', 'id').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final employees = _filtered;

    return ScreenScaffold(
      'Karyawan',
      Column(
        children: [
          // Search bar — placeholder style
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
                borderRadius: BorderRadius.circular(NusaConfig.radiusXL),
                border: Border.all(
                  color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder,
                ),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: TextStyle(fontSize: 15,
                    color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Cari karyawan...',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary,
                  ),
                  prefixIcon: Icon(Icons.search_rounded, size: 22,
                      color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                  suffixIcon: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.clear_rounded, size: 20,
                                color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
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
                            final hasPhoto = e.photoPath != null && e.photoPath!.isNotEmpty;
                            final statusColor = _statusColors[e.status ?? 'Aktif'] ?? NusaConfig.accentGreen;
                            return NusaCard(
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        // Photo / Avatar
                                        Container(
                                          width: 52, height: 52,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _avatarColor(e.name),
                                            image: hasPhoto
                                                ? DecorationImage(
                                                    image: FileImage(File(e.photoPath!)),
                                                    fit: BoxFit.cover,
                                                  )
                                                : null,
                                            border: Border.all(
                                              color: statusColor,
                                              width: 2,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: hasPhoto
                                              ? null
                                              : Text(
                                                  e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
                                                  style: const TextStyle(
                                                    fontSize: 22,
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
                                                  fontWeight: FontWeight.w700,
                                                  color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(children: [
                                                _roleBadge(e.role),
                                                if (e.status != null && e.status != 'Aktif') ...[
                                                  const SizedBox(width: 6),
                                                  _statusBadge(e.status!),
                                                ],
                                              ]),
                                              if (e.startDate != null) ...[
                                                const SizedBox(height: 4),
                                                Row(children: [
                                                  Icon(Icons.calendar_today, size: 13,
                                                      color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                                                  const SizedBox(width: 4),
                                                  Text('Mulai: ${_fmtDate(e.startDate)}',
                                                      style: TextStyle(fontSize: 12,
                                                          color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
                                                ]),
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
                                    // Bottom row: salary + WA
                                    if (e.baseSalary != null || (e.phone != null && e.phone!.isNotEmpty)) ...[
                                      const SizedBox(height: 10),
                                      const Divider(height: 1),
                                      const SizedBox(height: 8),
                                      Row(children: [
                                        if (e.baseSalary != null) ...[
                                          Icon(Icons.payments_outlined, size: 14,
                                              color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                                          const SizedBox(width: 4),
                                          Text('Gaji: ${formatRupiah(e.baseSalary!)}',
                                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                                  color: NusaConfig.accentGreenDark)),
                                        ],
                                        if (e.baseSalary != null &&
                                            e.phone != null && e.phone!.isNotEmpty)
                                          const Spacer(),
                                        if (e.phone != null && e.phone!.isNotEmpty)
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
                                                      fontSize: 13,
                                                      color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                                                    )),
                                              ],
                                            ),
                                          ),
                                      ]),
                                    ],
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
