import 'package:daytrace/features/tasks/data/task_repository.dart';

class ReportRepository {
  ReportRepository(this._tasks);

  final TaskRepository _tasks;

  Future<DailyReport> loadDaily(DateTime day) async {
    final List<TimelineItem> entries = await _tasks.loadTimeline(day);
    final String? note = await _tasks.loadDailyNote(day);
    final DateTime start = DateTime(day.year, day.month, day.day).toUtc();
    final DateTime end = start.add(const Duration(days: 1));
    int totalMinutes = 0;
    int untrackedMinutes = 0;
    final Map<String, int> categoryMinutes = <String, int>{};
    for (final TimelineItem entry in entries) {
      final DateTime clippedStart = entry.startAt.isBefore(start) ? start : entry.startAt;
      final DateTime rawEnd = entry.endAt ?? DateTime.now().toUtc();
      final DateTime clippedEnd = rawEnd.isAfter(end) ? end : rawEnd;
      final int minutes = clippedEnd.isAfter(clippedStart)
          ? clippedEnd.difference(clippedStart).inMinutes
          : 0;
      if (entry.entryType == 'untracked') {
        untrackedMinutes += minutes;
      } else {
        totalMinutes += minutes;
      }
      final String category = entry.categoryName ?? _entryLabel(entry);
      categoryMinutes.update(category, (int current) => current + minutes, ifAbsent: () => minutes);
    }
    final TaskStatusCounts counts = await _tasks.loadTaskStatusCounts(start, end);
    return DailyReport(
      day: day,
      entries: entries,
      trackedMinutes: totalMinutes,
      categoryMinutes: categoryMinutes,
      taskCounts: counts,
      note: note,
      untrackedMinutes: untrackedMinutes,
    );
  }

  Future<void> saveDailyNote(DateTime day, String note) => _tasks.saveDailyNote(day, note);

  Future<WeeklyReport> loadWeekly(DateTime day) async {
    final DateTime local = day.toLocal();
    final DateTime weekStart = DateTime(local.year, local.month, local.day)
        .subtract(Duration(days: local.weekday - 1));
    final List<DailyReport> days = await Future.wait<DailyReport>(
      <Future<DailyReport>>[
        for (int offset = 0; offset < 7; offset++) loadDaily(weekStart.add(Duration(days: offset))),
      ],
    );
    final Map<String, int> categoryMinutes = <String, int>{};
    final Map<String, int> taskMinutes = <String, int>{};
    int total = 0;
    for (final DailyReport report in days) {
      total += report.trackedMinutes;
      report.categoryMinutes.forEach((String category, int minutes) {
        categoryMinutes.update(category, (int current) => current + minutes, ifAbsent: () => minutes);
      });
      for (final TimelineItem entry in report.entries) {
        if (entry.endAt == null) continue;
        final DateTime dayStart = DateTime(report.day.year, report.day.month, report.day.day).toUtc();
        final DateTime dayEnd = dayStart.add(const Duration(days: 1));
        final DateTime start = entry.startAt.isBefore(dayStart) ? dayStart : entry.startAt;
        final DateTime end = entry.endAt!.isAfter(dayEnd) ? dayEnd : entry.endAt!;
        final int minutes = end.isAfter(start) ? end.difference(start).inMinutes : 0;
        final String label = entry.taskTitle ?? entry.note ?? 'Activity';
        taskMinutes.update(label, (int current) => current + minutes, ifAbsent: () => minutes);
      }
    }
    final TaskStatusCounts counts = await _tasks.loadTaskStatusCounts(weekStart, weekStart.add(const Duration(days: 7)));
    final List<MapEntry<String, int>> mostTimeConsuming = taskMinutes.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
    return WeeklyReport(
      weekStart: weekStart,
      days: days,
      trackedMinutes: total,
      categoryMinutes: categoryMinutes,
      taskCounts: counts,
      mostTimeConsuming: mostTimeConsuming.take(5).toList(growable: false),
    );
  }

  String _entryLabel(TimelineItem entry) {
    switch (entry.entryType) {
      case 'break': return 'Break';
      case 'meeting': return 'Meeting';
      case 'untracked': return 'Untracked';
      default: return 'Other activity';
    }
  }
}

class DailyReport {
  const DailyReport({required this.day, required this.entries, required this.trackedMinutes, required this.categoryMinutes, required this.taskCounts, required this.note, required this.untrackedMinutes});

  final DateTime day;
  final List<TimelineItem> entries;
  final int trackedMinutes;
  final Map<String, int> categoryMinutes;
  final TaskStatusCounts taskCounts;
  final String? note;
  final int untrackedMinutes;

  String get localSummary {
    final String date = '${day.day}/${day.month}/${day.year}';
    final StringBuffer out = StringBuffer('DayTrace daily report - $date\n');
    out.writeln('Tracked time: ${formatMinutes(trackedMinutes)}');
    out.writeln('Activities: ${entries.length}');
    out.writeln('Untracked time: ${formatMinutes(untrackedMinutes)}');
    out.writeln('Tasks: ${taskCounts.completed} completed, ${taskCounts.pending} pending, ${taskCounts.overdue} overdue');
    if (categoryMinutes.isNotEmpty) {
      out.writeln('\nTime by category:');
      categoryMinutes.forEach((String name, int minutes) => out.writeln('- $name: ${formatMinutes(minutes)}'));
    }
    if (note != null && note!.isNotEmpty) out.writeln('\nNote: $note');
    if (entries.isNotEmpty) {
      out.writeln('\nActivity timeline:');
      for (final TimelineItem entry in entries) {
        final String label = entry.taskTitle ?? entry.note ?? 'Activity';
        out.writeln('- ${_clock(entry.startAt)}-${entry.endAt == null ? 'running' : _clock(entry.endAt!)}: $label');
      }
    }
    return out.toString().trimRight();
  }

  static String formatMinutes(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';
  static String _clock(DateTime value) => '${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
}

class WeeklyReport {
  const WeeklyReport({
    required this.weekStart,
    required this.days,
    required this.trackedMinutes,
    required this.categoryMinutes,
    required this.taskCounts,
    required this.mostTimeConsuming,
  });

  final DateTime weekStart;
  final List<DailyReport> days;
  final int trackedMinutes;
  final Map<String, int> categoryMinutes;
  final TaskStatusCounts taskCounts;
  final List<MapEntry<String, int>> mostTimeConsuming;

  int get completionRate {
    final int denominator = taskCounts.completed + taskCounts.pending + taskCounts.overdue;
    return denominator == 0 ? 0 : (taskCounts.completed * 100 / denominator).round();
  }

  String get localSummary {
    final StringBuffer out = StringBuffer('DayTrace weekly report - week of ${weekStart.day}/${weekStart.month}/${weekStart.year}\n');
    out.writeln('Tracked time: ${DailyReport.formatMinutes(trackedMinutes)}');
    out.writeln('Completion rate: $completionRate% (${taskCounts.completed} completed)');
    out.writeln('Overdue carry-forward: ${taskCounts.overdue}');
    if (mostTimeConsuming.isNotEmpty) {
      out.writeln('\nMost time-consuming tasks:');
      for (final MapEntry<String, int> item in mostTimeConsuming) {
        out.writeln('- ${item.key}: ${DailyReport.formatMinutes(item.value)}');
      }
    }
    return out.toString().trimRight();
  }
}
