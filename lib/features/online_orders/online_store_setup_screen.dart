import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/services/online_order_service.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class OnlineStoreSetupScreen extends ConsumerStatefulWidget {
  const OnlineStoreSetupScreen({super.key});
  @override
  ConsumerState<OnlineStoreSetupScreen> createState() => _OnlineStoreSetupScreenState();
}

class _OnlineStoreSetupScreenState extends ConsumerState<OnlineStoreSetupScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _storeId;
  String? _storeUrl;
  bool _isActive = false;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _waCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController(text: '08:00 - 21:00');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _waCtrl.dispose();
    _addressCtrl.dispose();
    _hoursCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = await SecureStore.getActivation();
    if (key == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    _storeId = key;
    _storeUrl = 'https://nusa-online.vercel.app/toko/$key';

    // Load store name from local settings
    final repo = ref.read(settingsRepoProvider);
    final name = await repo.getStoreName();
    if (name.isNotEmpty) _nameCtrl.text = name;

    // Load from Supabase
    try {
      final svc = OnlineOrderService(Supabase.instance.client);
      final store = await svc.getStoreSettings();
      if (store != null) {
        _isActive = store['is_active'] == true;
        _nameCtrl.text = store['store_name'] as String? ?? _nameCtrl.text;
        _descCtrl.text = store['description'] as String? ?? '';
        _waCtrl.text = store['whatsapp'] as String? ?? '';
        _addressCtrl.text = store['address'] as String? ?? '';
        _hoursCtrl.text = store['open_hours'] as String? ?? '08:00 - 21:00';
      }
    } catch (e) {
      // ignore: avoid_print
      print('[OnlineStoreSetup] Gagal memuat data Supabase: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save({bool? activate}) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      TopToast.error(context, 'Nama toko wajib diisi');
      return;
    }

    setState(() => _saving = true);

    final isActive = activate ?? _isActive;

    try {
      final svc = OnlineOrderService(Supabase.instance.client);
      final ok = await svc.upsertStore(
        storeName: name,
        description: _descCtrl.text.trim(),
        whatsapp: _waCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        openHours: _hoursCtrl.text.trim(),
        isActive: isActive,
      );

      if (ok) {
        // Also save store name locally
        await ref.read(settingsRepoProvider).setStoreName(name);

        // If activating, sync all online products
        if (isActive) {
          await _syncProducts();
        }

        if (mounted) {
          setState(() => _isActive = isActive);
          TopToast.success(context, isActive
              ? 'Toko online diaktifkan! 🎉'
              : 'Pengaturan disimpan');
        }
      } else {
        if (mounted) TopToast.error(context, 'Gagal menyimpan. Cek koneksi internet.');
      }
    } catch (e) {
      if (mounted) TopToast.error(context, 'Error: $e');
    }

    if (mounted) setState(() => _saving = false);
  }

  Future<void> _syncProducts() async {
    try {
      final db = ref.read(databaseProvider);
      final products = await ProductRepository(db).getProducts();
      final onlineProducts = products
          .where((p) => p.isOnline)
          .map((p) => {
                'product_id': p.id,
                'name': p.name,
                'category': p.category,
                'price': p.sellPrice,
                'stock': p.stock,
                'image': p.imagePath ?? '',
                'description': '',
                'is_published': true,
              })
          .toList();

      if (onlineProducts.isNotEmpty) {
        final svc = OnlineOrderService(Supabase.instance.client);
        await svc.syncProducts(onlineProducts);
      }
    } catch (e) {
      // ignore: avoid_print
      print('[OnlineStoreSetup] Gagal sinkronisasi produk: $e');
    }
  }

  Future<void> _shareLink() async {
    if (_storeUrl == null) return;
    final message = '🛒 Pesan online dari ${_nameCtrl.text.trim()}!\n\n$_storeUrl';
    await Share.share(message, subject: 'Toko Online ${_nameCtrl.text.trim()}');
  }

  Future<void> _openPreview() async {
    if (_storeUrl == null) return;
    final uri = Uri.parse(_storeUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _textarea(String label, TextEditingController ctrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: 2,
          style: TextStyle(fontSize: 15, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: isDark ? NusaConfig.darkSurface2 : NusaConfig.surfaceColor,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScreenScaffold(
      'Toko Online',
      _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status banner
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: _isActive
                          ? const LinearGradient(colors: [NusaConfig.accentGreen, NusaConfig.accentGreenDark])
                          : const LinearGradient(colors: [NusaConfig.textSecondary, NusaConfig.textTertiary]),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _isActive ? '🟢 Toko Online Aktif' : '⚪ Toko Online Nonaktif',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isActive
                              ? 'Pelanggan sudah bisa memesan via link di bawah ini'
                              : 'Lengkapi info toko & aktifkan untuk mulai',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Store link (only visible when active)
                  if (_isActive && _storeUrl != null) ...[
                    NusaCard(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🔗 Link Toko Online',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? NusaConfig.darkSurface2 : NusaConfig.backgroundColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: NusaConfig.primaryColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _storeUrl!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontFamily: 'monospace',
                                      color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: NusaButton('📋 Salin Link',
                                    fullWidth: true,
                                    onPressed: () => _shareLink()),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _openPreview,
                                  icon: const Icon(Icons.open_in_browser, size: 18),
                                  label: const Text('Preview'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: NusaConfig.primaryColor,
                                    side: const BorderSide(color: NusaConfig.primaryColor),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Store info form
                  NusaCard(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Info Toko',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        const SizedBox(height: 12),
                        NusaInput('Nama Toko *', controller: _nameCtrl),
                        const SizedBox(height: 12),
                        _textarea('Deskripsi singkat', _descCtrl),
                        const SizedBox(height: 12),
                        NusaInput('Nomor WhatsApp untuk order', controller: _waCtrl,
                            hint: '08xx, untuk konfirmasi pesanan'),
                        const SizedBox(height: 12),
                        NusaInput('Alamat (opsional)', controller: _addressCtrl,
                            hint: 'Jl. ...'),
                        const SizedBox(height: 12),
                        NusaInput('Jam Buka', controller: _hoursCtrl,
                            hint: '08:00 - 21:00'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Toggle activation
                  NusaCard(
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isActive ? 'Nonaktifkan Toko' : 'Aktifkan Toko Online',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isActive
                                    ? 'Toko tidak akan muncul di web'
                                    : 'Produk dg centang Online akan tampil',
                                style: const TextStyle(fontSize: 12, color: NusaConfig.textTertiary),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isActive,
                          activeColor: NusaConfig.accentGreen,
                          onChanged: (v) {
                            setState(() => _isActive = v);
                            _save(activate: v);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sync products button
                  if (_isActive) ...[
                    NusaButton('🔄 Sinkronkan Produk Sekarang',
                        onPressed: _saving ? null : () async {
                          setState(() => _saving = true);
                          await _syncProducts();
                          if (mounted) {
                            TopToast.success(context, 'Produk disinkronkan!');
                            setState(() => _saving = false);
                          }
                        }),
                    const SizedBox(height: 8),
                    Text(
                      'Produk yang dicentang "Tampil di Toko Online" saat edit produk akan muncul di website.',
                      style: const TextStyle(fontSize: 11, color: NusaConfig.textTertiary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
