import 'dart:typed_data';

import 'package:daytrace/features/reports/data/report_repository.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class ReportExportService {
  Future<void> shareText(DailyReport report) => SharePlus.instance.share(
    ShareParams(text: report.localSummary, subject: 'DayTrace report'),
  );

  Future<void> sharePdf(DailyReport report) async {
    final Uint8List bytes = await buildPdf(report);
    await Printing.sharePdf(bytes: bytes, filename: 'daytrace-${report.day.year}-${report.day.month}-${report.day.day}.pdf');
  }

  Future<Uint8List> buildPdf(DailyReport report) async {
    final pw.Document document = pw.Document();
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => <pw.Widget>[
        pw.Text('DayTrace daily report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.Text('${report.day.day}/${report.day.month}/${report.day.year}'),
        pw.SizedBox(height: 16),
        pw.Text('Tracked time: ${DailyReport.formatMinutes(report.trackedMinutes)}'),
        pw.Text('Recorded activities: ${report.entries.length}'),
        pw.SizedBox(height: 12),
        pw.Text('Time by category', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ...report.categoryMinutes.entries.map((MapEntry<String, int> item) => pw.Text('${item.key}: ${DailyReport.formatMinutes(item.value)}')),
        pw.SizedBox(height: 12),
        pw.Text('Activity timeline', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ...report.entries.map(
          (entry) => pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              '${_clock(entry.startAt)} - ${entry.endAt == null ? 'Running' : _clock(entry.endAt!)}  ${entry.taskTitle ?? entry.note ?? 'Activity'}',
            ),
          ),
        ),
      ],
    ));
    return document.save();
  }

  String _clock(DateTime value) => '${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
}
