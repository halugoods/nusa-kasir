import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/services/image_storage_service.dart';
import 'package:nusa_kasir/core/services/online_order_service.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';

class OnlineStoreSetupScreen extends ConsumerStatefulWidget {
  const OnlineStoreSetupScreen({super.key});
  @override
  ConsumerState<OnlineStoreSetupScreen> createState() =>
      _OnlineStoreSetupScreenState();
}

class _OnlineStoreSetupScreenState extends ConsumerState<OnlineStoreSetupScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _saving = false;
  String? _storeUrl;
  bool _isActive = false;
  String? _logoPath;
  int _onlineProductCount = 0;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _waCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController(text: '08:00 - 21:00');

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _waCtrl.dispose();
    _addressCtrl.dispose();
    _hoursCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  String _slugify(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  Future<void> _load() async {
    final key = await SecureStore.getActivation();
    if (key == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final repo = ref.read(settingsRepoProvider);
    final name = await repo.getStoreName();
    if (name.isNotEmpty) _nameCtrl.text = name;

    // Load store logo from local settings
    _logoPath = await repo.getStoreLogoPath();

    final fallbackSlug = _slugify(name);
    _storeUrl = 'https://nusa-online.vercel.app/toko/$fallbackSlug';

    // Count online products
    try {
      final db = ref.read(databaseProvider);
      final products = await ProductRepository(db).getProducts();
      _onlineProductCount = products.where((p) => p.isOnline).length;
    } catch (_) {}

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
        final cloudSlug = store['slug'] as String?;
        _storeUrl = 'https://nusa-online.vercel.app/toko/${cloudSlug ?? _slugify(_nameCtrl.text)}';
      }
    } catch (_) {}

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
      final slug = _slugify(name);
      final ok = await svc.upsertStore(
        storeName: name,
        slug: slug,
        description: _descCtrl.text.trim(),
        whatsapp: _waCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        openHours: _hoursCtrl.text.trim(),
        isActive: isActive,
      );

      if (ok) {
        await ref.read(settingsRepoProvider).setStoreName(name);
        _storeUrl = 'https://nusa-online.vercel.app/toko/$slug';

        if (isActive) await _syncProducts();

        if (mounted) {
          setState(() {
            _isActive = isActive;
            _storeUrl = 'https://nusa-online.vercel.app/toko/$slug';
          });
          TopToast.success(context, isActive
              ? 'Toko online diaktifkan! 🎉'
              : 'Pengaturan disimpan');
        }
      } else {
        if (mounted) {
          TopToast.error(context, 'Gagal menyimpan. Cek koneksi internet.');
        }
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
      debugPrint('[OnlineStoreSetup] Gagal sinkronisasi produk: $e');
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result == null || result.files.single.path == null) return;
    try {
      final src = File(result.files.single.path!);
      final dir = await getApplicationDocumentsDirectory();
      final ext = p.extension(src.path);
      final destName = 'store_logo_${DateTime.now().millisecondsSinceEpoch}$ext';
      final destPath = p.join(dir.path, destName);
      await src.copy(destPath);
      await ref.read(settingsRepoProvider).setStoreLogoPath(destPath);
      setState(() => _logoPath = destPath);

      // Cloud upload
      try {
        final uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid != null) {
          ImageStorageService(Supabase.instance.client, uid)
              .uploadImage('settings', destPath);
        }
      } catch (_) {}
    } catch (_) {
      if (mounted) TopToast.error(context, 'Gagal menyimpan logo');
    }
  }

  Future<void> _openPreview() async {
    if (_storeUrl == null || _storeUrl!.isEmpty) {
      if (mounted) TopToast.error(context, 'URL toko belum diatur.');
      return;
    }
    var uri = Uri.parse(_storeUrl!);
    if (!uri.hasScheme) uri = Uri.parse('https://$_storeUrl');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        TopToast.error(context, 'Tidak dapat membuka browser.');
      }
    } catch (_) {
      if (mounted) TopToast.error(context, 'Gagal membuka website');
    }
  }

  void _copyLink() {
    if (_storeUrl != null) {
      Clipboard.setData(ClipboardData(text: _storeUrl!));
      TopToast.success(context, 'Link disalin! 📋');
    }
  }

  void _shareLink() {
    if (_storeUrl != null) {
      final name = _nameCtrl.text.trim();
      Share.share(
        '🛒 $name\n\nPesan online di: $_storeUrl',
        subject: 'Toko Online $name',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary;
    final subColor = isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary;
    final cardBg = isDark ? NusaConfig.darkSurface : Colors.white;
    final borderC = isDark ? NusaConfig.darkBorder : NusaConfig.borderColor;

    if (_loading) {
      return const ScreenScaffold(
        'Toko Online',
        Center(child: CircularProgressIndicator()),
      );
    }

    return ScreenScaffold(
      'Toko Online',
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ═══════════════════════════════════════════════
            // STATUS CARD — Active/Inactive
            // ═══════════════════════════════════════════════
            _buildStatusCard(isDark),

            const SizedBox(height: 16),

            // ═══════════════════════════════════════════════
            // STORE PREVIEW MOCKUP
            // ═══════════════════════════════════════════════
            _buildStorePreview(isDark, textColor, subColor, cardBg, borderC),

            const SizedBox(height: 16),

            // ═══════════════════════════════════════════════
            // STORE INFO FORM
            // ═══════════════════════════════════════════════
            _buildStoreInfoForm(isDark, textColor, subColor, cardBg, borderC),

            const SizedBox(height: 16),

            // ═══════════════════════════════════════════════
            // PRODUCTS CARD
            // ═══════════════════════════════════════════════
            _buildProductsCard(isDark, textColor, subColor, cardBg, borderC),

            const SizedBox(height: 20),

            // ═══════════════════════════════════════════════
            // ACTIVATION TOGGLE
            // ═══════════════════════════════════════════════
            _buildActivationToggle(isDark, textColor, subColor, cardBg, borderC),

            const SizedBox(height: 24),

            // ═══════════════════════════════════════════════
            // SAVE BUTTON
            // ═══════════════════════════════════════════════
            NusaButton(
              _saving ? 'Menyimpan...' : '💾 Simpan Semua',
              onPressed: _saving ? null : () => _save(),
            ),
            const SizedBox(height: 12),

            // Help text
            Text(
              'Produk yang dicentang "Tampil di Toko Online" saat edit produk '
              'akan otomatis muncul di website toko kamu.',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Status Card
  // ─────────────────────────────────────────────────────────
  Widget _buildStatusCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: _isActive
            ? const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF047857)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: isDark
                    ? [const Color(0xFF374151), const Color(0xFF1F2937)]
                    : [const Color(0xFF9CA3AF), const Color(0xFF6B7280)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        boxShadow: _isActive
            ? [
                BoxShadow(
                  color: const Color(0xFF059669).withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          // Icon with glowing dot
          Stack(
            alignment: Alignment.topRight,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isActive ? Icons.store : Icons.store_outlined,
                  size: 28,
                  color: Colors.white,
                ),
              ),
              if (_isActive)
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) => Opacity(
                    opacity: _pulseAnim.value,
                    child: Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF4ADE80),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4ADE80).withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isActive)
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) => Opacity(
                    opacity: _pulseAnim.value,
                    child: Container(
                      width: 8, height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF4ADE80),
                      ),
                    ),
                  ),
                ),
              Text(
                _isActive ? 'Toko Online Kamu Aktif' : 'Toko Online Nonaktif',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _isActive
                ? 'Pelanggan bisa langsung order via web kamu! 🎉'
                : 'Lengkapi info di bawah & aktifkan untuk mulai jualan online',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Store Preview Mockup
  // ─────────────────────────────────────────────────────────
  Widget _buildStorePreview(
    bool isDark, Color textColor, Color subColor, Color cardBg, Color borderC,
  ) {
    final name = _nameCtrl.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.preview, size: 18, color: textColor),
          const SizedBox(width: 8),
          Text('Tampilan Toko', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
          if (_isActive && _storeUrl != null) ...[
            const Spacer(),
            GestureDetector(
              onTap: () async {
                try {
                  await launchUrl(Uri.parse(_storeUrl!), mode: LaunchMode.externalApplication);
                } catch (_) {}
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_in_browser, size: 14, color: Color(0xFF059669)),
                    SizedBox(width: 4),
                    Text('Buka Website', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF059669))),
                  ],
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),

        // Store info card (compact)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? NusaConfig.darkSurface2 : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderC),
          ),
          child: Column(
            children: [
              if (_logoPath != null && _logoPath!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(File(_logoPath!), height: 56, fit: BoxFit.contain),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: isDark ? NusaConfig.darkSurface : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.store, size: 28, color: isDark ? NusaConfig.darkTextSecondary : const Color(0xFF9CA3AF)),
                  ),
                ),
              Text(
                name.isNotEmpty ? name : 'Nama Toko Kamu',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textColor),
                textAlign: TextAlign.center,
              ),
              if (_descCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_descCtrl.text.trim(),
                    style: TextStyle(fontSize: 12, color: subColor),
                    textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _isActive ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _isActive ? '🟢 Buka' : '🔴 Tutup',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _isActive ? const Color(0xFF059669) : const Color(0xFFE63946),
                  ),
                ),
              ),
              if (_hoursCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.access_time, size: 13, color: subColor),
                  const SizedBox(width: 4),
                  Text(_hoursCtrl.text.trim(), style: TextStyle(fontSize: 12, color: subColor)),
                ]),
              ],
              if (_addressCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.location_on, size: 13, color: subColor),
                  const SizedBox(width: 4),
                  Flexible(child: Text(_addressCtrl.text.trim(),
                      style: TextStyle(fontSize: 12, color: subColor),
                      overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // Store Info Form
  // ─────────────────────────────────────────────────────────
  Widget _buildStoreInfoForm(
    bool isDark, Color textColor, Color subColor, Color cardBg, Color borderC,
  ) {
    return NusaCard(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.edit_note, size: 18, color: textColor),
          const SizedBox(width: 8),
          Text('Info Toko', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
        ]),
        const SizedBox(height: 16),

        // ── Logo ──
        Row(children: [
          GestureDetector(
            onTap: _pickLogo,
            child: Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: isDark ? NusaConfig.darkSurface2 : NusaConfig.surfaceColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderC, width: 1.5),
              ),
              child: _logoPath != null && _logoPath!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(_logoPath!), fit: BoxFit.cover),
                    )
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add_photo_alternate, size: 24, color: subColor),
                      const SizedBox(height: 2),
                      Text('Logo', style: TextStyle(fontSize: 8, color: subColor)),
                    ]),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Logo Toko', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                const SizedBox(height: 2),
                Text('Tampil di halaman toko & preview',
                    style: TextStyle(fontSize: 11, color: subColor)),
                const SizedBox(height: 6),
                Row(children: [
                  TextButton.icon(
                    onPressed: _pickLogo,
                    icon: const Icon(Icons.upload, size: 16),
                    label: Text(_logoPath != null ? 'Ganti' : 'Upload', style: const TextStyle(fontSize: 12)),
                  ),
                  if (_logoPath != null)
                    TextButton.icon(
                      onPressed: () {
                        ref.read(settingsRepoProvider).setStoreLogoPath('');
                        setState(() => _logoPath = null);
                      },
                      icon: const Icon(Icons.delete, size: 16, color: Colors.redAccent),
                      label: const Text('Hapus', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                    ),
                ]),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 16),

        NusaInput('Nama Toko *', controller: _nameCtrl,
            hint: 'Cth: Toko Berkah Jaya', prefixIcon: const Icon(Icons.store)),
        const SizedBox(height: 12),

        // Deskripsi
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Deskripsi Singkat', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: isDark ? NusaConfig.darkSurface2 : NusaConfig.surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderC),
              ),
              child: TextField(
                controller: _descCtrl, maxLines: 2,
                style: TextStyle(fontSize: 14, color: textColor),
                decoration: InputDecoration(
                  hintText: 'Jelaskan toko kamu dalam 1-2 kalimat...',
                  hintStyle: TextStyle(fontSize: 13, color: subColor),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Row(children: [
          Expanded(
            child: NusaInput('WhatsApp', controller: _waCtrl,
                hint: '08xxxxxxxxxx', prefixIcon: const Icon(Icons.phone_android)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: NusaInput('Jam Buka', controller: _hoursCtrl,
                hint: '08:00 - 21:00', prefixIcon: const Icon(Icons.access_time)),
          ),
        ]),
        const SizedBox(height: 14),
        NusaInput('Alamat', controller: _addressCtrl,
            hint: 'Jl. ... (opsional)', prefixIcon: const Icon(Icons.location_on_outlined)),
      ],
    ));
  }

  // ─────────────────────────────────────────────────────────
  // Products Card
  // ─────────────────────────────────────────────────────────
  Widget _buildProductsCard(
    bool isDark, Color textColor, Color subColor, Color cardBg, Color borderC,
  ) {
    return NusaCard(Row(children: [
      Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.inventory_2, size: 22, color: Color(0xFFF59E0B)),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Produk Online', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
            const SizedBox(height: 2),
            Text(
              _onlineProductCount > 0
                  ? '$_onlineProductCount produk siap tampil di website'
                  : 'Belum ada produk online. Tandai produk saat edit.',
              style: TextStyle(fontSize: 12, color: subColor),
            ),
          ],
        ),
      ),
      // Sync button
      if (_isActive)
        TextButton(
          onPressed: _saving ? null : () async {
            setState(() => _saving = true);
            await _syncProducts();
            try {
              final db = ref.read(databaseProvider);
              final products = await ProductRepository(db).getProducts();
              if (mounted) setState(() {
                _onlineProductCount = products.where((p) => p.isOnline).length;
              });
            } catch (_) {}
            if (mounted) {
              TopToast.success(context, '$_onlineProductCount produk disinkronkan!');
              setState(() => _saving = false);
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFF59E0B),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: const Text('Sinkronkan', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
    ]));
  }

  // ─────────────────────────────────────────────────────────
  // Activation Toggle
  // ─────────────────────────────────────────────────────────
  Widget _buildActivationToggle(
    bool isDark, Color textColor, Color subColor, Color cardBg, Color borderC,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isActive
            ? const Color(0xFF059669).withValues(alpha: 0.06)
            : cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isActive
              ? const Color(0xFF059669).withValues(alpha: 0.25)
              : borderC,
        ),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: _isActive
                ? const Color(0xFF059669).withValues(alpha: 0.15)
                : NusaConfig.primarySoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _isActive ? Icons.toggle_on : Icons.toggle_off,
            size: 24,
            color: _isActive ? const Color(0xFF059669) : NusaConfig.primaryColor,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isActive ? 'Toko Online Aktif' : 'Aktifkan Toko Online',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
              ),
              const SizedBox(height: 2),
              Text(
                _isActive
                    ? 'Pelanggan bisa melihat & order di website'
                    : 'Produk dengan centang "Online" akan tampil',
                style: TextStyle(fontSize: 12, color: subColor),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: _isActive,
          activeColor: const Color(0xFF059669),
          activeTrackColor: const Color(0xFF059669).withValues(alpha: 0.3),
          onChanged: (v) {
            setState(() => _isActive = v);
            _save(activate: v);
          },
        ),
      ]),
    );
  }
}
