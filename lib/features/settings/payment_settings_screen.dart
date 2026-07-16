import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';

class PaymentSettingsScreen extends ConsumerStatefulWidget {
  const PaymentSettingsScreen({super.key});
  @override
  ConsumerState<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends ConsumerState<PaymentSettingsScreen> {
  final _qrisCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _bankHolderCtrl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final repo = ref.read(settingsRepoProvider);
    final qris = await repo.getQris();
    final bankName = await repo.getBankName();
    final bankAccount = await repo.getBankAccount();
    final bankHolder = await repo.getBankHolder();
    _qrisCtrl.text = qris ?? '';
    _bankNameCtrl.text = bankName ?? '';
    _bankAccountCtrl.text = bankAccount ?? '';
    _bankHolderCtrl.text = bankHolder ?? '';
  }

  @override
  void dispose() {
    _qrisCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankAccountCtrl.dispose();
    _bankHolderCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveQris() async {
    setState(() => _loading = true);
    try {
      await ref.read(settingsRepoProvider).setQris(_qrisCtrl.text.trim());
      if (mounted) TopToast.success(context, 'QRIS disimpan ✅');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveBank() async {
    setState(() => _loading = true);
    try {
      await ref.read(settingsRepoProvider).setBankInfo(
        name: _bankNameCtrl.text.trim(),
        account: _bankAccountCtrl.text.trim(),
        holder: _bankHolderCtrl.text.trim(),
      );
      if (mounted) TopToast.success(context, 'Info rekening disimpan ✅');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final qris = _qrisCtrl.text.trim();

    return ScreenScaffold(
      'Pembayaran',
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── QRIS Section ──
            _sectionHeader('QRIS', Icons.qr_code_2, const Color(0xFF6366F1)),
            NusaCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('QRIS String',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('Masukkan string QRIS dari penyedia pembayaran Anda (contoh: QRIS, Gopay, dll)',
                      style: TextStyle(fontSize: 12, color: NusaConfig.textSecondary)),
                  const SizedBox(height: 12),
                  NusaInput('QRIS string', controller: _qrisCtrl),
                  if (qris.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
                        ),
                        child: QrImageView(data: qris, version: QrVersions.auto, size: 150),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  NusaButton('Simpan QRIS', onPressed: _loading ? null : _saveQris),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Bank Transfer Section ──
            _sectionHeader('TRANSFER BANK', Icons.account_balance, const Color(0xFF6366F1)),
            NusaCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Informasi Rekening',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('Data rekening bank untuk pembayaran via transfer',
                      style: TextStyle(fontSize: 12, color: NusaConfig.textSecondary)),
                  const SizedBox(height: 14),
                  NusaInput('Nama bank (contoh: BCA)', controller: _bankNameCtrl),
                  const SizedBox(height: 12),
                  NusaInput('Nomor rekening', controller: _bankAccountCtrl,
                      type: TextInputType.number),
                  const SizedBox(height: 12),
                  NusaInput('Atas nama', controller: _bankHolderCtrl),
                  const SizedBox(height: 16),
                  // Preview card
                  if (_bankNameCtrl.text.isNotEmpty || _bankAccountCtrl.text.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? NusaConfig.darkSurface2 : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.account_balance, size: 20, color: Color(0xFF6366F1)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_bankNameCtrl.text.isNotEmpty)
                                  Text(_bankNameCtrl.text,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                if (_bankAccountCtrl.text.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(_bankAccountCtrl.text,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                                          fontFamily: 'monospace', letterSpacing: 1)),
                                ],
                                if (_bankHolderCtrl.text.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text('a.n. ${_bankHolderCtrl.text}',
                                      style: const TextStyle(fontSize: 12, color: NusaConfig.textSecondary)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  NusaButton('Simpan Rekening', onPressed: _loading ? null : _saveBank),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: NusaConfig.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
