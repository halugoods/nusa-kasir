import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/attendance_repository.dart';
import 'package:nusa_kasir/features/auth/employee_session_provider.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
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

  // ── Bottom sheet: Absen Masuk / Pulang ──────────────────────────

  void _showAbsenSheet(Employee e, {required bool isCheckIn}) {
    final pinCtrl = TextEditingController();
    final cashCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = isCheckIn ? 'Absen Masuk' : 'Absen Pulang';
    final cashLabel = isCheckIn ? 'Kas Awal' : 'Kas Akhir';
    final iconData = isCheckIn ? Icons.login_rounded : Icons.logout_rounded;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          decoration: BoxDecoration(
            color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? NusaConfig.darkDivider : NusaConfig.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Employee header
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: _avatarCol(e.name).withValues(alpha: 0.15),
                    image: e.photoPath != null && e.photoPath!.isNotEmpty
                        ? DecorationImage(
                            image: FileImage(File(e.photoPath!)),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: (e.photoPath == null || e.photoPath!.isEmpty)
                      ? Text(e.name[0].toUpperCase(),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _avatarCol(e.name)))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.name,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                            color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
                    Text(e.role,
                        style: TextStyle(fontSize: 13,
                            color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                  ]),
                ),
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: (isCheckIn ? NusaConfig.accentGreen : const Color(0xFFEF4444)).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(iconData, size: 20,
                      color: isCheckIn ? NusaConfig.accentGreen : const Color(0xFFEF4444)),
                ),
              ]),
              const SizedBox(height: 18),
              // PIN input
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                style: TextStyle(fontSize: 15,
                    color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
                decoration: InputDecoration(
                  labelText: 'PIN',
                  labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                  hintText: 'Masukkan PIN 4-6 digit',
                  hintStyle: TextStyle(fontSize: 15,
                      color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 1.5)),
                  filled: true,
                  fillColor: isDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
                ),
              ),
              const SizedBox(height: 12),
              // Cash input
              TextField(
                controller: cashCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(fontSize: 15,
                    color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
                decoration: InputDecoration(
                  labelText: cashLabel,
                  labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                  hintText: 'Masukkan nominal $cashLabel (wajib)',
                  hintStyle: TextStyle(fontSize: 15,
                      color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 1.5)),
                  filled: true,
                  fillColor: isDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
                ),
              ),
              const SizedBox(height: 20),
              // Action buttons
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder),
                    ),
                    child: Text('Batal',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                            color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final pin = pinCtrl.text.trim();
                      if (pin != e.pin) {
                        TopToast.error(context, 'PIN salah');
                        return;
                      }
                      final amount = int.tryParse(cashCtrl.text.trim());
                      if (amount == null || amount <= 0) {
                        TopToast.error(context, '$cashLabel wajib diisi');
                        return;
                      }
                      Navigator.pop(ctx);
                      final repo = AttendanceRepository(ref.read(databaseProvider));
                      if (isCheckIn) {
                        await repo.checkInWithCash(e.id, amount);
                        if (mounted) TopToast.success(context, '${e.name} absen masuk');
                      } else {
                        await repo.checkOutWithCash(e.id, amount);
                        if (mounted) TopToast.success(context, '${e.name} absen pulang');
                      }
                      _load();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCheckIn ? NusaConfig.accentGreen : const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    ).then((_) {
      pinCtrl.dispose();
      cashCtrl.dispose();
    });
  }

  // ── Bottom sheet: Izin ──────────────────────────────────────────

  void _showIzinSheet(Employee e) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: isDark ? NusaConfig.darkDivider : NusaConfig.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.event_busy_rounded, size: 28, color: Color(0xFF3B82F6)),
            ),
            const SizedBox(height: 14),
            Text('Tandai Izin',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
            const SizedBox(height: 4),
            Text('${e.name} akan ditandai izin hari ini.',
                style: TextStyle(fontSize: 14,
                    color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder),
                  ),
                  child: Text('Batal',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                          color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final repo = AttendanceRepository(ref.read(databaseProvider));
                    await repo.markTodayStatus(e.id, 'Izin');
                    if (mounted) TopToast.success(context, '${e.name} ditandai Izin');
                    _load();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Konfirmasi',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _sendWAReminder(Employee e) async {
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
        // Tab switch (1 card) + dropdown filter in one row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            // Segmented toggle: Hari Ini / Riwayat in 1 card
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
                  _segBtn('Hari Ini', 0, isDark: isDark),
                  _segBtn('Riwayat', 1, isDark: isDark),
                ]),
              ),
            ),
            if (_tab == 0) ...[
              const SizedBox(width: 8),
              _roleDropdown(isDark),
            ],
          ]),
        ),
        const SizedBox(height: 6),
        Expanded(child: _tab == 0 ? _todayTab(isDark, isOwner) : _historyTab(isDark)),
      ]),
    );
  }

  Widget _segBtn(String label, int idx, {bool isDark = false}) {
    final sel = idx == _tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _tab = idx;
          if (idx == 1) _loadHistory();
        }),
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
      // Search bar — placeholder style, not NusaInput
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
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
              hintText: 'Cari nama karyawan...',
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
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
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
      final parts = inTime.split(':');
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
            // Avatar — bigger, supports photo
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: _avatarCol(e.name).withValues(alpha: 0.15),
                image: e.photoPath != null && e.photoPath!.isNotEmpty
                    ? DecorationImage(
                        image: FileImage(File(e.photoPath!)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              alignment: Alignment.center,
              child: (e.photoPath == null || e.photoPath!.isEmpty)
                  ? Text(e.name[0].toUpperCase(),
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _avatarCol(e.name)))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(e.name,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                          color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary))),
                  // Status badge — more prominent
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(statusLabel,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor)),
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
                    child: Text(e.role, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: NusaConfig.primaryColor)),
                  ),
                  if (hasPhone) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.phone_android, size: 12, color: const Color(0xFF25D366).withValues(alpha: 0.7)),
                    const SizedBox(width: 2),
                    Text(e.phone!, style: TextStyle(fontSize: 11, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
                  ],
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          // Time info — bigger fonts
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
              child: _actionBtn(Icons.login_rounded, 'Absen Masuk', NusaConfig.accentGreen,
                  enabled: !isCheckedIn && !isIzin, onTap: () => _showAbsenSheet(e, isCheckIn: true)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _actionBtn(Icons.logout_rounded, 'Absen Pulang', const Color(0xFFEF4444),
                  enabled: isCheckedIn && !isCheckedOut && !isIzin, onTap: () => _showAbsenSheet(e, isCheckIn: false)),
            ),
            if (isOwner && !isCheckedIn && !isIzin) ...[
              const SizedBox(width: 4),
              _iconBtn(Icons.event_busy_rounded, 'Izin', () => _showIzinSheet(e)),
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
    int totalHadir = 0, totalTerlambat = 0, totalIzin = 0, totalAlpha = 0;
    for (final v in _monthlySummary.values) {
      totalHadir += (v['hadir'] as int?) ?? 0;
      totalTerlambat += (v['terlambat'] as int?) ?? 0;
      totalIzin += (v['izin'] as int?) ?? 0;
      totalAlpha += (v['alpha'] as int?) ?? 0;
    }

    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // Month picker — card style
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: surf,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Map<String, int>>(
                value: monthOptions.firstWhere(
                  (o) => o['year'] == _histYear && o['month'] == _histMonth,
                  orElse: () => monthOptions.first,
                ),
                isExpanded: true,
                isDense: true,
                icon: Icon(Icons.expand_more_rounded, size: 18, color: textTer),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSec),
                dropdownColor: isDark ? NusaConfig.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(12),
                underline: const SizedBox.shrink(),
                items: monthOptions.map((o) => DropdownMenuItem(
                  value: o,
                  child: Text('${monthNames[o['month']!]} ${o['year']}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPri)),
                )).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() { _histYear = v['year']!; _histMonth = v['month']!; });
                  _loadHistory();
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Overall summary chips — 4 chips only
          if (_monthlySummary.isNotEmpty) ...[
            Wrap(spacing: 6, runSpacing: 6, children: [
              _sumChip('$totalHadir Hadir', NusaConfig.accentGreen),
              _sumChip('$totalTerlambat Terlambat', NusaConfig.accentGold),
              _sumChip('$totalIzin Izin', const Color(0xFF3B82F6)),
              _sumChip('$totalAlpha Alpha', NusaConfig.primaryColor),
            ]),
            const SizedBox(height: 16),
          ],

          // Employee list with calendar-style attendance
          if (_historyGrouped.isEmpty)
            const EmptyState(icon: Icons.no_accounts_outlined, message: 'Belum ada data presensi bulan ini'),

          ..._historyGrouped.entries.map((entry) {
            final empName = entry.key;
            final atts = entry.value;
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

            // Build day-by-day map for this employee
            final dayStatus = <int, String>{};
            for (final a in atts) {
              if (a.status == 'Izin' || a.status == 'Sakit') {
                dayStatus[a.date.day] = 'izin';
              } else if (a.checkOut != null) {
                dayStatus[a.date.day] = 'hadir';
              } else if (a.checkIn != null) {
                // Check terlambat
                final parts = a.checkIn!.split(':');
                final h = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
                final m = parts.length >= 2 ? (int.tryParse(parts[1]) ?? 0) : 0;
                if (h > 8 || (h == 8 && m > 15)) {
                  dayStatus[a.date.day] = 'terlambat';
                } else {
                  dayStatus[a.date.day] = 'hadir';
                }
              }
            }

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
                      image: emp?.photoPath != null && emp!.photoPath!.isNotEmpty
                          ? DecorationImage(
                              image: FileImage(File(emp.photoPath!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: (emp == null || emp.photoPath == null || emp.photoPath!.isEmpty)
                        ? Text(empName[0].toUpperCase(),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _avatarCol(empName)))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(empName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPri)),
                      if (empRole.isNotEmpty)
                        Text(empRole, style: TextStyle(fontSize: 11, color: textTer)),
                    ]),
                  ),
                  // Ratio text
                  Text('${(ratio * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                          color: ratio >= 0.8 ? NusaConfig.accentGreen : ratio >= 0.5 ? NusaConfig.accentGold : NusaConfig.primaryColor)),
                  if (empPhone != null && empPhone.isNotEmpty) ...[
                    const SizedBox(width: 6),
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
                        child: const Text('WA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF25D366))),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 10),

                // Linear progress bar
                Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: ratio.clamp(0.0, 1.0),
                        backgroundColor: NusaConfig.primaryColor.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation(
                            ratio >= 0.8 ? NusaConfig.accentGreen : ratio >= 0.5 ? NusaConfig.accentGold : NusaConfig.primaryColor),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('$hadir H / $terlambat T / $izin I / $alpha A',
                      style: TextStyle(fontSize: 11, color: textSec)),
                ]),

                // Mini calendar grid — current month
                if (atts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  // Day-of-week headers
                  Row(
                    children: ['Sn', 'Sl', 'Rb', 'Km', 'Jm', 'Sb', 'Mn'].map((d) => Expanded(
                      child: Center(child: Text(d, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textTer))),
                    )).toList(),
                  ),
                  const SizedBox(height: 4),
                  // Calendar grid
                  ..._buildCalendarGrid(_histYear, _histMonth, dayStatus, isDark),
                ],
              ]),
            );
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  List<Widget> _buildCalendarGrid(int year, int month, Map<int, String> dayStatus, bool isDark) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday; // 1=Mon, 7=Sun
    final textSec = isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary;
    final textTer = isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary;

    final rows = <TableRow>[];
    var cells = <Widget>[];
    // Leading empty cells
    for (var i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    // Day cells
    for (var d = 1; d <= daysInMonth; d++) {
      final status = dayStatus[d];
      final dot = status != null ? _attDot(status) : null;
      final isToday = year == DateTime.now().year && month == DateTime.now().month && d == DateTime.now().day;

      cells.add(Container(
        padding: const EdgeInsets.all(3),
        decoration: isToday
            ? BoxDecoration(
                color: NusaConfig.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$d', style: TextStyle(fontSize: 11, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              color: isToday ? NusaConfig.primaryColor : (status != null ? textSec : textTer))),
          ?dot,
        ]),
      ));

      if (cells.length == 7) {
        rows.add(TableRow(children: cells));
        cells = [];
      }
    }
    // Pad last row
    if (cells.isNotEmpty) {
      while (cells.length < 7) {
        cells.add(const SizedBox.shrink());
      }
      rows.add(TableRow(children: cells));
    }
    rows.insert(0, const TableRow(children: [SizedBox(height: 2)]));

    return [
      Table(
        columnWidths: const {
          0: FlexColumnWidth(1), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1),
          3: FlexColumnWidth(1), 4: FlexColumnWidth(1), 5: FlexColumnWidth(1), 6: FlexColumnWidth(1),
        },
        children: rows,
      ),
    ];
  }

  Widget _attDot(String status) {
    Color c;
    switch (status) {
      case 'hadir': c = NusaConfig.accentGreen; break;
      case 'terlambat': c = NusaConfig.accentGold; break;
      case 'izin': c = const Color(0xFF3B82F6); break;
      default: c = NusaConfig.primaryColor;
    }
    return Container(
      width: 5, height: 5,
      margin: const EdgeInsets.only(top: 1),
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }

  // ── Helper Widgets ──────────────────────────────────────────────────

  Widget _roleDropdown(bool isDark) {
    return Container(
      height: 36,
      constraints: const BoxConstraints(maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface : NusaConfig.backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _roleOptions.contains(_roleFilter) ? _roleFilter : 'Semua',
          isDense: true,
          icon: Icon(Icons.expand_more_rounded, size: 18,
              color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
          dropdownColor: isDark ? NusaConfig.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(12),
          underline: const SizedBox.shrink(),
          items: _roleOptions.map((r) => DropdownMenuItem(
            value: r,
            child: Text(r, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
          )).toList(),
          onChanged: (v) => setState(() => _roleFilter = v ?? 'Semua'),
        ),
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
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
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
      Icon(icon, size: 14, color: color ?? (isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
      const SizedBox(width: 4),
      Text(value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: color ?? (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary))),
    ]);
  }

  Widget _actionBtn(IconData icon, String label, Color color, {required bool enabled, required VoidCallback onTap}) {
    return SizedBox(
      height: 36,
      child: ElevatedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withValues(alpha: 0.25),
          disabledForegroundColor: Colors.white54,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          minimumSize: Size.zero,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: NusaConfig.primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: NusaConfig.primaryColor),
        ),
      ),
    );
  }
}
