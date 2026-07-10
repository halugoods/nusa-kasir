import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:nusa_kasir/core/services/notification_service.dart';
import 'package:nusa_kasir/core/services/stok_alert_worker.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/settings_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Workmanager: initialise first so the callback dispatcher is registered.
  await Workmanager().initialize(stokCallbackDispatcher, isInDebugMode: false);

  // Local notifications
  await NotificationService.init();

  if (NusaConfig.supabaseUrl.isNotEmpty && NusaConfig.supabaseAnon.isNotEmpty) {
    await Supabase.initialize(
        url: NusaConfig.supabaseUrl, publishableKey: NusaConfig.supabaseAnon);
  }
  final activated = (await SecureStore.getActivation()) != null;

  // Load persisted theme mode before app starts.
  final db = AppDatabase();
  final persistedTheme =
      await SettingsRepository(db).getThemeMode() ?? 'system';
  await db.close();

  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider.overrideWith((ref) => persistedTheme),
      ],
      child: NusaApp(
          initialLocation: activated ? '/login' : '/activation'),
    ),
  );
}
