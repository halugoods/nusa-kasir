import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/services/spreadsheet_service.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';

class SpreadsheetScreen extends ConsumerStatefulWidget {
  const SpreadsheetScreen({super.key});
  @override
  ConsumerState<SpreadsheetScreen> createState() => _SpreadsheetScreenState();
}

class _SpreadsheetScreenState extends ConsumerState<SpreadsheetScreen> {
  SpreadsheetService? _svc;
  String? _spreadsheetId;
  String _userEmail = '';
  bool _connecting = false;
  bool _syncing = false;
  String _syncingTab = '';
  final Map<String, DateTime?> _lastSync = {};
  int _syncedCount = 0;
  int _totalCount = 0;

  // All tabs (10 total)
  static const _allTabs = [
    'Produk', 'Transaksi', 'Stok', 'Laporan', 'Keuangan',
    'Karyawan', 'Pelanggan', 'Supplier', 'Promo', 'Presensi',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = SpreadsheetService(ref.read(databaseProvider));
    // Try restore previous session
    final savedEmail = await SecureStore.getSheetsEmail();
    final savedSheetId = await SecureStore.getSheetsId();

    if (savedEmail != null) {
      setState(() {
        _userEmail = savedEmail;
        _spreadsheetId = savedSheetId;
      });
      // Silent sign-in to refresh token
      final account = await _svc!.signInSilently();
      if (account != null && mounted) {
        setState(() => _userEmail = account.email);
      }
    }
  }

