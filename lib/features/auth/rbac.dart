import 'package:nusa_kasir/core/config/nusa_config.dart';

/// Check if user has basic access to a screen.
bool hasAccess(String role, String screen) {
  final access = NusaConfig.roleAccess[role];
  return access?.contains(screen) ?? false;
}

/// True if this screen requires PIN re-entry (for security).
bool needsPinGuard(String screen) {
  return NusaConfig.pinGuardScreens.contains(screen);
}

/// True if this screen is owner-only (block non-owners).
bool isOwnerOnly(String screen) {
  return NusaConfig.ownerOnlyScreens.contains(screen);
}

/// Legacy pin-to-role map (deprecated — now queries DB).
const Map<String, String> pinToRole = {
  '1234': 'Owner',
  '5678': 'Manager',
  '9012': 'Kasir',
  '1111': 'Gudang',
  '2222': 'Finance',
};
