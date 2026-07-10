import 'package:flutter/material.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
class NusaSnackbar {
  static void error(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: NusaConfig.primaryColor,
      content: Text(message, style: const TextStyle(color: Colors.white)),
    ));
  }

  static void success(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.green,
      content: Text(message, style: const TextStyle(color: Colors.white)),
    ));
  }
}
