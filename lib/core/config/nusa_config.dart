import 'package:flutter/material.dart';

abstract class NusaConfig {
  static const String appName = "NUSA";
  static const String brandName = "NUSA";
  static const String appSubtitle = "Aplikasi Kasir untuk Toko Kelontong";
  static const String appVersion = "1.0.0";
  static const int appBuildNumber = 7;
  static const String githubRepo = "halugoods/nusa-kasir";
  static const String applicationId = "com.nusa.kasir";
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://sakeuhcbcnueplzlkltm.supabase.co');
  static const String supabaseAnon = String.fromEnvironment('SUPABASE_ANON', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNha2V1aGNiY251ZXBsemxrbHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM2ODIzMDEsImV4cCI6MjA5OTI1ODMwMX0.WvjZJ8Sd3o5T8a4vMApyvoCoS01Qv493mo1PxyWO06M');
  // --- Brand colors (from nusa design tokens) ---
  static const Color primaryColor = Color(0xFFE63946);
  static const Color primaryDark = Color(0xFFC1121F);
  static const Color primarySoft = Color(0xFFFDE8EA);
  static const Color backgroundColor = Color(0xFFF7F7F9);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color dividerColor = Color(0xFFE5E7EB);
  static const Color borderColor = Color(0xFFF3F4F6);

  // --- Accent ---
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentGreenDark = Color(0xFF059669);
  static const Color accentPurple = Color(0xFF8B5CF6);
  static const Color accentPurpleDark = Color(0xFF7C3AED);
  static const Color accentGold = Color(0xFFF59E0B);

  // --- Dark mode palette ---
  static const Color darkBackground = Color(0xFF0F0F1A);
  static const Color darkSurface = Color(0xFF1A1A2E);
  static const Color darkSurface2 = Color(0xFF252540);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF64748B);
  static const Color darkDivider = Color(0xFF2D2D44);
  static const Color darkBorder = Color(0xFF3A3A52);
  static const Color darkCardShadow = Color(0x1A000000);
  static const bool enableBarcode = true;
  static const bool enableQRIS = true;
  static const bool enableSpreadsheet = true;
  static const bool enableWhatsApp = true;
  static const int maxDevicesPerKey = 2;
  static const List<String> categories = ["Makanan", "Minuman", "Sembako", "Lainnya"];
  static const List<String> roles = ["Owner", "Manager", "Kasir", "Gudang", "Finance"];
  static const Map<String, List<String>> roleAccess = {
    "Owner": ["home","kasir","produk","stok","transaksi","pelanggan","promo","laporan","presensi","karyawan","keuangan","pengaturan","supplier","spreadsheet","pesanan_online"],
    "Manager": ["home","kasir","produk","stok","transaksi","pelanggan","promo","laporan","presensi","karyawan","keuangan","pengaturan","supplier","spreadsheet","pesanan_online"],
    "Kasir": ["home","kasir","produk","transaksi","pelanggan"],
    "Gudang": ["home","produk","stok","laporan","supplier"],
    "Finance": ["home","transaksi","keuangan","laporan","presensi","karyawan","supplier"],
  };
}
