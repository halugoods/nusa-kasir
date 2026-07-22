import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/shift_repository.dart';
import 'package:nusa_kasir/features/auth/employee_session_provider.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';

class ShiftScreen extends ConsumerStatefulWidget {
  const ShiftScreen({super.key});
  @override
  ConsumerState<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends ConsumerState<ShiftScreen> {
  int _tab = 0; // 0 = Shift Aktif, 1 = Riwayat
  final _startingCashCtrl = TextEditingController();
  final _actualCashCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _loading = true;
  ShiftSession? _activeShift;
  List<ShiftSession> _history = [];
  int? _currentEmployeeId;
  String _runningTime = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _startingCashCtrl.dispose();
    _actualCashCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    try {
      final session = ref.read(employeeSessionProvider);
      if (session != null) {
        _currentEmployeeId = session.employeeId;
      }
      await _load();
    } catch (e) {
      if (mounted) {
        TopToast.error(context, 'Gagal memuat data shift: $e');
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _load() async {
    final repo = ShiftRepository(ref.read(databaseProvider));

    if (_currentEmployeeId != null) {
      _activeShift = await repo.getActiveShift(_currentEmployeeId!);
    }

    // Load history for the last 30 days
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    _history = await repo.getShiftsByDate(thirtyDaysAgo, now);

    // Start/stop running time timer
    _timer?.cancel();
    if (_activeShift != null) {
      _updateRunningTime();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          _updateRunningTime();
          setState(() {});
        }
      });
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _updateRunningTime() {
    if (_activeShift == null) return;
    final elapsed = DateTime.now().difference(_activeShift!.openedAt);
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    _runningTime = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _openShift() async {
    if (_currentEmployeeId == null) {
      if (mounted) TopToast.error(context, 'Anda harus login terlebih dahulu');
      return;
    }

    final startingCashText = _startingCashCtrl.text.trim();
    final startingCash = int.tryParse(startingCashText) ?? 0;

    try {
      final repo = ShiftRepository(ref.read(databaseProvider));
      await repo.openShift(
        employeeId: _currentEmployeeId!,
        startingCash: startingCash,
      );
      if (mounted) {
        TopToast.success(context, 'Shift dibuka! Selamat bekerja.');
        _startingCashCtrl.clear();
        await _load();
      }
    } catch (e) {
      if (mounted) {
        TopToast.error(context, 'Gagal membuka shift: $e');
      }
    }
  }

  Future<void> _closeShift() async {
    if (_activeShift == null) return;

    final actualCashText = _actualCashCtrl.text.trim();
    final actualCash = int.tryParse(actualCashText) ?? 0;
    if (actualCashText.isEmpty) {
      if (mounted) TopToast.error(context, 'Masukkan jumlah kas yang dihitung');
      return;
    }

    try {
      final repo = ShiftRepository(ref.read(databaseProvider));
      final notes = _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null;

      await repo.closeShift(
        shiftId: _activeShift!.id,
        actualCash: actualCash,
        notes: notes,
      );

      // Reload to get the updated shift with calculated values
      final closedShift = await (ref.read(databaseProvider).select(ref.read(databaseProvider).shiftSessions)
            ..where((t) => t.id.equals(_activeShift!.id)))
          .getSingle();

      if (mounted) {
        _actualCashCtrl.clear();
        _notesCtrl.clear();
        await _load();
        _showCloseResultDialog(closedShift);
      }
    } catch (e) {
      if (mounted) {
        TopToast.error(context, 'Gagal menutup shift: $e');
      }
    }
  }

  void _showCloseResultDialog(ShiftSession shift) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selisih = shift.difference;
    final selisihNegative = selisih < 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: NusaConfig.success, size: 28),
            SizedBox(width: 10),
            Text('Shift Ditutup', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _resultRow('Kas Awal', formatRupiah(shift.startingCash), isDark),
            const SizedBox(height: 8),
            _resultRow('Kas Diharapkan (Sistem)', formatRupiah(shift.expectedCash), isDark),
            const SizedBox(height: 8),
            _resultRow('Kas Aktual (Dihitung)', formatRupiah(shift.actualCash), isDark),
            const Divider(height: 20),
            _resultRow(
              'Selisih',
              formatRupiah(selisih),
              isDark,
              valueColor: selisihNegative ? NusaConfig.primaryColor : NusaConfig.success,
            ),
            if (shift.notes != null && shift.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Catatan: ${shift.notes}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: NusaConfig.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value, bool isDark, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor ?? (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
          ),
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScreenScaffold(
      'Shift & Kas',
      Column(
        children: [
          // Tab bar
          _buildTabBar(isDark),
          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tab == 0
                    ? _activeShift != null ? _buildActiveShift(isDark) : _buildOpenShift(isDark)
                    : _buildHistory(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface2 : NusaConfig.borderColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _tab == 0
                      ? (isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _tab == 0
                      ? [
                          BoxShadow(
                            color: isDark ? Colors.black26 : const Color(0x0A111827),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  'Shift',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _tab == 0
                        ? (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)
                        : (isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _tab == 1
                      ? (isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _tab == 1
                      ? [
                          BoxShadow(
                            color: isDark ? Colors.black26 : const Color(0x0A111827),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  'Riwayat',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _tab == 1
                        ? (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)
                        : (isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Open Shift Card ─────────────────────────────────────────────────

  Widget _buildOpenShift(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        NusaCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF14B8A6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.toggle_on_outlined, size: 26, color: Color(0xFF14B8A6)),
              ),
              const SizedBox(height: 12),
              Text(
                'Buka Shift',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Mulai shift kerja Anda dan catat kas awal.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Kas Awal (Rp)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _startingCashCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Masukkan jumlah kas awal',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF14B8A6), width: 2),
                  ),
                  filled: true,
                  fillColor: isDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF14B8A6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _openShift();
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_arrow_rounded, size: 22),
                      SizedBox(width: 8),
                      Text('Buka Shift',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Active Shift Card ────────────────────────────────────────────────

  Widget _buildActiveShift(bool isDark) {
    final shift = _activeShift!;
    final openedTime =
        '${shift.openedAt.hour.toString().padLeft(2, '0')}:${shift.openedAt.minute.toString().padLeft(2, '0')}';
    final openedDate =
        '${shift.openedAt.day}/${shift.openedAt.month}/${shift.openedAt.year}';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Active shift info card
        NusaCard(
          Column(
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: NusaConfig.accentGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: NusaConfig.accentGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shift Aktif',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                          ),
                        ),
                        Text(
                          'Sedang berjalan sejak $openedTime',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Stats row
              Row(
                children: [
                  Expanded(
                    child: _statBox('Mulai', '$openedDate, $openedTime', Icons.schedule_rounded,
                        NusaConfig.info, isDark),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statBox(
                      'Kas Awal',
                      formatRupiah(shift.startingCash),
                      Icons.wallet_outlined,
                      const Color(0xFF14B8A6),
                      isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _statBox(
                      'Berjalan',
                      _runningTime.isNotEmpty ? _runningTime : '...',
                      Icons.timer_outlined,
                      NusaConfig.accentPurple,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Spacer(),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Close shift card
        NusaCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tutup Shift & Hitung Kas',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Hitung uang yang ada di laci kas dan catat hasilnya.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Kas Dihitung (Rp)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _actualCashCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Hitung dan masukkan total kas',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 2),
                  ),
                  filled: true,
                  fillColor: isDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Catatan (opsional)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Misal: ada selisih karena refund...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 2),
                  ),
                  filled: true,
                  fillColor: isDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NusaConfig.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _closeShift();
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.stop_rounded, size: 22),
                      SizedBox(width: 8),
                      Text('Tutup Shift & Hitung Kas',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statBox(String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface2 : NusaConfig.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── History Tab ──────────────────────────────────────────────────────

  Widget _buildHistory(bool isDark) {
    if (_history.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        message: 'Belum ada riwayat shift.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _history.length,
      itemBuilder: (_, i) {
        final shift = _history[i];
        final isOpen = shift.status == 'Open';
        final openedTime =
            '${shift.openedAt.hour.toString().padLeft(2, '0')}:${shift.openedAt.minute.toString().padLeft(2, '0')}';
        final openedDate =
            '${shift.openedAt.day}/${shift.openedAt.month}/${shift.openedAt.year}';
        final selisihNeg = shift.difference < 0;

        String closedInfo = '';
        if (shift.closedAt != null) {
          final c = shift.closedAt!;
          closedInfo =
              'Tutup: ${c.day}/${c.month}/${c.year} ${c.hour.toString().padLeft(2, '0')}:${c.minute.toString().padLeft(2, '0')}';
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: NusaCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isOpen
                            ? NusaConfig.accentGreen.withValues(alpha: 0.12)
                            : const Color(0xFF14B8A6).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isOpen ? Icons.play_circle_outline : Icons.check_circle_outline,
                        size: 22,
                        color: isOpen ? NusaConfig.accentGreen : const Color(0xFF14B8A6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '$openedDate, $openedTime',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isOpen
                                      ? NusaConfig.accentGreen.withValues(alpha: 0.12)
                                      : (isDark ? NusaConfig.darkSurface2 : NusaConfig.borderColor),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isOpen ? 'Buka' : 'Tutup',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isOpen ? NusaConfig.accentGreen : NusaConfig.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (closedInfo.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              closedInfo,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Summary stats
                Row(
                  children: [
                    _miniStat('Awal', formatRupiah(shift.startingCash), isDark),
                    const SizedBox(width: 12),
                    _miniStat('Harapan', formatRupiah(shift.expectedCash), isDark),
                    const SizedBox(width: 12),
                    _miniStat('Aktual', formatRupiah(shift.actualCash), isDark),
                    const SizedBox(width: 12),
                    _miniStat(
                      'Selisih',
                      formatRupiah(shift.difference),
                      isDark,
                      valueColor: selisihNeg ? NusaConfig.primaryColor : NusaConfig.success,
                    ),
                  ],
                ),
                if (shift.notes != null && shift.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    shift.notes!,
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _miniStat(String label, String value, bool isDark, {Color? valueColor}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: valueColor ?? (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
