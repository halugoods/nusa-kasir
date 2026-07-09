import 'package:nusa_kasir/core/config/nusa_config.dart';

bool hasAccess(String role, String screen) {
  final access = NusaConfig.roleAccess[role];
  return access?.contains(screen) ?? false;
}

const Map<String, String> pinToRole = {
  '1234': 'Owner',
  '5678': 'Manager',
  '9012': 'Kasir',
  '1111': 'Gudang',
  '2222': 'Finance',
};
