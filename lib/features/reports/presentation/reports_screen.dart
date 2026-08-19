import 'package:daytrace/features/reports/data/report_repository.dart';
import 'package:daytrace/features/reports/data/report_export_service.dart';
import 'package:daytrace/features/ai_summary/data/ai_summary_service.dart';
import 'package:daytrace/features/today/application/today_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final NotifierProvider<_ReportDayNotifier, DateTime> reportDayProvider =
    NotifierProvider<_ReportDayNotifier, DateTime>(_ReportDayNotifier.new);
final NotifierProvider<_ReportModeNotifier, bool> reportModeProvider =
    NotifierProvider<_ReportModeNotifier, bool>(_ReportModeNotifier.new);

class _ReportDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();
}

class _ReportModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
}
final dailyReportProvider = FutureProvider<DailyReport>((Ref ref) {
  final DateTime day = ref.watch(reportDayProvider);
  return ReportRepository(ref.watch(taskRepositoryProvider)).loadDaily(day);
});
final weeklyReportProvider = FutureProvider<WeeklyReport>((Ref ref) {
  final DateTime day = ref.watch(reportDayProvider);
  return ReportRepository(ref.watch(taskRepositoryProvider)).loadWeekly(day);
});

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime day = ref.watch(reportDayProvider);
    final bool weekly = ref.watch(reportModeProvider);
    final AsyncValue<DailyReport> report = ref.watch(dailyReportProvider);
    final AsyncValue<WeeklyReport> weeklyReport = ref.watch(weeklyReportProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: weekly ? weeklyReport.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not create this weekly report.')),
        data: (WeeklyReport data) => _WeeklyReportBody(day: day, report: data),
      ) : report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not create this report.')),
        data: (DailyReport data) => ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            _ReportModeToggle(weekly: weekly),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
              IconButton(onPressed: () => ref.read(reportDayProvider.notifier).state = day.subtract(const Duration(days: 1)), icon: const Icon(Icons.chevron_left_rounded)),
              Text('${day.day}/${day.month}/${day.year}', style: Theme.of(context).textTheme.titleMedium),
              IconButton(onPressed: day.isAfter(DateTime.now().subtract(const Duration(days: 1))) ? null : () => ref.read(reportDayProvider.notifier).state = day.add(const Duration(days: 1)), icon: const Icon(Icons.chevron_right_rounded)),
            ]),
            const SizedBox(height: 16),
            Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('Tracked time', style: Theme.of(context).textTheme.labelLarge),
              Text(DailyReport.formatMinutes(data.trackedMinutes), style: Theme.of(context).textTheme.displaySmall),
              Text('${data.entries.length} recorded activities'),
            ]))),
            const SizedBox(height: 16),
            Text('Time by category', style: Theme.of(context).textTheme.titleMedium),
            ...data.categoryMinutes.entries.map((MapEntry<String, int> item) => ListTile(title: Text(item.key), trailing: Text(DailyReport.formatMinutes(item.value)))),
            const SizedBox(height: 12),
            Text('Local summary', style: Theme.of(context).textTheme.titleMedium),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(data.localSummary))),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Create optional AI summary'),
              subtitle: const Text('Sends this report only after you confirm'),
              onTap: () => _generateAiSummary(context, ref, data),
            ),
            const SizedBox(height: 12),
            _DailyNoteCard(day: day, initialNote: data.note),
          ],
        ),
      ),
      floatingActionButton: weekly
          ? weeklyReport.value == null ? null : FloatingActionButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: weeklyReport.value!.localSummary)),
              tooltip: 'Copy weekly report', child: const Icon(Icons.copy_rounded),
            )
          : report.value == null ? null : FloatingActionButton(
        onPressed: () => _showExportActions(context, report.value!),
        tooltip: 'Export report', child: const Icon(Icons.ios_share_rounded),
      ),
    );
  }

  Future<void> _showExportActions(BuildContext context, DailyReport report) => showModalBottomSheet<void>(context: context, builder: (BuildContext sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
    ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('Copy text'), onTap: () async { await Clipboard.setData(ClipboardData(text: report.localSummary)); if (sheet.mounted) Navigator.pop(sheet); }),
    ListTile(leading: const Icon(Icons.share_rounded), title: const Text('Share text'), onTap: () async { await ReportExportService().shareText(report); if (sheet.mounted) Navigator.pop(sheet); }),
    ListTile(leading: const Icon(Icons.picture_as_pdf_rounded), title: const Text('Share PDF'), onTap: () async { await ReportExportService().sharePdf(report); if (sheet.mounted) Navigator.pop(sheet); }),
  ])));

  Future<void> _generateAiSummary(BuildContext context, WidgetRef ref, DailyReport report) async {
    final bool? consent = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: const Text('Send report to your AI proxy?'),
        content: const Text('DayTrace will send the selected date, your local report text, tracked time, and category totals to the HTTPS proxy you configured. It never sends data automatically or stores a provider API key in the app.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Continue')),
        ],
      ),
    );
    if (consent != true || !context.mounted) return;
    try {
      final String summary = await AiSummaryService(ref.read(appDatabaseProvider)).generateDailySummary(report);
      if (!context.mounted) return;
      await showDialog<void>(context: context, builder: (BuildContext dialog) => AlertDialog(title: const Text('AI summary'), content: SingleChildScrollView(child: SelectableText(summary)), actions: <Widget>[TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Close'))]));
    } on StateError catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI summary failed. Your local summary is still available.')));
    }
  }
}

