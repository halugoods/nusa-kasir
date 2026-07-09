import 'package:flutter/material.dart';

abstract class NusaConfig {
  static const String appName = "NUSA Kasir";
  static const String brandName = "NUSA";
  static const String vertical = "kelontong";
  static const String tagline = "Aplikasi Kasir untuk Toko Kelontong";
  static const String applicationId = "com.nusa.kasir";
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnon = String.fromEnvironment('SUPABASE_ANON', defaultValue: '');
  static const Color primaryColor = Color(0xFFE53935);
  static const Color primaryDark = Color(0xFFB91C1C);
  static const Color backgroundColor = Color(0xFFF9FAFB);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const bool enableBarcode = true;
  static const bool enableQRIS = true;
  static const bool enableSpreadsheet = true;
  static const bool enableWhatsApp = true;
  static const int maxDevicesPerKey = 2;
  static const List<String> categories = ["Makanan", "Minuman", "Sembako", "Lainnya"];
  static const List<String> roles = ["Owner", "Manager", "Kasir", "Gudang", "Finance"];
  static const Map<String, List<String>> roleAccess = {
    "Owner": ["home","kasir","produk","stok","transaksi","pelanggan","promo","laporan","presensi","keuangan","pengaturan"],
    "Manager": ["home","kasir","produk","stok","transaksi","pelanggan","promo","laporan","presensi","keuangan","pengaturan"],
    "Kasir": ["home","kasir","produk","transaksi","pelanggan"],
    "Gudang": ["home","produk","stok","laporan"],
    "Finance": ["home","transaksi","keuangan","laporan","presensi"],
  };
}
