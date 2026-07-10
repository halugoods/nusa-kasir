import 'dart:convert';
import 'package:nusa_kasir/core/utils/secure_storage.dart';

class EmployeeSession {
  final int employeeId;
  final String name;
  final String role;
  final DateTime savedAt;
  final bool remember;

  EmployeeSession({
    required this.employeeId,
    required this.name,
    required this.role,
    this.remember = false,
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();

  bool get isExpired {
    // Only remembered sessions can survive app restart.
    // Non-remembered sessions are in-memory only and should NOT be persisted.
    if (!remember) return true; // not remembered → don't auto-restore
    return DateTime.now().difference(savedAt).inHours >= 8;
  }

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'name': name,
        'role': role,
        'savedAt': savedAt.toIso8601String(),
        'remember': remember,
      };

  factory EmployeeSession.fromJson(Map<String, dynamic> json) {
    return EmployeeSession(
      employeeId: json['employeeId'] as int,
      name: json['name'] as String,
      role: json['role'] as String,
      remember: json['remember'] == true,
      savedAt: DateTime.parse(json['savedAt'] as String),
    );
  }

  static const _key = 'nusa_employee_session';

  static Future<EmployeeSession?> restore() async {
    final raw = await SecureStore.read(key: _key);
    if (raw == null) return null;
    try {
      final session = EmployeeSession.fromJson(jsonDecode(raw));
      if (session.isExpired) {
        await clear();
        return null;
      }
      return session;
    } catch (_) {
      await clear();
      return null;
    }
  }

  static Future<void> save(EmployeeSession session) async {
    await SecureStore.write(
        key: _key, value: jsonEncode(session.toJson()));
  }

  static Future<void> clear() async {
    await SecureStore.delete(key: _key);
  }
}