class _ReportModeToggle extends ConsumerWidget {
  const _ReportModeToggle({required this.weekly});
  final bool weekly;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SegmentedButton<bool>(
    segments: const <ButtonSegment<bool>>[
      ButtonSegment(value: false, label: Text('Daily'), icon: Icon(Icons.today_outlined)),
      ButtonSegment(value: true, label: Text('Weekly'), icon: Icon(Icons.date_range_outlined)),
    ],
    selected: <bool>{weekly},
    onSelectionChanged: (Set<bool> value) => ref.read(reportModeProvider.notifier).state = value.single,
  );
}

class _WeeklyReportBody extends ConsumerWidget {
  const _WeeklyReportBody({required this.day, required this.report});
  final DateTime day;
  final WeeklyReport report;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(20),
    children: <Widget>[
      _ReportModeToggle(weekly: true),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
        IconButton(onPressed: () => ref.read(reportDayProvider.notifier).state = day.subtract(const Duration(days: 7)), icon: const Icon(Icons.chevron_left_rounded)),
        Text('Week of ${report.weekStart.day}/${report.weekStart.month}/${report.weekStart.year}', style: Theme.of(context).textTheme.titleMedium),
        IconButton(onPressed: day.isAfter(DateTime.now().subtract(const Duration(days: 7))) ? null : () => ref.read(reportDayProvider.notifier).state = day.add(const Duration(days: 7)), icon: const Icon(Icons.chevron_right_rounded)),
      ]),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('Tracked this week', style: Theme.of(context).textTheme.labelLarge),
        Text(DailyReport.formatMinutes(report.trackedMinutes), style: Theme.of(context).textTheme.displaySmall),
        Text('${report.completionRate}% completion rate · ${report.taskCounts.overdue} overdue'),
      ]))),
      const SizedBox(height: 16),
      Text('Tracked time by day', style: Theme.of(context).textTheme.titleMedium),
      ...report.days.map((DailyReport item) => ListTile(title: Text('${item.day.day}/${item.day.month}'), trailing: Text(DailyReport.formatMinutes(item.trackedMinutes)))),
      const SizedBox(height: 12),
      Text('Most time-consuming', style: Theme.of(context).textTheme.titleMedium),
      ...report.mostTimeConsuming.map((MapEntry<String, int> item) => ListTile(title: Text(item.key), trailing: Text(DailyReport.formatMinutes(item.value)))),
      const SizedBox(height: 12),
      Text('Local summary', style: Theme.of(context).textTheme.titleMedium),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(report.localSummary))),
    ],
  );
}

class _DailyNoteCard extends ConsumerStatefulWidget {
  const _DailyNoteCard({required this.day, required this.initialNote});
  final DateTime day;
  final String? initialNote;
  @override
  ConsumerState<_DailyNoteCard> createState() => _DailyNoteCardState();
}

class _DailyNoteCardState extends ConsumerState<_DailyNoteCard> {
  late final TextEditingController _controller;
  @override
  void initState() { super.initState(); _controller = TextEditingController(text: widget.initialNote ?? ''); }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
    Text('Daily note', style: Theme.of(context).textTheme.titleMedium),
    TextField(controller: _controller, maxLines: 3, decoration: const InputDecoration(hintText: 'Add context for this day')),
    Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () async { await ReportRepository(ref.read(taskRepositoryProvider)).saveDailyNote(widget.day, _controller.text); ref.invalidate(dailyReportProvider); }, child: const Text('Save note'))),
  ])));
}
