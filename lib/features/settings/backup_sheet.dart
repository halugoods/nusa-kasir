import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/core/providers.dart';
import "package:nusa_kasir/shared/widgets/top_toast.dart";
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void showBackupSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    builder: (_) => _BackupSheetBody(rootContext: context, ref: ref),
  );
}

class _BackupSheetBody extends StatelessWidget {
  final BuildContext rootContext;
  final WidgetRef ref;
  const _BackupSheetBody({required this.rootContext, required this.ref});

  Future<String> _dbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'nusa_kasir.sqlite');
  }

  Future<void> _backup(BuildContext ctx) async {
    try {
      final src = File(await _dbPath());
      if (!await src.exists()) {
        if (ctx.mounted) TopToast.error(ctx, 'Database tidak ditemukan');
        return;
      }
      final outDir = await getTemporaryDirectory();
      final ts = DateTime.now();
      final name =
          'nusa_kasir_backup_${ts.year}${ts.month}${ts.day}_${ts.hour}${ts.minute}.sqlite';
      final out = File(p.join(outDir.path, name));
      await src.copy(out.path);
      if (ctx.mounted) Navigator.of(ctx).pop();
      await Share.shareXFiles(
        [XFile(out.path)],
        subject: 'Backup NUSA Kasir',
        text: 'File backup database NUSA Kasir',
      );
    } catch (e) {
      if (ctx.mounted) TopToast.error(ctx, 'Gagal backup: $e');
    }
  }

  Future<void> _restore(BuildContext ctx) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['sqlite', 'db'],
      );
      if (result == null || result.files.single.path == null) return;
      final picked = File(result.files.single.path!);
      final db = ref.read(databaseProvider);
      await db.close();
      await picked.copy(await _dbPath());
      ref.invalidate(databaseProvider);
      if (ctx.mounted) Navigator.of(ctx).pop();
      if (rootContext.mounted) GoRouter.of(rootContext).go('/home');
    } catch (e) {
      if (ctx.mounted) TopToast.error(ctx, 'Gagal restore: $e');
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Backup & Restore',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.backup),
                title: const Text('Backup Database'),
                subtitle: const Text('Simpan & bagikan file database'),
                onTap: () => _backup(context),
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore Database'),
                subtitle: const Text('Pilih file backup (.sqlite)'),
                onTap: () => _restore(context),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
}
