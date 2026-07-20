import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';

/// Build a clean PDF report and return the file (ready to share).
Future<File> exportReportPdf({
  required String period,
  required Map<String, dynamic> summary,
  required List<Map<String, dynamic>> topProducts,
  required List<Map<String, dynamic>> categories,
  required Map<String, int> payments,
}) async {
  final omzet = summary['omzet'] as int? ?? 0;
  final count = summary['count'] as int? ?? 0;
  final avg = summary['avg'] as int? ?? 0;

  final pdf = pw.Document(title: 'Laporan NUSA Kasir', author: 'NUSA Kasir');

  pw.Widget _stat(String label, String value) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
      );

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text('Laporan NUSA Kasir',
            style: pw.TextStyle(
                fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.Text('Periode: $period',
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
        pw.SizedBox(height: 16),
        pw.Row(children: [
          _stat('Omzet', formatRupiah(omzet)),
          pw.SizedBox(width: 8),
          _stat('Transaksi', count.toString()),
          pw.SizedBox(width: 8),
          _stat('Rata-rata', formatRupiah(avg)),
        ]),
        pw.SizedBox(height: 24),
        pw.Text('Produk Terlaris',
            style: pw.TextStyle(
                fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        if (topProducts.isEmpty)
          pw.Text('Belum ada data',
              style: const pw.TextStyle(color: PdfColors.grey600))
        else
          pw.Table.fromTextArray(
            headers: const ['Produk', 'Qty', 'Revenue'],
            data: topProducts
                .map((p) => [
                      p['name'].toString(),
                      (p['qty'] as int).toString(),
                      formatRupiah(p['revenue'] as int),
                    ])
                .toList(),
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, fontSize: 11),
            cellStyle: const pw.TextStyle(fontSize: 11),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
            },
          ),
        pw.SizedBox(height: 24),
        pw.Text('Penjualan per Kategori',
            style: pw.TextStyle(
                fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        if (categories.isEmpty)
          pw.Text('Belum ada data',
              style: const pw.TextStyle(color: PdfColors.grey600))
        else
          pw.Table.fromTextArray(
            headers: const ['Kategori', 'Qty', 'Revenue'],
            data: categories
                .map((c) => [
                      c['category'].toString(),
                      (c['qty'] as int).toString(),
                      formatRupiah(c['revenue'] as int),
                    ])
                .toList(),
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, fontSize: 11),
            cellStyle: const pw.TextStyle(fontSize: 11),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
            },
          ),
        pw.SizedBox(height: 24),
        pw.Text('Metode Pembayaran',
            style: pw.TextStyle(
                fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        if (payments.isEmpty)
          pw.Text('Belum ada data',
              style: const pw.TextStyle(color: PdfColors.grey600))
        else
          pw.Table.fromTextArray(
            headers: const ['Metode', 'Total'],
            data: payments.entries
                .map((e) => [e.key, formatRupiah(e.value)])
                .toList(),
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, fontSize: 11),
            cellStyle: const pw.TextStyle(fontSize: 11),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {1: pw.Alignment.centerRight},
          ),
        pw.SizedBox(height: 24),
        pw.Divider(),
        pw.Text(
            'Dicetak otomatis oleh NUSA Kasir • ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
      ],
    ),
  );

  final dir = await getTemporaryDirectory();
  final safe = period.replaceAll(RegExp(r'[^a-z0-9]', caseSensitive: false), '');
  final file = File('${dir.path}/laporan_$safe.pdf');
  await file.writeAsBytes(await pdf.save());
  return file;
}
