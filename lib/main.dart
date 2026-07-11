import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/auth/employee_session.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:nusa_kasir/core/services/notification_service.dart';
import 'package:nusa_kasir/core/services/stok_alert_worker.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/settings_repository.dart';

/// Catch all unhandled Flutter errors and display them instead of blank screen.
void _setupErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (!details.silent) {
      final errorString = 'FlutterError: ${details.exception}\n${details.stack?.toString().substring(0, 500) ?? ''}';
      debugPrint(errorString);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformDispatcher error: $error\n$stack');
    return true; // handled
  };
}

/// Swap a pending encrypted backup into place BEFORE the database opens.
/// downloadAndRestore() stages a .pending file + flag; we commit it here
/// while the app is still single-threaded and no DB handle exists.
Future<void> _applyPendingRestore() async {
  if (!await SecureStore.hasPendingRestore()) return;
  try {
    final dir = await getApplicationDocumentsDirectory();
    final pending = File(p.join(dir.path, 'nusa_kasir.sqlite.pending'));
    final target = File(p.join(dir.path, 'nusa_kasir.sqlite'));
    if (await pending.exists()) {
      await pending.copy(target.path); // atomic replace
      await pending.delete();
    }
    await SecureStore.clearPendingRestore();
  } catch (_) {
    await SecureStore.clearPendingRestore();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _setupErrorHandlers();

  // Workmanager: initialise first so the callback dispatcher is registered.
  await Workmanager().initialize(stokCallbackDispatcher, isInDebugMode: false);

  // Local notifications
  await NotificationService.init();

  if (NusaConfig.supabaseUrl.isNotEmpty && NusaConfig.supabaseAnon.isNotEmpty) {
    await Supabase.initialize(
        url: NusaConfig.supabaseUrl, publishableKey: NusaConfig.supabaseAnon);
  }
  final activated = (await SecureStore.getActivation()) != null;

  // Apply pending device-migration backup BEFORE opening the database.
  await _applyPendingRestore();

  // Load persisted theme mode before app starts.
  final db = AppDatabase();
  final persistedTheme =
      await SettingsRepository(db).getThemeMode() ?? 'system';

  // Try to restore a remembered employee session.
  String initialLocation;
  if (!activated) {
    initialLocation = '/activation';
  } else {
    final session = await EmployeeSession.restore();
    initialLocation = (session != null && !session.isExpired)
        ? '/home'   // valid session → skip login
        : '/login';
  }
  await db.close();

  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider.overrideWith((ref) => persistedTheme),
      ],
      child: NusaApp(initialLocation: initialLocation),
    ),
  );
}
