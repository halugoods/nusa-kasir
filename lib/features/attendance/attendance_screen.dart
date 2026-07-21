import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/attendance_repository.dart';
import 'package:nusa_kasir/features/auth/employee_session_provider.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/pin_dialog.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:url_launcher/url_launcher.dart';

const _avatarColors2 = [
  Color(0xFFE63946), Color(0xFF3B82F6), Color(0xFF10B981),
  Color(0xFF8B5CF6), Color(0xFFF59E0B), Color(0xFFEC4899),
];
Color _avatarCol(String name) => _avatarColors2[name.runes.fold(0, (a, b) => a + b) % _avatarColors2.length];

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  int _tab = 0; // 0 = Hari Ini, 1 = Riwayat
  List<Employee> _employees = [];
  Map<int, AttendanceData?> _today = {};
  Map<String, int> _summary = {};
  bool _loading = true;

  // Filter
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _roleFilter = 'Semua';

  // History
  int _histYear = DateTime.now().year;
  int _histMonth = DateTime.now().month;
  Map<int, Map<String, dynamic>> _monthlySummary = {};
  Map<String, List<AttendanceData>> _historyGrouped = {};
  bool _histLoading = false;

  final _roleOptions = ['Semua', 'Owner', 'Manager', 'Kasir', 'Gudang', 'Finance'];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.toLowerCase()));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Employee> get _filtered {
    var list = _employees;
    if (_query.isNotEmpty) {
      list = list.where((e) => e.name.toLowerCase().contains(_query)).toList();
    }
    if (_roleFilter != 'Semua') {
      list = list.where((e) => e.role == _roleFilter).toList();
    }
    return list;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = AttendanceRepository(ref.read(databaseProvider));
    final emps = await repo.getEmployees();
    final todayMap = <int, AttendanceData?>{};
    for (final e in emps) {
      todayMap[e.id] = await repo.getToday(e.id);
    }
    final sum = await repo.getTodaySummary();
    if (mounted) {
      setState(() {
        _employees = emps;
        _today = todayMap;
        _summary = sum;
        _loading = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _histLoading = true);
    final repo = AttendanceRepository(ref.read(databaseProvider));
    final ms = await repo.getMonthlySummary(year: _histYear, month: _histMonth);
    final hg = await repo.getHistoryGrouped(year: _histYear, month: _histMonth);
    if (mounted) {
      setState(() {
        _monthlySummary = ms;
        _historyGrouped = hg;
        _histLoading = false;
      });
    }
  }

  Future<void> _checkIn(Employee e) async {
    final result = await PinDialog.show(
      context: context,
      employeeName: e.name,
      employeeRole: e.role,
      correctPin: e.pin,
    );
    if (result == null || !result.success) return;
    final cash = await _showCashInput('Kas Awal', 'Masukkan nominal kas awal (wajib)');
    if (cash == null || !mounted) return;
    final repo = AttendanceRepository(ref.read(databaseProvider));
    await repo.checkInWithCash(e.id, cash);
    TopToast.success(context, '${e.name} absen masuk');
    _load();
  }

  Future<void> _checkOut(Employee e) async {
    final result = await PinDialog.show(
      context: context,
      employeeName: e.name,
      employeeRole: e.role,
      correctPin: e.pin,
    );
    if (result == null || !result.success) return;
    final cash = await _showCashInput('Kas Akhir', 'Masukkan nominal kas akhir (wajib)');
    if (cash == null || !mounted) return;
    final repo = AttendanceRepository(ref.read(databaseProvider));
    await repo.checkOutWithCash(e.id, cash);
    TopToast.success(context, '${e.name} absen pulang');
    _load();
  }

  Future<void> _markIzin(Employee e) async {
    final repo = AttendanceRepository(ref.read(databaseProvider));
    await repo.markTodayStatus(e.id, 'Izin');
    TopToast.success(context, '${e.name} ditandai Izin');
    _load();
  }

  Future<void> _sendWAReminder(Employee e) async {
    if (e.phone == null || e.phone!.isEmpty) return;
    final phone = e.phone!.replaceAll(RegExp(r'[^0-9]'), '');
    var num = phone;
    if (num.startsWith('0')) num = '62${num.substring(1)}';
    final msg = Uri.encodeComponent(
      'Halo ${e.name}, ini dari NUSA Kasir.\n\n'
      'Kamu belum absen masuk hari ini. Mohon segera absen ya.\n\nTerima kasih 🙏'
    );
    final uri = Uri.parse('https://wa.me/$num?text=$msg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<int?> _showCashInput(String title, String hint) async {
    final ctrl = TextEditingController();
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        content: NusaInput(hint, controller: ctrl, type: TextInputType.number),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              final amount = int.tryParse(ctrl.text.trim());
              if (amount == null || amount <= 0) {
                TopToast.error(context, '$title wajib diisi');
                return;
              }
              Navigator.pop(ctx, amount);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: NusaConfig.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final session = ref.watch(employeeSessionProvider);
    final isOwner = session?.role == 'Owner' || session?.role == 'Manager';

    return ScreenScaffold(
      'Presensi',
      Column(children: [
        const SizedBox(height: 6),
        // Tab switch + filter row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _tabChip('Hari Ini', 0, isDark: isDark),
            const SizedBox(width: 8),
            _tabChip('Riwayat', 1, isDark: isDark),
            const Spacer(),
            if (_tab == 0) _roleDropdown(isDark),
          ]),
        ),
        const SizedBox(height: 6),
        Expanded(child: _tab == 0 ? _todayTab(isDark, isOwner) : _historyTab(isDark)),
      ]),
    );
  }

  // ── TAB: Hari Ini ─────────────────────────────────────────────────

  Widget _todayTab(bool isDark, bool isOwner) {
    return Column(children: [
      // Summary cards
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: SizedBox(
          height: 64,
          child: Row(children: [
            Expanded(child: _sumCard('Hadir', '${_summary['hadir'] ?? 0}', NusaConfig.accentGreen, isDark)),
            const SizedBox(width: 6),
            Expanded(child: _sumCard('Terlambat', '${_summary['terlambat'] ?? 0}', NusaConfig.accentGold, isDark)),
            const SizedBox(width: 6),
            Expanded(child: _sumCard('Izin', '${_summary['izin'] ?? 0}', const Color(0xFF3B82F6), isDark)),
            const SizedBox(width: 6),
            Expanded(child: _sumCard('Belum', '${_summary['belum'] ?? 0}', NusaConfig.primaryColor, isDark)),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      // Search bar
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: NusaInput(
          'Cari nama karyawan...',
          controller: _searchCtrl,
          prefixIcon: Icon(Icons.search, size: 20,
              color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
        ),
      ),
      const SizedBox(height: 8),
      // Employee list
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _filtered.isEmpty
                ? const EmptyState(icon: Icons.person_off_outlined, message: 'Tidak ada karyawan')
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _employeeCard(_filtered[i], isDark, isOwner),
                    ),
                  ),
      ),
    ]);
  }

  Widget _employeeCard(Employee e, bool isDark, bool isOwner) {
    final att = _today[e.id];
    final inTime = att?.checkIn;
    final outTime = att?.checkOut;
    final pettyCash = att?.pettyCash;
    final finalCash = att?.finalCash;
    final isCheckedIn = inTime != null;
    final isCheckedOut = outTime != null;
    final isIzin = att?.status == 'Izin' || att?.status == 'Sakit';
    final hasPhone = e.phone != null && e.phone!.isNotEmpty;

    Color statusColor;
    String statusLabel;
    if (isIzin) {
      statusColor = const Color(0xFF3B82F6);
      statusLabel = 'Izin';
    } else if (isCheckedOut) {
      statusColor = const Color(0xFF9CA3AF);
      statusLabel = 'Selesai';
    } else if (isCheckedIn) {
      // Check terlambat
      final parts = inTime!.split(':');
      final h = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
      final m = parts.length >= 2 ? (int.tryParse(parts[1]) ?? 0) : 0;
      if (h > 8 || (h == 8 && m > 15)) {
        statusColor = NusaConfig.accentGold;
        statusLabel = 'Terlambat';
      } else {
        statusColor = NusaConfig.accentGreen;
        statusLabel = 'Aktif';
      }
    } else {
      statusColor = NusaConfig.primaryColor;
      statusLabel = 'Belum absen';
    }

    return NusaCard(
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Avatar
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: _avatarCol(e.name).withValues(alpha: 0.15),
              ),
              alignment: Alignment.center,
              child: Text(e.name[0].toUpperCase(),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _avatarCol(e.name))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(e.name,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                          color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary))),
                  // Status dot + label
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(statusLabel,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                  ),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(
                      color: NusaConfig.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(e.role, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: NusaConfig.primaryColor)),
                  ),
                  if (hasPhone) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.phone_android, size: 12, color: const Color(0xFF25D366).withValues(alpha: 0.7)),
                    const SizedBox(width: 2),
                    Text(e.phone!, style: TextStyle(fontSize: 10, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
                  ],
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          // Time info
          Wrap(spacing: 10, runSpacing: 6, children: [
            _infoBadge(Icons.login_rounded, 'Masuk', inTime ?? '-',
                color: inTime != null ? NusaConfig.accentGreen : null, isDark: isDark),
            _infoBadge(Icons.logout_rounded, 'Pulang', outTime ?? '-',
                color: outTime != null ? NusaConfig.accentGreen : null, isDark: isDark),
            _infoBadge(Icons.account_balance_wallet_outlined, 'Kas Awal', pettyCash != null ? formatRupiah(pettyCash) : '-',
                isDark: isDark),
            _infoBadge(Icons.monetization_on_outlined, 'Kas Akhir', finalCash != null ? formatRupiah(finalCash) : '-',
                isDark: isDark),
          ]),
          const SizedBox(height: 10),
          // Action buttons
          Row(children: [
            Expanded(
              child: _actionBtn('Absen Masuk', NusaConfig.accentGreen,
                  enabled: !isCheckedIn && !isIzin, onTap: () => _checkIn(e)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _actionBtn('Absen Pulang', const Color(0xFFEF4444),
                  enabled: isCheckedIn && !isCheckedOut && !isIzin, onTap: () => _checkOut(e)),
            ),
            if (isOwner && !isCheckedIn && !isIzin) ...[
              const SizedBox(width: 4),
              _iconBtn(Icons.event_busy_rounded, 'Izin', () => _markIzin(e)),
            ],
            if (isOwner && hasPhone && !isCheckedIn && !isIzin) ...[
              const SizedBox(width: 4),
              _iconBtn(Icons.notifications_active, 'WA', () => _sendWAReminder(e)),
            ],
          ]),
        ]),
      ),
    );
  }

  // ── TAB: Riwayat ─────────────────────────────────────────────────

  Widget _historyTab(bool isDark) {
    final textPri = isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary;
    final textSec = isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary;
    final textTer = isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary;
    final surf = isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor;
    final border = isDark ? NusaConfig.darkBorder : NusaConfig.borderColor;

    if (_histLoading) return const Center(child: CircularProgressIndicator());

    // Build month options
    final now = DateTime.now();
    final monthOptions = <Map<String, int>>[];
    for (var y = now.year; y >= now.year - 2; y--) {
      final endM = y == now.year ? now.month : 12;
      for (var m = endM; m >= 1; m--) {
        monthOptions.add({'year': y, 'month': m});
      }
    }

    // Calculate overall sums
    int totalHadir = 0, totalTerlambat = 0, totalIzin = 0, totalAlpha = 0, totalJam = 0, totalMenit = 0;
    for (final v in _monthlySummary.values) {
      totalHadir += (v['hadir'] as int?) ?? 0;
      totalTerlambat += (v['terlambat'] as int?) ?? 0;
      totalIzin += (v['izin'] as int?) ?? 0;
      totalAlpha += (v['alpha'] as int?) ?? 0;
      totalJam += (v['totalJam'] as int?) ?? 0;
      totalMenit += (v['totalMenit'] as int?) ?? 0;
    }
    totalJam += totalMenit ~/ 60;
    totalMenit = totalMenit % 60;

    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // Month picker
          Row(children: [
            Icon(Icons.calendar_month_outlined, size: 18, color: textSec),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Map<String, int>>(
                  value: monthOptions.firstWhere(
                    (o) => o['year'] == _histYear && o['month'] == _histMonth,
                    orElse: () => monthOptions.first,
                  ),
                  isExpanded: true,
                  isDense: true,
                  icon: Icon(Icons.expand_more, size: 20, color: textSec),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPri),
                  dropdownColor: isDark ? NusaConfig.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  underline: const SizedBox.shrink(),
                  items: monthOptions.map((o) => DropdownMenuItem(
                    value: o,
                    child: Text('${monthNames[o['month']!]} ${o['year']}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPri)),
                  )).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() { _histYear = v['year']!; _histMonth = v['month']!; });
                    _loadHistory();
                  },
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // Overall summary cards
          if (_monthlySummary.isNotEmpty) ...[
            Wrap(spacing: 6, runSpacing: 6, children: [
              _sumChip('$totalHadir Hadir', NusaConfig.accentGreen),
              _sumChip('$totalTerlambat Terlambat', NusaConfig.accentGold),
              _sumChip('$totalIzin Izin', const Color(0xFF3B82F6)),
              _sumChip('$totalAlpha Alpha', NusaConfig.primaryColor),
              _sumChip('${totalJam}h ${totalMenit}m Kerja', const Color(0xFF8B5CF6)),
            ]),
            const SizedBox(height: 16),
          ],

          // Employee list with progress
          if (_historyGrouped.isEmpty)
            const EmptyState(icon: Icons.no_accounts_outlined, message: 'Belum ada data presensi bulan ini'),

          ..._historyGrouped.entries.map((entry) {
            final empName = entry.key;
            final atts = entry.value;
            // Find employee data
            final emp = _employees.cast<Employee?>().firstWhere((e) => e!.name == empName, orElse: () => null);
            final ms = emp != null ? (_monthlySummary[emp.id] ?? {}) : <String, dynamic>{};
            final hadir = (ms['hadir'] as int?) ?? 0;
            final terlambat = (ms['terlambat'] as int?) ?? 0;
            final izin = (ms['izin'] as int?) ?? 0;
            final alpha = (ms['alpha'] as int?) ?? 0;
            final totalHari = hadir + terlambat + izin + alpha;
            final ratio = totalHari > 0 ? (hadir + terlambat) / totalHari : 0.0;
            final empRole = emp?.role ?? '';
            final empPhone = emp?.phone;

            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surf,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Employee header
                Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: _avatarCol(empName).withValues(alpha: 0.15),
                    ),
                    alignment: Alignment.center,
                    child: Text(empName[0].toUpperCase(),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _avatarCol(empName))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(empName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPri)),
                      if (empRole.isNotEmpty)
                        Text(empRole, style: TextStyle(fontSize: 11, color: textTer)),
                    ]),
                  ),
                  if (empPhone != null && empPhone.isNotEmpty)
                    GestureDetector(
                      onTap: () async {
                        final clean = empPhone.replaceAll(RegExp(r'[^0-9]'), '');
                        var num = clean;
                        if (num.startsWith('0')) num = '62${num.substring(1)}';
                        final uri = Uri.parse('https://wa.me/$num');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('WA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF25D366))),
                      ),
                    ),
                ]),
                const SizedBox(height: 10),

                // Progress bar
                Row(children: [
                  SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(
                      value: ratio.clamp(0.0, 1.0),
                      strokeWidth: 2,
                      backgroundColor: NusaConfig.primaryColor.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation(
                          ratio >= 0.8 ? NusaConfig.accentGreen : ratio >= 0.5 ? NusaConfig.accentGold : NusaConfig.primaryColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${(ratio * 100).toStringAsFixed(0)}% kehadiran ($hadir H / $terlambat T / $izin I / $alpha A)',
                      style: TextStyle(fontSize: 11, color: textSec)),
                ]),

                // Attendance list
                if (atts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  ...atts.map((a) {
                    final dateLabel = '${a.date.day}/${a.date.month}';
                    final inT = a.checkIn ?? '-';
                    final outT = a.checkOut ?? '-';
                    final isIzin = a.status == 'Izin' || a.status == 'Sakit';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        SizedBox(width: 48, child: Text(dateLabel, style: TextStyle(fontSize: 12, color: textSec))),
                        Icon(Icons.login, size: 12, color: a.checkIn != null ? NusaConfig.accentGreen : textTer),
                        const SizedBox(width: 4),
                        SizedBox(width: 40, child: Text(inT, style: TextStyle(fontSize: 11, color: textPri))),
                        const SizedBox(width: 6),
                        Icon(Icons.logout, size: 12, color: a.checkOut != null ? NusaConfig.accentGreen : textTer),
                        const SizedBox(width: 4),
                        SizedBox(width: 40, child: Text(outT, style: TextStyle(fontSize: 11, color: textPri))),
                        if (isIzin) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(a.status ?? 'Izin', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF3B82F6))),
                          ),
                        ],
                      ]),
                    );
                  }),
                ],
              ]),
            );
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ── Helper Widgets ──────────────────────────────────────────────────

  Widget _tabChip(String label, int idx, {bool isDark = false}) {
    final sel = idx == _tab;
    return FilterChip(
      label: Text(label),
      selected: sel,
      showCheckmark: false,
      selectedColor: NusaConfig.primaryColor,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: sel ? Colors.white : (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
      onSelected: (_) => setState(() {
        _tab = idx;
        if (idx == 1) _loadHistory();
      }),
    );
  }

  Widget _roleDropdown(bool isDark) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _roleOptions.contains(_roleFilter) ? _roleFilter : 'Semua',
        isDense: true,
        icon: Icon(Icons.filter_list, size: 18,
            color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
            color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
        dropdownColor: isDark ? NusaConfig.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        underline: const SizedBox.shrink(),
        items: _roleOptions.map((r) => DropdownMenuItem(
          value: r,
          child: Text(r, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
        )).toList(),
        onChanged: (v) => setState(() => _roleFilter = v ?? 'Semua'),
      ),
    );
  }

  Widget _sumCard(String label, String value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
            color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color, height: 1.1)),
      ]),
    );
  }

  Widget _sumChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _infoBadge(IconData icon, String label, String value, {Color? color, bool isDark = false}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color ?? (isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
      const SizedBox(width: 4),
      Text(value,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: color ?? (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary))),
    ]);
  }

  Widget _actionBtn(String label, Color color, {required bool enabled, required VoidCallback onTap}) {
    return SizedBox(
      height: 34,
      child: ElevatedButton(
        onPressed: enabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withValues(alpha: 0.25),
          disabledForegroundColor: Colors.white54,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          minimumSize: Size.zero,
        ),
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: NusaConfig.primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: NusaConfig.primaryColor),
        ),
      ),
    );
  }
}
