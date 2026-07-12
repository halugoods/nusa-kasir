import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/services/online_order_service.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/customer_repository.dart';
import 'package:nusa_kasir/data/repositories/online_order_repository.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/data/repositories/transaction_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/skeleton_list.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';
import 'package:nusa_kasir/features/auth/employee_session_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class OnlineOrdersScreen extends ConsumerStatefulWidget {
  const OnlineOrdersScreen({super.key});
  @override
  ConsumerState<OnlineOrdersScreen> createState() => _OnlineOrdersScreenState();
}

class _OnlineOrdersScreenState extends ConsumerState<OnlineOrdersScreen> with SingleTickerProviderStateMixin {
  List<OnlineOrder> _orders = [];
  bool _loading = true;
  late TabController _tabController;
  final List<String> _tabs = ['Semua', 'Baru', 'Disiapkan', 'Siap Diambil', 'Lunas'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _filter();
    });
    _load();
    _listenSupabase();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = OnlineOrderRepository(ref.read(databaseProvider));
    final all = await repo.getAll();
    if (mounted) setState(() { _orders = all; _loading = false; });
  }

  void _filter() {
    final idx = _tabController.index;
    final status = idx == 0 ? null : _tabs[idx];
    final repo = OnlineOrderRepository(ref.read(databaseProvider));
    repo.getAll(status: status).then((filtered) {
      if (mounted) setState(() => _orders = filtered);
    });
  }

  void _listenSupabase() {
    try {
      final supabase = Supabase.instance.client;
      supabase.channel('online-orders').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'online_orders',
        callback: (payload) {
          if (mounted) _load();
        },
      ).onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'online_orders',
        callback: (payload) {
          if (mounted) _load();
        },
      ).subscribe();
    } catch (e) {
      // ignore: avoid_print
      print('[OnlineOrders] Gagal subscribe Supabase realtime: $e');
    }
  }

  /// State machine transition buttons
  List<Widget> _actionsFor(OnlineOrder order) {
    final buttons = <Widget>[];
    final status = order.status;

    if (status == 'Online Baru') {
      buttons.add(_actionBtn('Terima & Siapkan', NusaConfig.accentGreen, () => _transition(order, 'Disiapkan')));
      buttons.add(const SizedBox(height: 6));
      buttons.add(_actionBtn('Tolak / Batal', NusaConfig.primaryColor, () => _transition(order, 'Dibatalkan')));
    } else if (status == 'Disiapkan') {
      buttons.add(_actionBtn('Siap Diambil', NusaConfig.accentPurple, () => _transition(order, 'Siap Diambil')));
      buttons.add(const SizedBox(height: 6));
      buttons.add(_actionBtn('Batal', NusaConfig.primaryColor, () => _transition(order, 'Dibatalkan')));
    } else if (status == 'Siap Diambil') {
      buttons.add(_actionBtn('Selesai (Lunas)', NusaConfig.accentGreenDark, () => _completeOrder(order)));
      buttons.add(const SizedBox(height: 6));
      buttons.add(_actionBtn('Batal', NusaConfig.primaryColor, () => _transition(order, 'Dibatalkan')));
    }

    return buttons;
  }

  Future<void> _transition(OnlineOrder order, String newStatus) async {
    // Confirm
    final labels = {
      'Disiapkan': 'Terima pesanan & mulai siapkan?',
      'Siap Diambil': 'Tandai pesanan siap diambil?',
      'Dibatalkan': 'Yakin batalkan pesanan ini?',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(newStatus == 'Dibatalkan' ? 'Batalkan Pesanan' : 'Update Status'),
        content: Text(labels[newStatus] ?? 'Update ke "$newStatus"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Tidak')),
          NusaButton(newStatus == 'Dibatalkan' ? 'Ya, Batalkan' : 'Ya, Lanjutkan',
              fullWidth: false,
              onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // Update local DB
    final session = ref.read(employeeSessionProvider);
    final repo = OnlineOrderRepository(ref.read(databaseProvider));
    await repo.updateStatus(order.id, newStatus, processedBy: session?.name);

    // Update Supabase
    final svc = OnlineOrderService(Supabase.instance.client);
    await svc.updateOrderStatus(orderId: order.id, status: newStatus, processedBy: session?.name);

    if (mounted) {
      TopToast.success(context, 'Pesanan #${order.invoice}: $newStatus');
      _load();
    }
  }

  Future<void> _completeOrder(OnlineOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Selesaikan Pesanan'),
        content: Text('Pesanan #${order.invoice} selesai?\n\n'
            'Stok akan otomatis berkurang & transaksi tercatat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          NusaButton('Selesai', fullWidth: false, onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // Parse items — fail early if JSON is corrupt
    final List items;
    try {
      items = (jsonDecode(order.items) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      if (mounted) {
        TopToast.error(context, 'Gagal membaca data pesanan #${order.invoice}. Hubungi developer.');
      }
      return;
    }

    final db = ref.read(databaseProvider);
    final session = ref.read(employeeSessionProvider);
    final productRepo = ProductRepository(db);
    final trxRepo = TransactionRepository(db);
    final customerRepo = CustomerRepository(db);

    final cartItems = items.map((i) => {
      'productId': i['product_id'],
      'name': i['name'] ?? '',
      'qty': i['qty'] ?? 1,
      'price': i['price'] ?? 0,
    }).toList();

    try {
      // Wrap stock deduction, transaction, loyalty, and status in a single DB transaction.
      // If any step fails, the entire block rolls back — no partial state.
      await db.transaction(() async {
        // Deduct stock for each item
        for (final item in items) {
          final pid = item['product_id'] as int?;
          final qty = item['qty'] as int? ?? 1;
          if (pid != null) {
            await productRepo.adjustStock(pid, -qty);
          }
        }

        // Record transaction locally
        await trxRepo.addTransaction(
          invoice: order.invoice,
          items: jsonEncode(cartItems),
          total: order.total,
          discount: order.discount,
          cashierName: session?.name ?? 'Sistem',
          paymentMethod: order.paymentMethod,
          branchId: null,
          cashGiven: order.total,
          cashReturn: 0,
        );

        // Add loyalty points for customer (if phone exists)
        if (order.customerPhone.isNotEmpty) {
          final customer = await customerRepo.byPhone(order.customerPhone);
          if (customer != null) {
            await customerRepo.addSpent(customer.id, order.total);
          }
        }

        // Update local status to Lunas
        final repo = OnlineOrderRepository(ref.read(databaseProvider));
        await repo.updateStatus(order.id, 'Lunas', processedBy: session?.name);
      });
    } catch (e) {
      if (mounted) {
        TopToast.error(context, 'Gagal menyelesaikan pesanan #${order.invoice}: $e');
      }
      return;
    }

    // Update Supabase (outside transaction — network call)
    try {
      final svc = OnlineOrderService(Supabase.instance.client);
      await svc.updateOrderStatus(orderId: order.id, status: 'Lunas', processedBy: session?.name);
    } catch (_) {
      // Supabase sync failed but local DB is consistent — will sync on next poll
    }

    if (mounted) {
      TopToast.success(context, 'Pesanan #${order.invoice} selesai! ✅');
      _load();
    }
  }

  Widget _actionBtn(String label, Color color, VoidCallback fn) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        onPressed: fn,
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  /// Format JSON items list to readable text
  String _formatItems(String itemsJson) {
    try {
      final items = (jsonDecode(itemsJson) as List).cast<Map<String, dynamic>>();
      return items.map((i) => '${i['qty']}x ${i['name']}').join(', ');
    } catch (_) {
      return itemsJson;
    }
  }

  /// Open WhatsApp with customer
  Future<void> _openWA(OnlineOrder order) async {
    if (order.customerPhone.isEmpty) return;
    final phone = order.customerPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Online Baru': return NusaConfig.accentGold;
      case 'Disiapkan': return NusaConfig.accentGreen;
      case 'Siap Diambil': return NusaConfig.accentPurple;
      case 'Lunas': return NusaConfig.accentGreenDark;
      case 'Dibatalkan': return NusaConfig.primaryColor;
      default: return NusaConfig.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScreenScaffold(
      _tabs[_tabController.index] == 'Semua' ? 'Pesanan Online' : 'Pesanan Online — ${_tabs[_tabController.index]}',
      Column(
        children: [
          // Tab bar
          Container(
            height: 44,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            decoration: BoxDecoration(
              color: isDark ? NusaConfig.darkSurface2 : NusaConfig.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              labelColor: NusaConfig.primaryColor,
              unselectedLabelColor: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textTertiary,
              indicator: BoxDecoration(
                color: isDark ? NusaConfig.darkSurface : NusaConfig.backgroundColor,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              padding: const EdgeInsets.all(4),
              tabs: _tabs.map((t) => Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t),
                    if (t != 'Semua') ...[
                      const SizedBox(width: 4),
                      _badgeFor(t),
                    ],
                  ],
                ),
              )).toList(),
              onTap: (_) => setState(() {}),
            ),
          ),

          // Order list
          Expanded(
            child: _loading
                ? const SkeletonList()
                : _orders.isEmpty
                    ? const EmptyState(icon: Icons.shopping_cart_outlined, message: 'Belum ada pesanan online')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _orders.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => _orderCard(_orders[i], isDark),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _badgeFor(String tab) {
    int count = 0;
    if (tab == 'Baru') count = _orders.where((o) => o.status == 'Online Baru').length;
    else if (tab == 'Disiapkan') count = _orders.where((o) => o.status == 'Disiapkan').length;
    else if (tab == 'Siap Diambil') count = _orders.where((o) => o.status == 'Siap Diambil').length;
    else if (tab == 'Lunas') count = _orders.where((o) => o.status == 'Lunas').length;

    if (count == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tab == 'Baru' ? NusaConfig.primaryColor.withValues(alpha: 0.12) : NusaConfig.textTertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        count.toString(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: tab == 'Baru' ? NusaConfig.primaryColor : NusaConfig.textSecondary,
        ),
      ),
    );
  }

  Widget _orderCard(OnlineOrder order, bool isDark) {
    final sColor = _statusColor(order.status);

    return NusaCard(
      padding: EdgeInsets.zero,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: invoice + status
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                // Invoice
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${order.invoice}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatDate(order.createdAt)} • ${order.branch}',
                        style: const TextStyle(fontSize: 11, color: NusaConfig.textTertiary),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: sColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    order.status,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sColor),
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Divider(height: 1, thickness: 1, color: isDark ? NusaConfig.darkDivider : NusaConfig.dividerColor),

          // Customer info
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.person_outline, size: 16, color: NusaConfig.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.customerName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                    ),
                  ),
                ),
                if (order.customerPhone.isNotEmpty)
                  GestureDetector(
                    onTap: () => _openWA(order),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('💬 WA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF128C7E))),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Text(
              order.customerPhone.isNotEmpty ? '📱 ${order.customerPhone}' : 'Tanpa nomor WA',
              style: const TextStyle(fontSize: 12, color: NusaConfig.textSecondary),
            ),
          ),

          // Items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _formatItems(order.items),
              style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),

          // Payment + total
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.payment, size: 14, color: NusaConfig.textTertiary),
                const SizedBox(width: 4),
                Text(order.paymentMethod, style: const TextStyle(fontSize: 12, color: NusaConfig.textTertiary)),
                const Spacer(),
                Text(formatRupiah(order.total),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
              ],
            ),
          ),

          // Pickup time
          if (order.pickupTime != null && order.pickupTime!.isNotEmpty && order.pickupTime != 'Segera')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: NusaConfig.textTertiary),
                  const SizedBox(width: 4),
                  Text('Pickup: ${order.pickupTime}', style: const TextStyle(fontSize: 12, color: NusaConfig.textTertiary)),
                ],
              ),
            ),

          // Action buttons
          if (_actionsFor(order).isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _actionsFor(order),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
