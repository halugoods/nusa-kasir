import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/shared/widgets/animated_builder.dart'
    show NusaAnimatedBuilder;

/// EmployeeCardData — pre-fetched data for the flip card back side.
class EmployeeCardData {
  final int penjualan;
  final int laba;
  final int trxCount;
  final int modalAwal;
  final int totalLaci;
  final int selisihLaci;
  final String? shiftHours;
  final int omzet;
  final int transaksiBulan;
  final int hadirDays;
  final int totalDays;
  final int pendingItems;

  const EmployeeCardData({
    this.penjualan = 0,
    this.laba = 0,
    this.trxCount = 0,
    this.modalAwal = 0,
    this.totalLaci = 0,
    this.selisihLaci = 0,
    this.shiftHours,
    this.omzet = 0,
    this.transaksiBulan = 0,
    this.hadirDays = 0,
    this.totalDays = 0,
    this.pendingItems = 0,
  });
}

/// Red gradient profile card with 3D flip.
///
/// **Front:** Same layout as before — avatar, name, role, branch, attendance,
/// and 4 sales KPI stats (PENJUALAN, TRANSAKSI, RATA-RATA, TERLARIS).
///
/// **Back:** Role-adaptive data:
///   - Owner → live sales + profit + pending items
///   - Manager → monthly performance + attendance
///   - Kasir → cash drawer reconciliation
///
/// Tap to flip. Non-Owner / non-self viewers cannot see the back.
class ProfileStatsCard extends StatefulWidget {
  // ── Front display fields (unchanged) ────────────────
  final String? photoPath;
  final String initials;
  final String userName;
  final String role;
  final String branch;
  final String attendanceStatus;
  final String salesValue;
  final String transactionCount;
  final String avgValue;
  final String topProduct;

  // ── Flip / back-side fields ────────────────────────
  final String viewerRole;
  final int? viewerEmployeeId;
  final int? employeeId;
  final EmployeeCardData? cardData;
  final Future<bool> Function()? onAuthOwner;
  final VoidCallback? onAbsenMasuk;
  final VoidCallback? onAbsenKeluar;
  final VoidCallback? onKontakWa;

  const ProfileStatsCard({
    super.key,
    this.photoPath,
    this.initials = '?',
    this.userName = 'Belum ada sesi kasir',
    this.role = '',
    this.branch = '',
    this.attendanceStatus = 'Buka Kasir untuk memulai',
    this.salesValue = 'Rp 0',
    this.transactionCount = '0',
    this.avgValue = 'Rp 0',
    this.topProduct = '—',
    this.viewerRole = 'Kasir',
    this.viewerEmployeeId,
    this.employeeId,
    this.cardData,
    this.onAuthOwner,
    this.onAbsenMasuk,
    this.onAbsenKeluar,
    this.onKontakWa,
  });

  @override
  State<ProfileStatsCard> createState() => _ProfileStatsCardState();
}

