import 'package:flutter/material.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';

/// NUSA-branded app header: logo + user info + notification bell.
///
/// Matches the reference design:
///   - "NUSA" wordmark in brand red (24px extrabold)
///   - Vertical divider, then user name (13px semibold) + role • branch (11px)
///   - Bell icon (44x44 tap target) with red notification dot
class DashboardHeader extends StatelessWidget {
  final String userName;
  final String role;
  final String branch;
  final bool hasNotification;
  final VoidCallback? onBellTap;

  const DashboardHeader({
    super.key,
    this.userName = '',
    this.role = '',
    this.branch = '',
    this.hasNotification = false,
    this.onBellTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Left: Logo + user info
          Expanded(
            child: Row(
              children: [
                // NUSA wordmark + divider + app name
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'NUSA',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: NusaConfig.primaryColor,
                        height: 1,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Aplikasi Kasir untuk Toko Kelontong',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: NusaConfig.textTertiary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
                // Vertical divider
                Container(
                  height: 20,
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: NusaConfig.dividerColor,
                ),
                // User info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: NusaConfig.textPrimary,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$role • $branch',
                        style: const TextStyle(
                          fontSize: 11,
                          color: NusaConfig.textSecondary,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Right: Bell button with notification dot
          GestureDetector(
            onTap: onBellTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.notifications_outlined,
                    size: 22,
                    color: NusaConfig.textPrimary,
                  ),
                  if (hasNotification)
                    Positioned(
                      top: 9,
                      right: 10,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: NusaConfig.primaryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
