import 'package:flutter/material.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';

/// Red gradient profile card with avatar, user info,
/// left-right action buttons & 4 stats.
///
/// Button layout (horizontal):
///   🟣 Presensi (left) | 🟢 Masuk / 🔴 Pulang (right)
///
/// States:
///   - No session: avatar "?", name "--", role "Belum login"
///   - Logged in: avatar initials, real name + role + attendance status
class ProfileStatsCard extends StatelessWidget {
  final String initials;
  final String userName;
  final String role;
  final String branch;
  final String attendanceStatus;
  final String salesValue;
  final String transactionCount;
  final String avgValue;
  final String topProduct;
  final VoidCallback? onPresensiTap;
  final VoidCallback? onActionTap; // Masuk or Pulang
  final String actionLabel; // "Masuk" or "Pulang"
  final IconData actionIcon; // Icons.login or Icons.logout
  final Color actionColor; // Green or Red
  final bool hasSession; // whether an employee is logged in

  const ProfileStatsCard({
    super.key,
    this.initials = '?',
    this.userName = '--',
    this.role = 'Belum login',
    this.branch = '',
    this.attendanceStatus = 'Silakan absen masuk',
    this.salesValue = 'Rp 0',
    this.transactionCount = '0',
    this.avgValue = 'Rp 0',
    this.topProduct = '—',
    this.onPresensiTap,
    this.onActionTap,
    this.actionLabel = 'Masuk',
    this.actionIcon = Icons.login,
    this.actionColor = NusaConfig.accentGreen,
    this.hasSession = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
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

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildTopRow(),
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
      ),
    );
  }

  Widget _buildTopRow() {
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
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
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
                userName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
              Text(
                '$role${branch.isNotEmpty ? ' • $branch' : ''}',
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
                    hasSession ? Icons.check_circle : Icons.access_time,
                    size: 12,
                    color: hasSession
                        ? Colors.white70
                        : Colors.white.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    attendanceStatus,
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

        // Action buttons — left-right layout
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _actionBtn(
              icon: Icons.calendar_month,
              color: NusaConfig.accentPurple,
              shadowColor: NusaConfig.accentPurple,
              onTap: onPresensiTap,
            ),
            const SizedBox(width: 8),
            _actionBtn(
              icon: actionIcon,
              color: actionColor,
              shadowColor: actionColor,
              onTap: onActionTap,
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required Color color,
    required Color shadowColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: color,
          boxShadow: [
            BoxShadow(
              color: shadowColor.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final stats = [
      _Stat(
        icon: Icons.monetization_on_outlined,
        iconBg: NusaConfig.accentGold.withValues(alpha: 0.95),
        iconColor: Colors.white,
        value: salesValue,
        label: 'PENJUALAN',
      ),
      _Stat(
        icon: Icons.shopping_cart_outlined,
        iconBg: Colors.white.withValues(alpha: 0.22),
        iconColor: Colors.white,
        value: transactionCount,
        label: 'TRANSAKSI',
      ),
      _Stat(
        icon: Icons.trending_up,
        iconBg: Colors.white.withValues(alpha: 0.22),
        iconColor: Colors.white,
        value: avgValue,
        label: 'RATA-RATA',
      ),
      _Stat(
        icon: Icons.star_outline,
        iconBg: Colors.white.withValues(alpha: 0.22),
        iconColor: Colors.white,
        value: topProduct,
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
          style: const TextStyle(
            fontSize: 16,
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