  Future<void> _signIn() async {
    setState(() => _connecting = true);
    final account = await _svc!.signIn();
    if (account != null && mounted) {
      final email = account.email;
      await SecureStore.saveSheetsEmail(email);
      setState(() {
        _userEmail = email;
        _connecting = false;
      });
      // Auto-try find/create spreadsheet
      await _autoFindSheet(email);
    } else {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _autoFindSheet(String email) async {
    // Try restore existing spreadsheet ID
    final savedId = await SecureStore.getSheetsId();
    if (savedId != null && savedId.isNotEmpty) {
      setState(() => _spreadsheetId = savedId);
      return;
    }
    // Auto-create new spreadsheet
    await _createSheet();
  }

  Future<void> _signOut() async {
    await _svc!.signOut();
    await SecureStore.clearSheetsTokens();
    await SecureStore.clearSheetsEmail();
    await SecureStore.clearSheetsId();
    if (mounted) {
      setState(() {
        _userEmail = '';
        _spreadsheetId = null;
        _lastSync.clear();
      });
    }
  }

  Future<void> _createSheet() async {
    final email = _userEmail;
    if (email.isEmpty) return;
    setState(() => _connecting = true);
    final id = await _svc!.findOrCreate(email);
    if (id != null && mounted) {
      await SecureStore.saveSheetsId(id);
      setState(() {
        _spreadsheetId = id;
        _connecting = false;
      });
      TopToast.success(context, 'Spreadsheet dibuat — otomatis sinkron semua data...');
      // Auto-sync all after create
      _syncAll();
    } else if (mounted) {
      setState(() => _connecting = false);
      TopToast.error(context, 'Gagal membuat spreadsheet');
    }
  }

  Future<void> _syncTab(String tab) async {
    if (_spreadsheetId == null || _svc == null) return;
    setState(() {
      _syncing = true;
      _syncingTab = tab;
    });
    bool ok = false;
    try {
      switch (tab) {
        case 'Produk':    ok = await _svc!.syncProducts(_spreadsheetId!); break;
        case 'Transaksi': ok = await _svc!.syncTransactions(_spreadsheetId!); break;
        case 'Stok':      ok = await _svc!.syncStock(_spreadsheetId!); break;
        case 'Laporan':   ok = await _svc!.syncLaporan(_spreadsheetId!); break;
        case 'Keuangan':  ok = await _svc!.syncKeuangan(_spreadsheetId!); break;
        case 'Karyawan':  ok = await _svc!.syncKaryawan(_spreadsheetId!); break;
        case 'Pelanggan': ok = await _svc!.syncPelanggan(_spreadsheetId!); break;
        case 'Supplier':  ok = await _svc!.syncSupplier(_spreadsheetId!); break;
        case 'Promo':     ok = await _svc!.syncPromo(_spreadsheetId!); break;
        case 'Presensi':  ok = await _svc!.syncPresensi(_spreadsheetId!); break;
      }
    } catch (_) {
      ok = false;
    }
    if (mounted) {
      setState(() {
        _syncing = false;
        _syncingTab = '';
        if (ok) _lastSync[tab] = DateTime.now();
      });
      if (ok) {
        TopToast.success(context, '$tab tersinkronisasi');
      } else {
        TopToast.error(context, 'Gagal sinkron $tab');
      }
    }
  }

  Future<void> _syncAll() async {
    if (_spreadsheetId == null || _svc == null) return;
    setState(() {
      _syncing = true;
      _syncingTab = 'Semua';
      _syncedCount = 0;
      _totalCount = _allTabs.length;
    });
    bool allOk = true;
    for (var i = 0; i < _allTabs.length; i++) {
      final tab = _allTabs[i];
      bool ok = false;
      try {
        switch (tab) {
          case 'Produk':    ok = await _svc!.syncProducts(_spreadsheetId!); break;
          case 'Transaksi': ok = await _svc!.syncTransactions(_spreadsheetId!); break;
          case 'Stok':      ok = await _svc!.syncStock(_spreadsheetId!); break;
          case 'Laporan':   ok = await _svc!.syncLaporan(_spreadsheetId!); break;
          case 'Keuangan':  ok = await _svc!.syncKeuangan(_spreadsheetId!); break;
          case 'Karyawan':  ok = await _svc!.syncKaryawan(_spreadsheetId!); break;
          case 'Pelanggan': ok = await _svc!.syncPelanggan(_spreadsheetId!); break;
          case 'Supplier':  ok = await _svc!.syncSupplier(_spreadsheetId!); break;
          case 'Promo':     ok = await _svc!.syncPromo(_spreadsheetId!); break;
          case 'Presensi':  ok = await _svc!.syncPresensi(_spreadsheetId!); break;
        }
      } catch (_) {
        ok = false;
      }
      if (ok) {
        if (mounted) _lastSync[tab] = DateTime.now();
      } else {
        allOk = false;
      }
      if (mounted) setState(() => _syncedCount = i + 1);
    }
    if (mounted) {
      setState(() {
        _syncing = false;
        _syncingTab = '';
      });
      if (allOk) {
        TopToast.success(context, 'Semua data tersinkronisasi!');
      } else {
        TopToast.error(context, 'Sebagian gagal sinkronisasi');
      }
    }
  }

  String _lastSyncText(String tab) {
    final dt = _lastSync[tab];
    if (dt == null) return 'Belum';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m lalu';
    if (diff.inHours < 24) return '${diff.inHours}j lalu';
    return '${diff.inDays}h lalu';
  }

  // Icons per tab
  static const _tabIcons = {
    'Produk': Icons.inventory_2_outlined,
    'Transaksi': Icons.receipt_long_outlined,
    'Stok': Icons.view_module_outlined,
    'Laporan': Icons.paid_outlined,
    'Keuangan': Icons.account_balance_wallet_outlined,
    'Karyawan': Icons.people_outline,
    'Pelanggan': Icons.person_outline,
    'Supplier': Icons.local_shipping_outlined,
    'Promo': Icons.discount_outlined,
    'Presensi': Icons.fingerprint_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPri = isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary;
    final textTer = isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary;

    return ScreenScaffold(
      'Spreadsheet',
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // ── Status koneksi ──
          NusaCard(Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: _userEmail.isNotEmpty
                      ? NusaConfig.accentGreen.withValues(alpha: 0.12)
                      : NusaConfig.textTertiary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _userEmail.isNotEmpty ? Icons.check_circle_rounded : Icons.cloud_off_rounded,
                  color: _userEmail.isNotEmpty ? NusaConfig.accentGreen : NusaConfig.textTertiary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_userEmail.isNotEmpty ? 'Terhubung' : 'Belum Terhubung',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPri)),
                  const SizedBox(height: 2),
                  Text(
                    _userEmail.isNotEmpty ? _userEmail : 'Login Google untuk sinkronisasi',
                    style: TextStyle(fontSize: 12, color: textTer),
                  ),
                ]),
              ),
            ]),
          )),
          const SizedBox(height: 16),

          // ── Not connected → Login button ──
          if (_userEmail.isEmpty) ...[
            SizedBox(
              width: double.infinity,
              child: NusaButton(
                _connecting ? 'Menghubungkan...' : 'Login dengan Google',
                onPressed: _connecting ? null : _signIn,
              ),
            ),
            const SizedBox(height: 12),
            Text('Data akan otomatis tersimpan di Google Sheets akun Anda',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: textTer)),
          ]

          // ── Connected ──
          else ...[
            // Spreadsheet status card
            NusaCard(Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: _spreadsheetId != null
                          ? NusaConfig.accentGreen.withValues(alpha: 0.12)
                          : NusaConfig.accentPurple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _spreadsheetId != null ? Icons.description_outlined : Icons.add_to_drive,
                      color: _spreadsheetId != null ? NusaConfig.accentGreen : NusaConfig.accentPurple,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_spreadsheetId != null ? 'Spreadsheet Aktif' : 'Belum Ada Spreadsheet',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPri)),
                      const SizedBox(height: 2),
                      Text(
                        _spreadsheetId != null ? 'Semua data siap disinkronkan' : 'Satu klik untuk membuat',
                        style: TextStyle(fontSize: 12, color: textTer),
                      ),
                    ]),
                  ),
                ]),
                if (_spreadsheetId == null && !_connecting) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: NusaButton('Buat Spreadsheet Baru', onPressed: _createSheet),
                  ),
                ],
              ]),
            )),
            const SizedBox(height: 20),

            // ── Sync section ──
            if (_spreadsheetId != null) ...[
              Row(children: [
                Expanded(
                  child: Text('Sinkronisasi Data', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPri)),
                ),
                if (_syncing && _syncingTab == 'Semua')
                  Text('$_syncedCount / $_totalCount', style: TextStyle(fontSize: 13, color: textTer)),
              ]),
              const SizedBox(height: 8),

              // Progress bar for sync all
              if (_syncing && _syncingTab == 'Semua') ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _totalCount > 0 ? _syncedCount / _totalCount : 0,
                      backgroundColor: isDark ? NusaConfig.darkDivider : NusaConfig.dividerColor,
                      valueColor: const AlwaysStoppedAnimation(NusaConfig.accentGreen),
                      minHeight: 6,
                    ),
                  ),
                ),
              ],

              // Tab list
              ..._allTabs.map((tab) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _syncTile(tab, _tabIcons[tab] ?? Icons.sync, isDark: isDark),
              )),

              const SizedBox(height: 16),
              // Sync All button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _syncing ? null : _syncAll,
                  icon: _syncing && _syncingTab == 'Semua'
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync_rounded, size: 18),
                  label: Text(_syncing && _syncingTab == 'Semua' ? 'Menyinkronkan...' : 'Sync Semua Data'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NusaConfig.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            // Sign out
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Putuskan Koneksi'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: NusaConfig.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _syncTile(String label, IconData icon, {required bool isDark}) {
    final isActive = _syncing && _syncingTab == label;
    final textPri = isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary;
    final textTer = isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary;
    final surf = isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor;
    final border = isDark ? NusaConfig.darkBorder : NusaConfig.borderColor;

    return Container(
      decoration: BoxDecoration(
        color: surf,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: (_syncing) ? null : () => _syncTab(label),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: NusaConfig.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: NusaConfig.primaryColor, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPri)),
                  const SizedBox(height: 1),
                  Text('Terakhir: ${_lastSyncText(label)}',
                      style: TextStyle(fontSize: 11, color: textTer)),
                ]),
              ),
              if (isActive)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: NusaConfig.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.sync_rounded, size: 15, color: NusaConfig.primaryColor),
                    const SizedBox(width: 4),
                    Text('Sync', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: NusaConfig.primaryColor)),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