class _ProfileStatsCardState extends State<ProfileStatsCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  bool _isFlipped = false;

  bool get _isSelf =>
      widget.viewerEmployeeId != null &&
      widget.employeeId != null &&
      widget.viewerEmployeeId == widget.employeeId;

  bool get _canFlip =>
      _isSelf || widget.viewerRole == 'Owner';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _anim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _toggleFlip() async {
    if (_isFlipped) {
      // Flip back to front — always allowed
      _ctrl.reverse();
      setState(() => _isFlipped = false);
      return;
    }

    // Flip to back — check access
    if (!_canFlip) return; // silently blocked

    // Owner in non-Owner session must authenticate
    if (widget.viewerRole == 'Owner' &&
        widget.onAuthOwner != null &&
        !_isSelf) {
      final ok = await widget.onAuthOwner!();
      if (!ok) return;
    }

    _ctrl.forward();
    setState(() => _isFlipped = true);
  }

  // ────────────────────────────────────────────────────
  // FRONT SIDE (unchanged from original)
  // ────────────────────────────────────────────────────

  Widget _buildFront() {
    final hasPhoto = widget.photoPath != null &&
        widget.photoPath!.isNotEmpty &&
        File(widget.photoPath!).existsSync();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [NusaConfig.primaryColor, NusaConfig.primaryDark],
        ),
        boxShadow: [
          BoxShadow(
            color: NusaConfig.primaryColor.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),

          // Flip hint (top-right corner)
          if (_canFlip)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.flip_to_back,
                    size: 14, color: Colors.white.withValues(alpha: 0.8)),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildTopRow(hasPhoto),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 16),
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                _buildStatsGrid(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopRow(bool hasPhoto) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withValues(alpha: 0.22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
            ),
            image: hasPhoto
                ? DecorationImage(
                    image: FileImage(File(widget.photoPath!)),
                    fit: BoxFit.cover)
                : null,
          ),
          alignment: Alignment.center,
          child: hasPhoto
              ? null
              : Text(
                  widget.initials,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
        ),
        const SizedBox(width: 12),

        // Name + role + attendance
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.userName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
              Text(
                '${widget.role}${widget.branch.isNotEmpty ? ' • ${widget.branch}' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.9),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.access_time,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.attendanceStatus,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    final stats = [
      _Stat(
        icon: Icons.monetization_on_outlined,
        iconBg: NusaConfig.accentGold.withValues(alpha: 0.95),
        iconColor: Colors.white,
        value: widget.salesValue,
        label: 'PENJUALAN',
      ),
      _Stat(
        icon: Icons.shopping_cart_outlined,
        iconBg: Colors.white.withValues(alpha: 0.22),
        iconColor: Colors.white,
        value: widget.transactionCount,
        label: 'TRANSAKSI',
      ),
      _Stat(
        icon: Icons.trending_up,
        iconBg: Colors.white.withValues(alpha: 0.22),
        iconColor: Colors.white,
        value: widget.avgValue,
        label: 'RATA-RATA',
      ),
      _Stat(
        icon: Icons.star_outline,
        iconBg: Colors.white.withValues(alpha: 0.22),
        iconColor: Colors.white,
        value: widget.topProduct,
        label: 'TERLARIS',
      ),
    ];

    return Row(
      children: stats.map((s) => Expanded(child: _statItem(s))).toList(),
    );
  }

  Widget _statItem(_Stat s) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: s.iconBg,
          ),
          alignment: Alignment.center,
          child: Icon(s.icon, size: 16, color: s.iconColor),
        ),
        const SizedBox(height: 6),
        Text(
          s.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        Text(
          s.label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────
  // BACK SIDE (role-adaptive)
  // ────────────────────────────────────────────────────

  Widget _buildBack() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final data = widget.cardData;

    switch (widget.viewerRole) {
      case 'Kasir':
        return _buildKasirBack(isDark, data);
      case 'Manager':
        return _buildManagerBack(isDark, data);
      default:
        return _buildOwnerBack(isDark, data);
    }
  }

  // ── Kasir: Cash Drawer ────────────────────────────

  Widget _buildKasirBack(bool isDark, EmployeeCardData? data) {
    final surfaceColor =
        isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor;
    final textColor =
        isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary;
    final subColor =
        isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary;
    final isRed = (data?.selisihLaci ?? 0) < 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          _backHeader(Icons.point_of_sale, 'Shift Saya', isDark, textColor),
          const SizedBox(height: 12),
          _statRow('Modal Awal', formatRupiah(data?.modalAwal ?? 0), subColor,
              textColor),
          _statRow(
              'Penjualan', formatRupiah(data?.penjualan ?? 0), subColor, textColor),
          Divider(
              color: isDark ? NusaConfig.darkDivider : NusaConfig.dividerColor,
              height: 16),
          _statRow('Total di Laci', formatRupiah(data?.totalLaci ?? 0),
              subColor, textColor,
              bold: true),
          _statRow(
            'Selisih',
            formatRupiah(data?.selisihLaci.abs() ?? 0),
            subColor,
            isRed ? NusaConfig.primaryColor : NusaConfig.accentGreen,
            suffix: isRed ? ' (kurang)' : '',
          ),
          if (data?.shiftHours != null) ...[
            const SizedBox(height: 6),
            Text('Shift: ${data!.shiftHours}',
                style: TextStyle(fontSize: 11, color: subColor)),
          ],
          const SizedBox(height: 14),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: _backButton(
                  'Absen Masuk',
                  Icons.login,
                  NusaConfig.accentGreen,
                  widget.onAbsenMasuk,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _backButton(
                  'Absen Keluar',
                  Icons.logout,
                  NusaConfig.primaryColor,
                  widget.onAbsenKeluar,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Manager: Performance ──────────────────────────

  Widget _buildManagerBack(bool isDark, EmployeeCardData? data) {
    final surfaceColor =
        isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor;
    final textColor =
        isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary;
    final subColor =
        isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _backHeader(
              Icons.trending_up, 'Performa Bulan Ini', isDark, textColor),
          const SizedBox(height: 12),
          _statRow(
              'Omzet', formatRupiah(data?.omzet ?? 0), subColor, textColor),
          _statRow('Transaksi', '${data?.transaksiBulan ?? 0}', subColor,
              textColor),
          _statRow('Hadir', '${data?.hadirDays ?? 0}/${data?.totalDays ?? 0} hari',
              subColor, textColor),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: _backButton(
              'Hubungi WA',
              Icons.chat,
              NusaConfig.accentGreen,
              widget.onKontakWa,
            ),
          ),
        ],
      ),
    );
  }

  // ── Owner: Command Center ─────────────────────────

  Widget _buildOwnerBack(bool isDark, EmployeeCardData? data) {
    final surfaceColor =
        isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor;
    final textColor =
        isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _backHeader(Icons.insights, 'Live Hari Ini', isDark, textColor),
          const SizedBox(height: 12),
          // Mini stats row
          Row(
            children: [
              _ownerMiniStat(
                  'Penjualan', formatRupiah(data?.penjualan ?? 0), textColor),
              _ownerMiniStat('Laba', formatRupiah(data?.laba ?? 0),
                  NusaConfig.accentGreen),
              _ownerMiniStat(
                  'Trx', '${data?.trxCount ?? 0}', NusaConfig.accentPurple),
            ],
          ),
          const SizedBox(height: 12),
          // Pending alert
          if ((data?.pendingItems ?? 0) > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: NusaConfig.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.notifications_active,
                      size: 16, color: NusaConfig.warning),
                  const SizedBox(width: 6),
                  Text('${data!.pendingItems} item perlu tindakan',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: NusaConfig.warning)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: _backButton('Hubungi WA', Icons.chat, NusaConfig.accentGreen,
                widget.onKontakWa),
          ),
        ],
      ),
    );
  }

  // ── Shared back-side helpers ──────────────────────

  Widget _backHeader(
      IconData icon, String title, bool isDark, Color textColor) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: NusaConfig.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: NusaConfig.primaryColor, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title,
              style:
                  TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
        ),
        // Flip-back hint
        GestureDetector(
          onTap: _toggleFlip,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isDark
                  ? NusaConfig.darkDivider.withValues(alpha: 0.5)
                  : NusaConfig.dividerColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.flip_to_front, size: 16, color: NusaConfig.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _statRow(String label, String value, Color subColor, Color valueColor,
      {bool bold = false, String suffix = ''}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: subColor)),
          Text(
            '$value$suffix',
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ownerMiniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: -0.3)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _backButton(
      String label, IconData icon, Color color, VoidCallback? onTap) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────
  // 3D FLIP BUILD
  // ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleFlip,
      child: NusaAnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final isFrontVisible = _anim.value <= 0.5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(_anim.value * 3.14159),
            child: isFrontVisible ? _buildFront() : _buildBack(),
          );
        },
      ),
    );
  }
}

class _Stat {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String value;
  final String label;
  const _Stat({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.value,
    required this.label,
  });
}

/// Local AnimatedBuilder (shared with pin_keypad; keep here for self-containment).
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  Animation<double> get animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) => builder(context, child);
}
