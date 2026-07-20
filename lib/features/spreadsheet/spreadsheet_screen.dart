import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/services/spreadsheet_service.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import "package:nusa_kasir/shared/widgets/top_toast.dart";
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
  bool _syncing = false;
  String _syncingTab = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = SpreadsheetService(ref.read(databaseProvider));
    final tokens = await SecureStore.getSheetsTokens();
    if (tokens != null && tokens.isNotEmpty) {
      setState(() => _spreadsheetId = tokens);
    }
    final user = _svc!.isSignedIn;
    if (mounted && !user) {
      // try silent re-auth later
      setState(() {});
    }
  }

  Future<void> _signIn() async {
    final account = await _svc!.signIn();
    if (account != null && mounted) {
      setState(() {
        _userEmail = account.email;
      });
    }
  }

  Future<void> _signOut() async {
    await _svc!.signOut();
    await SecureStore.clearSheetsTokens();
    if (mounted) {
      setState(() {
        _userEmail = '';
        _spreadsheetId = null;
      });
    }
  }

  Future<void> _createSheet() async {
    final id = await _svc!.findOrCreate('NUSA Kasir');
    if (id != null && mounted) {
      await SecureStore.saveSheetsTokens(id);
      setState(() => _spreadsheetId = id);
      TopToast.success(context, 'Spreadsheet berhasil dibuat!');
    } else if (mounted) {
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
        case 'Produk':
          ok = await _svc!.syncProducts(_spreadsheetId!);
          break;
        case 'Transaksi':
          ok = await _svc!.syncTransactions(_spreadsheetId!);
          break;
        case 'Stok':
          ok = await _svc!.syncStock(_spreadsheetId!);
          break;
        case 'Laporan':
          ok = await _svc!.syncLaporan(_spreadsheetId!);
          break;
      }
    } catch (_) {
      ok = false;
    }
    if (mounted) {
      setState(() {
        _syncing = false;
        _syncingTab = '';
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
    });
    final ok = await _svc!.syncAll(_spreadsheetId!);
    if (mounted) {
      setState(() {
        _syncing = false;
        _syncingTab = '';
      });
      if (ok) {
        TopToast.success(context, 'Semua data tersinkronisasi');
      } else {
        TopToast.error(context, 'Gagal sinkronisasi');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ScreenScaffold(
      'Spreadsheet',
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Status card
            NusaCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Status Koneksi',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        _userEmail.isNotEmpty ? Icons.check_circle : Icons.cancel,
                        color: _userEmail.isNotEmpty ? Colors.green : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _userEmail.isNotEmpty
                              ? 'Terhubung sebagai $_userEmail'
                              : 'Belum terhubung ke Google',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Action buttons
            if (_userEmail.isEmpty) ...[
              SizedBox(
                width: double.infinity,
                child: NusaButton('Hubungkan Google Sheets',
                  onPressed: _signIn,
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Putuskan Koneksi'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NusaConfig.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Spreadsheet ID status
              NusaCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Spreadsheet',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _spreadsheetId != null
                                ? 'Spreadsheet terhubung'
                                : 'Belum ada spreadsheet',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        if (_spreadsheetId != null)
                          Icon(Icons.check_circle, color: Colors.green, size: 20)
                        else
                          Icon(Icons.info_outline, color: isDark ? NusaConfig.darkTextSecondary : Colors.grey, size: 20),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_spreadsheetId == null)
                      SizedBox(
                        width: double.infinity,
                        child: NusaButton('Buat Spreadsheet Baru',
                          onPressed: _createSheet,
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _createSheet,
                          icon: const Icon(Icons.add),
                          label: const Text('Buat Spreadsheet Baru'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Sync sections
              if (_spreadsheetId != null) ...[
                const Text('Sinkronisasi Data',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 12),
                _syncTile('Produk', Icons.inventory_2_outlined, isDark: isDark),
                const SizedBox(height: 8),
                _syncTile('Transaksi', Icons.receipt_long_outlined, isDark: isDark),
                const SizedBox(height: 8),
                _syncTile('Stok', Icons.view_module_outlined, isDark: isDark),
                const SizedBox(height: 8),
                _syncTile('Laporan', Icons.paid_outlined, isDark: isDark),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: NusaButton(
                    _syncing && _syncingTab == 'Semua'
                        ? 'Menyinkronkan...'
                        : 'Sync Semua',
                    onPressed: (_syncing) ? null : _syncAll,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _syncTile(String label, IconData icon, {required bool isDark}) {
    final isActive = _syncing && _syncingTab == label;
    return NusaCard(
      InkWell(
        onTap: (_syncing) ? null : () => _syncTab(label),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: NusaConfig.primaryColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              if (isActive)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.sync, color: isDark ? NusaConfig.darkTextSecondary : Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
