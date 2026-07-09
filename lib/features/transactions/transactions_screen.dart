import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});
  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  String _timeFilter = 'Hari Ini';
  String _payFilter = 'Semua';

  static const _timeChips = ['Hari Ini', 'Minggu Ini', 'Semua'];
  static const _payChips = ['Semua', 'Tunai', 'QRIS', 'Transfer'];

  List<Transaction> _filter(List<Transaction> all) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekAgo = now.subtract(const Duration(days: 7));
    final byTime = switch (_timeFilter) {
      'Hari Ini' =>
        all.where((t) => !t.date.isBefore(today)).toList(),
      'Minggu Ini' =>
        all.where((t) => t.date.isAfter(weekAgo)).toList(),
      _ => all,
    };
    if (_payFilter == 'Semua') return byTime;
    return byTime.where((t) => t.paymentMethod == _payFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      'Transaksi',
      Column(
        children: [
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
              future: ref.watch(transactionRepoProvider).getTransactions(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Gagal memuat: ${snap.error}',
                        style: const TextStyle(color: Colors.grey)),
                  );
                }
                final list = _filter(snap.data ?? []);
                if (list.isEmpty) {
                  return const Center(
                    child: Text('Belum ada transaksi',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _TransactionCard(tx: list[i]),
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
  const _TransactionCard({required this.tx});

  @override
  State<_TransactionCard> createState() => _TransactionCardState();
}

class _TransactionCardState extends State<_TransactionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final items = _parseItems(tx.items);
    final dateStr =
        '${tx.date.day}/${tx.date.month}/${tx.date.year} ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}';
    final subtotal = tx.total + tx.discount;

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(20),
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
                      Text(tx.invoice,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('$dateStr • ${tx.paymentMethod}',
                          style: const TextStyle(
                              fontSize: 13, color: NusaConfig.textSecondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatRupiah(tx.total),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: NusaConfig.primaryColor)),
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
            ],
          ],
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
