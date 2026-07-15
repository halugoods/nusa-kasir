import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/activation/activation_repository.dart';
import 'package:nusa_kasir/core/auth/employee_session.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/providers.dart';
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
Future<void> _applyPendingRestore() async {
  if (!await SecureStore.hasPendingRestore()) return;
  try {
    final dir = await getApplicationDocumentsDirectory();
    final pending = File(p.join(dir.path, 'nusa_kasir.sqlite.pending'));
    final target = File(p.join(dir.path, 'nusa_kasir.sqlite'));
    if (await pending.exists()) {
      await pending.copy(target.path);
      await pending.delete();
    }
    await SecureStore.clearPendingRestore();
  } catch (_) {
    await SecureStore.clearPendingRestore();
  }
}

/// On startup, compare local backup timestamp vs cloud.
/// If cloud is newer → download + stage pending restore → restart.
/// If local is newer → push local to cloud.
Future<void> _syncCloudOnStartup() async {
  if (NusaConfig.supabaseUrl.isEmpty) return;
  try {
    final key = await SecureStore.getActivation();
    if (key == null) return;
    final supabase = Supabase.instance.client;
    final repo = ActivationRepository(supabase);
    final localTime = await SecureStore.getLastBackupTime();
    final cloudTime = await repo.getBackupTimestamp();

    if (cloudTime != null && (localTime == null || cloudTime.isAfter(localTime))) {
      // Cloud is newer — pull it down
      final ok = await repo.downloadAndRestore(key);
      if (ok) {
        // Restart to apply the restored DB
        await _applyPendingRestore();
        // Update local timestamp
        await SecureStore.saveLastBackupTime(cloudTime);
      }
    } else if (localTime != null && (cloudTime == null || localTime.isAfter(cloudTime))) {
      // Local is newer — push up
      final ok = await repo.uploadBackup(key);
      if (ok) {
        await SecureStore.saveLastBackupTime(DateTime.now());
      }
    }
  } catch (_) {
    // Offline or error — skip sync, use local data
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _setupErrorHandlers();

  // Workmanager
  await Workmanager().initialize(stokCallbackDispatcher, isInDebugMode: false);

  // Local notifications
  await NotificationService.init();

  if (NusaConfig.supabaseUrl.isNotEmpty && NusaConfig.supabaseAnon.isNotEmpty) {
    await Supabase.initialize(
        url: NusaConfig.supabaseUrl, publishableKey: NusaConfig.supabaseAnon);
  }

  // Apply pending device-migration backup BEFORE opening the database.
  await _applyPendingRestore();

  // Register background tasks
  registerStokCheck();
  registerOnlineCheck();

  // Load persisted theme mode before app starts.
  final db = AppDatabase();
  final persistedTheme =
      await SettingsRepository(db).getThemeMode() ?? 'system';

  // New startup flow: always go to /activation first
  // ActivationScreen handles Google Sign-In → key activation or PIN login
  // If already activated AND has valid session → skip to /home
  String initialLocation;
  final activated = (await SecureStore.getActivation()) != null;

  if (!activated) {
    // Not activated — go through activation flow (Google → key input)
    initialLocation = '/activation';
  } else {
    // Activated — try to restore session
    final session = await EmployeeSession.restore();
    initialLocation = (session != null && !session.isExpired)
        ? '/home'   // valid session → skip to dashboard
        : '/activation';  // need Google sign-in again (PIN screen in activation)
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
