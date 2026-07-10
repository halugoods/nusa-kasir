import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:nusa_kasir/data/database/app_database.dart';

/// Unique task name registered with workmanager.
const _stokTaskName = 'nusa_kasir_stok_check';

/// Top-level callback invoked by workmanager in a background isolate.
///
/// 1. Opens the database.
/// 2. Queries for products where stock <= minStock.
/// 3. If any found, fires a local notification.
@pragma('vm:entry-point')
void stokCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != _stokTaskName) return false;
    try {
      final db = AppDatabase();
      await _checkAndNotify(db);
      await db.close();
      return true;
    } catch (_) {
      return false;
    }
  });
}

Future<void> _checkAndNotify(AppDatabase db) async {
  // Initialize notifications in this isolate
  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  await plugin.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
  );

  // Query all products
  final products = await db.select(db.products).get();
  final lowStock = products.where((p) => p.stock <= p.minStock).toList();

  if (lowStock.isEmpty) return;

  final names = lowStock.map((p) => p.name).toList();
  final body = names.length == 1
      ? 'Stok "${names.first}" menipis. Segera restock.'
      : '${names.length} produk stoknya menipis: ${names.take(3).join(", ")}';

  await plugin.show(
    DateTime.now().millisecond,
    '⚠️ Stok Menipis',
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'nusa_kasir_stock',
        'Stok Menipis',
        channelDescription: 'Notifikasi saat stok produk menipis',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

/// Register the periodic background task.
Future<void> registerStokCheck() async {
  await Workmanager().registerPeriodicTask(
    _stokTaskName,
    _stokTaskName,
    frequency: const Duration(minutes: 30),
    constraints: Constraints(),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
  );
}

/// Cancel the periodic background task.
Future<void> cancelStokCheck() async {
  await Workmanager().cancelByUniqueName(_stokTaskName);
}
