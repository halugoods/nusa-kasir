import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/skeleton_list.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});
  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  String _timeFilter = 'Hari Ini';
  String _payFilter = 'Semua';
  int _refreshKey = 0;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  static const _timeChips = ['Hari Ini', 'Minggu Ini', 'Semua'];
  static const _payChips = ['Semua', 'Tunai', 'QRIS', 'Transfer'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Transaction> _filter(List<Transaction> all) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekAgo = now.subtract(const Duration(days: 7));
    var filtered = switch (_timeFilter) {
      'Hari Ini' =>
        all.where((t) => !t.date.isBefore(today)).toList(),
      'Minggu Ini' =>
        all.where((t) => t.date.isAfter(weekAgo)).toList(),
      _ => all,
    };
    if (_payFilter != 'Semua') {
      filtered = filtered.where((t) => t.paymentMethod == _payFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((t) =>
        t.invoice.toLowerCase().contains(_searchQuery)
      ).toList();
    }
    return filtered;
  }

  Future<void> _voidTransaction(Transaction tx) async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Void Transaksi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invoice: ${tx.invoice}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Total: ${formatRupiah(tx.total)}',
                style: const TextStyle(
                    color: NusaConfig.primaryColor,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Alasan void *',
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.all(Radius.circular(12))),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          NusaButton(
            'Void',
            fullWidth: false,
            onPressed: () {
              final r = reasonCtrl.text.trim();
              if (r.isEmpty) {
                TopToast.error(context, 'Alasan void wajib diisi');
                return;
              }
              Navigator.pop(context, r);
            },
          ),
        ],
      ),
    );

    reasonCtrl.dispose();
    if (reason == null || reason.isEmpty) return;

    final repo = ref.read(transactionRepoProvider);
    final err = await repo.voidTransaction(tx.id, reason);
    if (mounted) {
      if (err != null) {
        TopToast.error(context, err);
      } else {
        TopToast.success(context, 'Transaksi #${tx.invoice} berhasil di-void');
        setState(() => _refreshKey++);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      'Transaksi',
      Column(
        children: [
          const SizedBox(height: 8),
          // Search by invoice
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Cari invoice...',
                prefixIcon: const Icon(Icons.search, color: NusaConfig.textSecondary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? NusaConfig.darkSurface
                    : NusaConfig.surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _timeChips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) =>
                  _filterChip(_timeChips[i], _timeFilter, (v) {
                setState(() => _timeFilter = v);
              }),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _payChips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) =>
                  _filterChip(_payChips[i], _payFilter, (v) {
                setState(() => _payFilter = v);
              }),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Transaction>>(
              key: ValueKey(_refreshKey),
              future: ref.watch(transactionRepoProvider).getTransactions(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SkeletonList();
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Gagal memuat: ${snap.error}',
                        style: const TextStyle(color: Colors.grey)),
                  );
                }
                final list = _filter(snap.data ?? []);
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    message: 'Belum ada transaksi',
                  );
                }
                // Summary
                final totalRevenue = list.fold<int>(0, (sum, t) => sum + t.total);
                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _refreshKey++);
                  },
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: NusaConfig.primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.summarize, size: 18, color: NusaConfig.primaryColor),
                              const SizedBox(width: 8),
                              Text('${list.length} transaksi',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              const Spacer(),
                              Text(formatRupiah(totalRevenue),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: NusaConfig.primaryColor)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => _TransactionCard(
                            tx: list[i],
                            onVoid: () => _voidTransaction(list[i]),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    String label,
    String selected,
    void Function(String) onSelect,
  ) {
    final isSel = label == selected;
    return FilterChip(
      label: Text(label),
      selected: isSel,
      showCheckmark: false,
      selectedColor: NusaConfig.primaryColor,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSel ? Colors.white : NusaConfig.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: NusaConfig.surfaceColor,
      onSelected: (_) => onSelect(label),
    );
  }
}

class _TransactionCard extends StatefulWidget {
  final Transaction tx;
  final VoidCallback onVoid;
  const _TransactionCard({required this.tx, required this.onVoid});

  @override
  State<_TransactionCard> createState() => _TransactionCardState();
}

class _TransactionCardState extends State<_TransactionCard> {
  bool _expanded = false;

  static const _payColors = {
    'Tunai': Color(0xFF10B981),
    'QRIS': Color(0xFF3B82F6),
    'Transfer': Color(0xFF8B5CF6),
  };
  static const _payIcons = {
    'Tunai': Icons.money,
    'QRIS': Icons.qr_code,
    'Transfer': Icons.account_balance,
  };

  Color _payColor() => _payColors[widget.tx.paymentMethod] ?? NusaConfig.textSecondary;
  IconData _payIcon() => _payIcons[widget.tx.paymentMethod] ?? Icons.payment;

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final items = _parseItems(tx.items);
    final dateStr =
        '${tx.date.day}/${tx.date.month}/${tx.date.year} ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}';
    final subtotal = tx.total + tx.discount;
    final isVoided = tx.status == 'Void';

    return Opacity(
      opacity: isVoided ? 0.55 : 1.0,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border(
              left: BorderSide(
                color: isVoided ? NusaConfig.textTertiary : _payColor(),
                width: 4,
              ),
            ),
          ),
          child: NusaCard(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(tx.invoice,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  decoration: isVoided
                                      ? TextDecoration.lineThrough
                                      : null)),
                          if (isVoided) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: NusaConfig.primaryColor
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('VOID',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: NusaConfig.primaryColor)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(_payIcon(), size: 14, color: isVoided ? NusaConfig.textTertiary : _payColor()),
                          const SizedBox(width: 4),
                          Text('$dateStr • ${tx.paymentMethod}',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: isVoided ? NusaConfig.textTertiary : _payColor())),
                        ],
                      )
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatRupiah(tx.total),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isVoided
                                ? NusaConfig.textTertiary
                                : NusaConfig.primaryColor)),
                    Icon(
                      _expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ],
            ),
            if (_expanded) ...[
              const Divider(height: 20),
              ...items.map((it) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                            child: Text('${it['name']} x ${it['qty']}',
                                style: const TextStyle(fontSize: 14))),
                        Text(
                            formatRupiah((it['qty'] as int) *
                                (it['price'] as int)),
                            style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                  )),
              const Divider(height: 20),
              _row('Subtotal', formatRupiah(subtotal)),
              _row('Diskon', formatRupiah(tx.discount)),
              _row('Total', formatRupiah(tx.total)),
              _row('Bayar', tx.cashGiven != null
                  ? formatRupiah(tx.cashGiven!)
                  : '-'),
              _row('Kembali', tx.cashReturn != null
                  ? formatRupiah(tx.cashReturn!)
                  : '-'),
              // Void reason (if voided)
              if (isVoided && tx.voidReason != null) ...[
                const SizedBox(height: 8),
                Text(
                  '🔴 Alasan void: ${tx.voidReason}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: NusaConfig.primaryColor,
                      fontStyle: FontStyle.italic),
                ),
              ],
              // Void button (only for normal, non-voided transactions)
              if (!isVoided) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onVoid,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Void Transaksi',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NusaConfig.primaryColor,
                      side: const BorderSide(color: NusaConfig.primaryColor),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 14, color: NusaConfig.textSecondary)),
            Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

List<Map<String, dynamic>> _parseItems(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is List) {
      return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    }
  } catch (_) {
    // ignore malformed items
  }
  return [];
}
