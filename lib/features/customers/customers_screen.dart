import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/customer_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/skeleton_list.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';

/// 6 random avatar colors picked from hash of customer name.
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

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  List<Customer> _customers = [];
  bool _loading = true;
  String _levelFilter = 'Semua';

  static const _levelOptions = ['Semua', 'Regular', 'Gold', 'Platinum'];

  @override
  void initState() {
    super.initState();
    _search.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _search.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = CustomerRepository(ref.read(databaseProvider));
    final all = await repo.getCustomers();
    final q = _search.text.toLowerCase();
    var filtered = q.isEmpty
        ? all
        : all
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                (c.phone?.toLowerCase().contains(q) ?? false))
            .toList();
    if (_levelFilter != 'Semua') {
      final levelKey = _levelFilter == 'Regular' ? 'Silver' : _levelFilter;
      filtered = filtered.where((c) => c.level == levelKey).toList();
    }
    if (mounted) {
      setState(() {
        _customers = filtered;
        _loading = false;
      });
    }
  }

  void _showAddSheet() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? NusaConfig.darkSurface
                    : NusaConfig.surfaceColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                10,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: NusaConfig.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: NusaConfig.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.person_add_rounded,
                          color: NusaConfig.primaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Tambah Pelanggan',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? NusaConfig.darkTextPrimary
                            : NusaConfig.textPrimary,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  NusaInput('Nama Pelanggan', controller: nameCtrl, hint: 'Cth: Dimas'),
                  const SizedBox(height: 12),
                  NusaInput('Telepon (opsional)',
                      controller: phoneCtrl, type: TextInputType.phone, hint: 'Cth: 0812xxxx'),
                  const SizedBox(height: 12),
                  NusaInput('Alamat (opsional)', controller: addressCtrl, hint: 'Cth: Jl. Merdeka No.1'),
                  const SizedBox(height: 20),
                  NusaButton(
                    'Simpan',
                    onPressed: saving
                        ? null
                        : () async {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) {
                              TopToast.error(
                                  context, 'Nama pelanggan wajib diisi');
                              return;
                            }
                            setSt(() => saving = true);
                            final repo = CustomerRepository(
                                ref.read(databaseProvider));
                            await repo.addCustomer(
                              name: name,
                              phone: phoneCtrl.text.trim(),
                              address: addressCtrl.text.trim(),
                            );
                            if (mounted) Navigator.pop(ctx);
                            _load();
                          },
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showDetail(Customer c) {
    final phone = c.phone ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).brightness == Brightness.dark
              ? NusaConfig.darkSurface
              : NusaConfig.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _CustomerDetailSheet(customer: c, phone: phone),
      ),
    );
  }

  Future<void> _deleteCustomer(Customer c) async {
    final repo = CustomerRepository(ref.read(databaseProvider));
    await repo.deleteCustomer(c.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ScreenScaffold(
      'Pelanggan',
      Column(
        children: [
          const SizedBox(height: 8),
          // ── Search ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? NusaConfig.darkInputFill
                    : NusaConfig.inputFill,
                borderRadius: BorderRadius.circular(NusaConfig.radiusXL),
                border: Border.all(
                  color: isDark
                      ? NusaConfig.darkInputBorder
                      : NusaConfig.inputBorder,
                ),
              ),
              child: TextField(
                controller: _search,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark
                      ? NusaConfig.darkTextPrimary
                      : NusaConfig.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Cari nama atau telepon…',
                  hintStyle: TextStyle(
                    color: isDark
                        ? NusaConfig.darkTextTertiary
                        : NusaConfig.textTertiary,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: NusaConfig.textSecondary, size: 22),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ── Level segmented filter ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _segmented(
              options: _levelOptions,
              selected: _levelFilter,
              onSelect: (v) {
                setState(() => _levelFilter = v);
                _load();
              },
            ),
          ),
          const SizedBox(height: 12),
          // ── List ──
          Expanded(
            child: _loading
                ? const SkeletonList()
                : _customers.isEmpty
                    ? const EmptyState(
                        icon: Icons.people_outline,
                        message: 'Belum ada pelanggan',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _customers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final c = _customers[i];
                            return Dismissible(
                              key: ValueKey(c.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade400,
                                  borderRadius: BorderRadius.circular(
                                      NusaConfig.radiusLG),
                                ),
                                child: const Icon(Icons.delete,
                                    color: Colors.white),
                              ),
                              confirmDismiss: (_) async {
                                return await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Hapus Pelanggan'),
                                    content: Text('Hapus "${c.name}"?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Batal'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Hapus',
                                            style: TextStyle(
                                                color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              onDismissed: (_) => _deleteCustomer(c),
                              child: _CustomerTile(
                                customer: c,
                                onTap: () => _showDetail(c),
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
        icon: const Icon(Icons.add),
        label: const Text('Tambah Pelanggan'),
        onPressed: _showAddSheet,
      ),
    );
  }

  Widget _segmented({
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface : NusaConfig.backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
      ),
      child: Row(
        children: options.map((opt) {
          final active = opt == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(opt),
              child: Container(
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? NusaConfig.primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  opt,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? Colors.white
                        : (isDark
                            ? NusaConfig.darkTextSecondary
                            : NusaConfig.textSecondary),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Customer tile card
// ═══════════════════════════════════════════

class _CustomerTile extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;
  const _CustomerTile({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = customer;
    final levelDisplay = c.level == 'Silver' ? 'Regular' : c.level;
    final Color levelColor;
    switch (c.level) {
      case 'Platinum':
        levelColor = Colors.purple;
      case 'Gold':
        levelColor = Colors.amber.shade700;
      default:
        levelColor = Colors.grey;
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(NusaConfig.radiusLG),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NusaConfig.radiusLG),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
            borderRadius: BorderRadius.circular(NusaConfig.radiusLG),
            border: Border.all(
                color: isDark
                    ? NusaConfig.darkBorder
                    : NusaConfig.dividerColor),
            boxShadow: [
              BoxShadow(
                  color: Colors.black
                      .withValues(alpha: isDark ? 0.15 : 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3))
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: _avatarColor(c.name),
              child: Text(
                c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                style: GoogleFonts.plusJakartaSans(
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
                  Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? NusaConfig.darkTextPrimary
                            : NusaConfig.textPrimary,
                      )),
                  const SizedBox(height: 3),
                  if (c.phone != null && c.phone!.isNotEmpty)
                    Text(c.phone!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? NusaConfig.darkTextTertiary
                              : NusaConfig.textTertiary,
                        )),
                  const SizedBox(height: 6),
                  Text('Total: ${formatRupiah(c.totalSpent)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: NusaConfig.primaryColor,
                      )),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(NusaConfig.radiusSM),
              ),
              child: Text(
                levelDisplay,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: levelColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: NusaConfig.textTertiary),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Customer detail sheet
// ═══════════════════════════════════════════

class _CustomerDetailSheet extends StatelessWidget {
  final Customer customer;
  final String phone;

  const _CustomerDetailSheet({
    required this.customer,
    required this.phone,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = customer;
    final levelDisplay = c.level == 'Silver' ? 'Regular' : c.level;
    final Color levelColor;
    switch (c.level) {
      case 'Platinum':
        levelColor = Colors.purple;
      case 'Gold':
        levelColor = Colors.amber.shade700;
      default:
        levelColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: NusaConfig.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: _avatarColor(c.name),
                child: Text(
                  c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? NusaConfig.darkTextPrimary
                              : NusaConfig.textPrimary,
                        )),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: levelColor.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(NusaConfig.radiusSM),
                      ),
                      child: Text(
                        levelDisplay,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: levelColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _detailRow(Icons.phone_outlined, 'Telepon',
              phone.isEmpty ? '-' : phone, isDark),
          const SizedBox(height: 8),
          _detailRow(Icons.location_on_outlined, 'Alamat',
              c.address?.isEmpty ?? true ? '-' : c.address!, isDark),
          const SizedBox(height: 8),
          _detailRow(Icons.attach_money_rounded, 'Total Belanja',
              formatRupiah(c.totalSpent), isDark),
          const SizedBox(height: 8),
          _detailRow(Icons.star_rounded, 'Poin', '${c.points}', isDark),
          const SizedBox(height: 24),
          if (phone.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openWhatsApp(context, phone),
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('Kirim WA'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF25D366),
                  side: const BorderSide(color: Color(0xFF25D366)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface2 : NusaConfig.inputFill,
        borderRadius: BorderRadius.circular(NusaConfig.radiusSM),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: NusaConfig.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: isDark
                        ? NusaConfig.darkTextTertiary
                        : NusaConfig.textTertiary,
                  )),
              Text(value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? NusaConfig.darkTextPrimary
                        : NusaConfig.textPrimary,
                  )),
            ],
          ),
        ),
      ]),
    );
  }

  Future<void> _openWhatsApp(BuildContext context, String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final normalized = digits.startsWith('0')
        ? '62${digits.substring(1)}'
        : digits.startsWith('62')
            ? digits
            : '62$digits';
    final uri = Uri.parse('https://wa.me/$normalized');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}
