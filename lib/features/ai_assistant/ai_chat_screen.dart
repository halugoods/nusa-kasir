import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/services/ai_service.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/data/repositories/transaction_repository.dart';
import 'package:nusa_kasir/data/repositories/promo_repository.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';

const int _maxContextChars = 260000; // ~65K tokens

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});
  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _messages = <ChatMessage>[];
  bool _loading = false;
  String? _storeName;
  int? _activeSessionId;
  List<ChatSession> _sessions = [];
  bool _showSessions = false;

  final List<String> _hints = [
    "Analisis penjualan",
    "Stok habis",
    "Laporan mingguan",
    "Top produk",
    "Tips bisnis",
  ];

  @override
  void initState() {
    super.initState();
    _loadStoreName();
    _loadSessions();
    _messages.add(ChatMessage(
      role: 'assistant',
      content:
          '👋 Halo! Saya AI Assistant NUSA Kasir. Saya punya akses ke data toko kamu — tanya soal stok, penjualan, promo, atau laporan. Ada yang bisa saya bantu?',
    ));
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  int get _totalChars => _messages.fold<int>(0, (s, m) => s + m.content.length);
  double get _contextUsage => (_totalChars / _maxContextChars).clamp(0.0, 1.0);

  // ── Session management ──────────────────────────────────────────────

  Future<void> _loadSessions() async {
    try {
      final db = ref.read(databaseProvider);
      final rows = await (db.select(db.chatSessions)
        ..orderBy([(t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)]))
        .get();
      if (mounted) setState(() => _sessions = rows);
    } catch (_) {}
  }

  Future<void> _saveSession() async {
    if (_messages.length <= 1) return; // don't save empty sessions
    try {
      final db = ref.read(databaseProvider);
      final title = _autoTitle();
      final json = jsonEncode(_messages.map((m) => m.toJson()).toList());
      if (_activeSessionId != null) {
        await (db.update(db.chatSessions)..where((t) => t.id.equals(_activeSessionId!)))
            .write(ChatSessionsCompanion(
              title: Value(title),
              messagesJson: Value(json),
              updatedAt: Value(DateTime.now()),
            ));
      } else {
        _activeSessionId = await db.into(db.chatSessions).insert(ChatSessionsCompanion.insert(
              title: title,
              messagesJson: json,
            ));
      }
      _loadSessions();
    } catch (_) {}
  }

  Future<void> _loadSession(ChatSession session) async {
    try {
      final msgs = (jsonDecode(session.messagesJson) as List)
          .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
          .toList();
      setState(() {
        _messages.clear();
        _messages.addAll(msgs);
        _activeSessionId = session.id;
        _showSessions = false;
      });
      _scrollToBottom();
    } catch (_) {}
  }

  Future<void> _deleteSession(ChatSession session) async {
    try {
      final db = ref.read(databaseProvider);
      await (db.delete(db.chatSessions)..where((t) => t.id.equals(session.id))).go();
      if (_activeSessionId == session.id) {
        setState(() => _activeSessionId = null);
      }
      _loadSessions();
    } catch (_) {}
  }

  void _newChat() {
    _saveSession();
    setState(() {
      _messages.clear();
      _activeSessionId = null;
      _showSessions = false;
      _messages.add(ChatMessage(
        role: 'assistant',
        content: '👋 Halo! Ada yang bisa saya bantu hari ini?',
      ));
    });
  }

  String _autoTitle() {
    final firstUser = _messages.where((m) => m.role == 'user').firstOrNull;
    if (firstUser == null) return 'Chat Baru';
    final words = firstUser.content.split(' ');
    return words.take(6).join(' ') + (words.length > 6 ? '...' : '');
  }

  // ── Database context ────────────────────────────────────────────────

  Future<String> _buildDbContext() async {
    final sb = StringBuffer();
    sb.writeln('=== DATA TOKO REAL-TIME ===');
    try {
      final db = ref.read(databaseProvider);
      // Products summary
      final products = await ProductRepository(db).getProducts();
      final totalProducts = products.length;
      final outOfStock = products.where((p) => p.stock == 0).length;
      final lowStock = products.where((p) => p.stock > 0 && p.stock <= p.minStock).length;
      sb.writeln('Produk: $totalProducts total, $outOfStock habis, $lowStock menipis');

      // Top 5 products by stock value
      final top5 = List.from(products)
        ..sort((a, b) => (b.stock * b.sellPrice).compareTo(a.stock * a.sellPrice));
      if (top5.isNotEmpty) {
        sb.writeln('Top produk:');
        for (final p in top5.take(5)) {
          sb.writeln('  - ${p.name}: stok ${p.stock}, harga jual Rp${p.sellPrice}');
        }
      }

      // Transactions today
      final transactions = await ref.read(transactionRepoProvider).getTransactions();
      final today = DateTime.now();
      final todayTrx = transactions.where((t) {
        final d = t.date;
        return d.year == today.year && d.month == today.month && d.day == today.day;
      }).toList();
      final todayTotal = todayTrx.fold<int>(0, (s, t) => s + t.total);
      final todayCount = todayTrx.length;
      sb.writeln('Transaksi hari ini: $todayCount transaksi, total Rp$todayTotal');

      // This month
      final monthTrx = transactions.where((t) {
        final d = t.date;
        return d.year == today.year && d.month == today.month;
      }).toList();
      final monthTotal = monthTrx.fold<int>(0, (s, t) => s + t.total);
      sb.writeln('Transaksi bulan ini: ${monthTrx.length} transaksi, total Rp$monthTotal');

      // Active promos
      final promos = await PromoRepository(db).getPromos();
      final activePromos = promos.where((p) => p.status == 'Aktif').toList();
      if (activePromos.isNotEmpty) {
        sb.writeln('Promo aktif:');
        for (final p in activePromos) {
          sb.writeln('  - ${p.name} (${p.code}): ${p.type == "persen" ? "${p.value}%" : "Rp${p.value}"} off, terpakai ${p.usedCount}x');
        }
      }

      // Store name
      if (_storeName != null) {
        sb.writeln('Nama toko: $_storeName');
      }
    } catch (_) {
      sb.writeln('(Data toko tidak tersedia)');
    }
    sb.writeln('=== AKHIR DATA TOKO ===');
    return sb.toString();
  }

  Future<void> _loadStoreName() async {
    final name = await ref.read(settingsRepoProvider).getStoreName();
    if (mounted && name.isNotEmpty) setState(() => _storeName = name);
  }

  // ── Send message ────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _messages.add(ChatMessage(role: 'user', content: text));
      _loading = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();

    try {
      // Build database context for the AI
      final dbContext = await _buildDbContext();

      final svc = AiService(Supabase.instance.client);
      final reply = await svc.chat(
        messages: _messages,
        storeName: _storeName,
        dbContext: dbContext,
      );

      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(role: 'assistant', content: reply));
          _loading = false;
        });
        _scrollToBottom();
        _saveSession();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
              role: 'assistant', content: '⚠️ Gagal: $e'));
          _loading = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant', style: TextStyle(fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(_showSessions ? Icons.close : Icons.history),
          onPressed: () => setState(() => _showSessions = !_showSessions),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'Chat Baru',
            onPressed: _newChat,
          ),
        ],
      ),
      body: Row(
        children: [
          // Session drawer
          if (_showSessions) _buildSessionDrawer(isDark),
          // Chat area
          Expanded(child: _buildChatArea(isDark)),
        ],
      ),
    );
  }

  Widget _buildSessionDrawer(bool isDark) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface : Colors.white,
        border: Border(
          right: BorderSide(color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Riwayat Chat',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
          ),
          const Divider(),
          Expanded(
            child: _sessions.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Belum ada riwayat chat',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13,
                              color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
                    ),
                  )
                : ListView.builder(
                    itemCount: _sessions.length,
                    itemBuilder: (_, i) {
                      final s = _sessions[i];
                      final active = s.id == _activeSessionId;
                      return ListTile(
                        dense: true,
                        selected: active,
                        selectedTileColor: NusaConfig.primaryColor.withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        title: Text(s.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          _formatDate(s.updatedAt),
                          style: TextStyle(fontSize: 11,
                              color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16),
                          onPressed: () => _deleteSession(s),
                        ),
                        onTap: () => _loadSession(s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatArea(bool isDark) {
    return Column(
      children: [
        // Header info
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: NusaConfig.primaryColor.withValues(alpha: 0.06),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: NusaConfig.primaryColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _storeName != null
                      ? 'AI Assistant • $_storeName'
                      : 'AI Assistant NUSA Kasir',
                  style: const TextStyle(
                      fontSize: 12,
                      color: NusaConfig.primaryColor,
                      fontWeight: FontWeight.w600),
                ),
              ),
              // Context usage indicator
              if (_messages.length > 2) ...[
                Container(
                  width: 60, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _contextUsage,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _contextUsage > 0.8
                            ? NusaConfig.primaryColor
                            : _contextUsage > 0.5
                                ? Colors.orange
                                : NusaConfig.accentGreen,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text('${(_contextUsage * 100).toInt()}%',
                    style: TextStyle(fontSize: 9, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
              ],
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: NusaConfig.accentGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('GRATIS',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: NusaConfig.accentGreen)),
              ),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_loading ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == _messages.length) {
                return _typingIndicator(isDark);
              }
              return _bubble(_messages[i], isDark);
            },
          ),
        ),

        // Quick hints
        if (_hints.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _hints.map((hint) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(hint, style: const TextStyle(fontSize: 12)),
                      onPressed: _loading ? null : () {
                        _inputCtrl.text = hint;
                        _send();
                      },
                      backgroundColor: isDark
                          ? NusaConfig.darkSurface2
                          : NusaConfig.backgroundColor,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

        // Input
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: isDark ? NusaConfig.darkSurface : Colors.white,
            border: Border(
              top: BorderSide(
                  color: isDark ? NusaConfig.darkDivider : NusaConfig.dividerColor),
            ),
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Tanya tentang NUSA Kasir...',
                      hintStyle: TextStyle(color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                      filled: true,
                      fillColor: isDark
                          ? NusaConfig.darkSurface2
                          : NusaConfig.backgroundColor,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _loading
                        ? NusaConfig.primaryColor.withValues(alpha: 0.3)
                        : NusaConfig.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _loading ? null : _send,
                    icon: Icon(_loading ? Icons.hourglass_top : Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubble(ChatMessage msg, bool isDark) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: NusaConfig.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome,
                  size: 16, color: NusaConfig.primaryColor),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? NusaConfig.primaryColor
                    : (isDark ? NusaConfig.darkSurface2 : NusaConfig.surfaceColor),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser
                    ? null
                    : Border.all(
                        color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
              ),
              child: SelectableText(
                msg.content,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: isUser
                      ? Colors.white
                      : (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: NusaConfig.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome,
                size: 16, color: NusaConfig.primaryColor),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? NusaConfig.darkSurface2 : NusaConfig.surfaceColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(
                  color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dot(isDark: isDark),
                const SizedBox(width: 4),
                _dot(delay: 200, isDark: isDark),
                const SizedBox(width: 4),
                _dot(delay: 400, isDark: isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot({int delay = 0, required bool isDark}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (_, val, __) => Opacity(
        opacity: val,
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m yg lalu';
    if (diff.inHours < 24) return '${diff.inHours}j yg lalu';
    if (diff.inDays < 7) return '${diff.inDays}h yg lalu';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
