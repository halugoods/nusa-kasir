import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (NusaConfig.supabaseUrl.isNotEmpty && NusaConfig.supabaseAnon.isNotEmpty) {
    await Supabase.initialize(url: NusaConfig.supabaseUrl, anonKey: NusaConfig.supabaseAnon);
  }
  final activated = (await SecureStore.getActivation()) != null;
  runApp(NusaApp(initialLocation: activated ? '/login' : '/activation'));
}
