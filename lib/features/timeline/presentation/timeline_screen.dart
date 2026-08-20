import 'package:daytrace/features/tasks/data/task_repository.dart';
import 'package:daytrace/features/settings/data/settings_repository.dart';
import 'package:daytrace/features/settings/presentation/settings_screen.dart';
import 'package:daytrace/features/timeline/application/timeline_controller.dart';
import 'package:daytrace/features/today/application/today_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(
      smartPromptPastActivityRequestProvider,
      (int? previous, int next) {
        if (next <= 0 || next == previous) return;
        ref.read(smartPromptPastActivityRequestProvider.notifier).consume();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) _showManualEntry(context, ref);
        });
      },
      fireImmediately: true,
    );
    final AsyncValue<List<TimelineItem>> items = ref.watch(timelineControllerProvider);
    final TrackingSettings tracking = ref.watch(trackingSettingsProvider).value ?? const TrackingSettings();
    final DateTime day = ref.watch(timelineDayProvider);
    final TimelineFilter filter = ref.watch(timelineFilterProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timeline'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search all timeline entries',
            onPressed: () => _showTimelineSearch(context, ref),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                onPressed: () => ref.read(timelineControllerProvider.notifier).changeDay(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('${day.day}/${day.month}/${day.year}'),
              IconButton(
                onPressed: day.isAfter(DateTime.now().subtract(const Duration(days: 1)))
                    ? null
                    : () => ref.read(timelineControllerProvider.notifier).changeDay(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load timeline.')),
        data: (List<TimelineItem> entries) {
          final List<_TimelineRow> allRows = _timelineRows(day, entries, tracking);
          final List<_TimelineRow> rows = _filterRows(allRows, filter);
          return Column(children: <Widget>[
            SizedBox(height: 52, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: <Widget>[for (final TimelineFilter value in TimelineFilter.values) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(_filterLabel(value)), selected: filter == value, onSelected: (_) => ref.read(timelineFilterProvider.notifier).state = value))])),
            Expanded(child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: rows.length,
                itemBuilder: (BuildContext context, int index) {
                  final _TimelineRow row = rows[index];
                  return row.entry == null
                      ? _GapCard(
                          start: row.start!,
                          end: row.end!,
                          onClassify: (String type) => ref.read(timelineControllerProvider.notifier).classifyGap(
                            startAt: row.start!, endAt: row.end!, entryType: type,
                          ),
                        )
                      : _EntryCard(
                          entry: row.entry!,
                          onEdit: () => _showEditEntry(context, ref, row.entry!),
                          onSplit: () => _showSplitEntry(context, ref, row.entry!),
                          onDelete: () => ref.read(timelineControllerProvider.notifier).deleteEntry(row.entry!.id),
                        );
                },
              )),
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showManualEntry(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add past activity'),
      ),
    );
  }

  List<_TimelineRow> _filterRows(List<_TimelineRow> rows, TimelineFilter filter) => rows.where((_TimelineRow row) {
    if (filter == TimelineFilter.all) return true;
    if (row.entry == null) return filter == TimelineFilter.untracked;
    switch (filter) {
      case TimelineFilter.tracked: return row.entry!.entryType == 'task' || row.entry!.entryType == 'manual';
      case TimelineFilter.untracked: return row.entry!.entryType == 'untracked';
      case TimelineFilter.breaks: return row.entry!.entryType == 'break';
      case TimelineFilter.meetings: return row.entry!.entryType == 'meeting';
      case TimelineFilter.all: return true;
    }
  }).toList(growable: false);

  String _filterLabel(TimelineFilter filter) {
    switch (filter) {
      case TimelineFilter.all: return 'All';
      case TimelineFilter.tracked: return 'Tracked';
      case TimelineFilter.untracked: return 'Untracked';
      case TimelineFilter.breaks: return 'Breaks';
      case TimelineFilter.meetings: return 'Meetings';
    }
  }

  Future<void> _showManualEntry(BuildContext context, WidgetRef ref) async {
    final TextEditingController note = TextEditingController();
    final DateTime selectedDay = ref.read(timelineDayProvider);
    DateTime start = DateTime(selectedDay.year, selectedDay.month, selectedDay.day, 9);
    DateTime end = start.add(const Duration(hours: 1));
    String type = 'manual';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => StatefulBuilder(builder: (BuildContext context, StateSetter setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text('Add past activity', style: Theme.of(context).textTheme.titleLarge),
            TextField(controller: note, autofocus: true, decoration: const InputDecoration(labelText: 'What did you do?')),
            DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Type'), items: const <DropdownMenuItem<String>>[DropdownMenuItem(value: 'manual', child: Text('Activity')), DropdownMenuItem(value: 'break', child: Text('Break')), DropdownMenuItem(value: 'meeting', child: Text('Meeting')), DropdownMenuItem(value: 'untracked', child: Text('Intentionally untracked'))], onChanged: (String? value) => setSheetState(() => type = value!)),
            ListTile(title: const Text('Start'), subtitle: Text(_dateTimeLabel(context, start)), onTap: () async { final DateTime? value = await _pickDateTime(sheetContext, start); if (value != null) setSheetState(() => start = value); }),
            ListTile(title: const Text('End'), subtitle: Text(_dateTimeLabel(context, end)), onTap: () async { final DateTime? value = await _pickDateTime(sheetContext, end); if (value != null) setSheetState(() => end = value); }),
            const SizedBox(height: 12),
            FilledButton(onPressed: () async { try { await ref.read(timelineControllerProvider.notifier).addManualEntry(startAt: start, endAt: end, note: note.text, entryType: type); if (sheetContext.mounted) Navigator.of(sheetContext).pop(); } on StateError catch (error) { if (sheetContext.mounted) ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(error.message))); } on ArgumentError catch (error) { if (sheetContext.mounted) ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(error.message?.toString() ?? 'Check the activity details.'))); } }, child: const Text('Save activity')),
          ]),
        )),
    );
    note.dispose();
  }

  Future<void> _showTimelineSearch(BuildContext context, WidgetRef ref) async {
    final TextEditingController query = TextEditingController();
    DateTime? from;
    DateTime? to;
    String type = 'all';
    List<TimelineItem> results = const <TimelineItem>[];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .78,
            child: Column(children: <Widget>[
              Text('Search timeline', style: Theme.of(context).textTheme.titleLarge),
              TextField(controller: query, decoration: const InputDecoration(labelText: 'Task, note, or category'), textInputAction: TextInputAction.search),
              DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Type'), items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'all', child: Text('All types')), DropdownMenuItem(value: 'task', child: Text('Task work')), DropdownMenuItem(value: 'manual', child: Text('Activity')), DropdownMenuItem(value: 'break', child: Text('Break')), DropdownMenuItem(value: 'meeting', child: Text('Meeting')), DropdownMenuItem(value: 'untracked', child: Text('Untracked')),
              ], onChanged: (String? value) => setSheetState(() => type = value ?? 'all')),
              Row(children: <Widget>[
                Expanded(child: TextButton(onPressed: () async { final DateTime? date = await showDatePicker(context: sheetContext, initialDate: from ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now()); if (date != null) setSheetState(() => from = date); }, child: Text(from == null ? 'From any date' : 'From ${from!.day}/${from!.month}/${from!.year}'))),
                Expanded(child: TextButton(onPressed: () async { final DateTime? date = await showDatePicker(context: sheetContext, initialDate: to ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now()); if (date != null) setSheetState(() => to = date); }, child: Text(to == null ? 'To any date' : 'To ${to!.day}/${to!.month}/${to!.year}'))),
              ]),
              FilledButton.icon(onPressed: () async { final List<TimelineItem> found = await ref.read(taskRepositoryProvider).searchTimeline(query: query.text, from: from, to: to, entryType: type); if (sheetContext.mounted) setSheetState(() => results = found); }, icon: const Icon(Icons.search_rounded), label: const Text('Search')),
              const SizedBox(height: 8),
              Expanded(child: results.isEmpty ? const Center(child: Text('Enter criteria, then search.')) : ListView.builder(itemCount: results.length, itemBuilder: (BuildContext context, int index) { final TimelineItem entry = results[index]; return ListTile(leading: const Icon(Icons.timeline_rounded), title: Text(entry.taskTitle ?? entry.note ?? 'Activity'), subtitle: Text('${_dateTimeLabel(context, entry.startAt.toLocal())} · ${entry.entryType}')); })),
            ]),
          ),
        ),
      ),
    );
    query.dispose();
  }

  Future<void> _showEditEntry(
    BuildContext context,
    WidgetRef ref,
    TimelineItem entry,
  ) async {
    final List<TaskItem> tasks = await ref.read(taskRepositoryProvider).loadAssignableTasks();
    if (!context.mounted) return;
    final TextEditingController note = TextEditingController(text: entry.note ?? '');
    DateTime start = entry.startAt.toLocal();
    DateTime end = entry.endAt!.toLocal();
    String type = entry.entryType;
    String taskChoice = entry.taskId ?? '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text('Edit activity', style: Theme.of(context).textTheme.titleLarge),
              TextField(controller: note, autofocus: true, decoration: const InputDecoration(labelText: 'Description')),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'manual', child: Text('Activity')),
                  DropdownMenuItem(value: 'break', child: Text('Break')),
                  DropdownMenuItem(value: 'meeting', child: Text('Meeting')),
                  DropdownMenuItem(value: 'untracked', child: Text('Intentionally untracked')),
                  DropdownMenuItem(value: 'task', child: Text('Task work')),
                ],
                onChanged: (String? value) => setSheetState(() => type = value ?? 'manual'),
              ),
              DropdownButtonFormField<String>(
                initialValue: taskChoice,
                decoration: const InputDecoration(labelText: 'Assign to task'),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem(value: '', child: Text('No linked task')),
                  for (final TaskItem task in tasks)
                    DropdownMenuItem(value: task.id, child: Text(task.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (String? value) => setSheetState(() => taskChoice = value ?? ''),
              ),
              ListTile(title: const Text('Start'), subtitle: Text(_dateTimeLabel(context, start)), onTap: () async { final DateTime? value = await _pickDateTime(sheetContext, start); if (value != null) setSheetState(() => start = value); }),
              ListTile(title: const Text('End'), subtitle: Text(_dateTimeLabel(context, end)), onTap: () async { final DateTime? value = await _pickDateTime(sheetContext, end); if (value != null) setSheetState(() => end = value); }),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  try {
                    await ref.read(timelineControllerProvider.notifier).updateEntry(
                      entryId: entry.id,
                      startAt: start,
                      endAt: end,
                      note: note.text,
                      entryType: type,
                      taskId: taskChoice.isEmpty ? null : taskChoice,
                    );
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  } on StateError catch (error) {
                    if (sheetContext.mounted) ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(error.message)));
                  } on ArgumentError catch (error) {
                    if (sheetContext.mounted) ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(error.message?.toString() ?? 'Check the activity details.')));
                  }
                },
                child: const Text('Save changes'),
              ),
            ]),
          ),
        ),
      ),
    );
    note.dispose();
  }

  Future<void> _showSplitEntry(
    BuildContext context,
    WidgetRef ref,
    TimelineItem entry,
  ) async {
    final DateTime start = entry.startAt.toLocal();
    final DateTime end = entry.endAt!.toLocal();
    DateTime split = start.add(Duration(microseconds: end.difference(start).inMicroseconds ~/ 2));
    final TextEditingController secondNote = TextEditingController(text: entry.note ?? '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text('Split activity', style: Theme.of(context).textTheme.titleLarge),
            Text('The first part keeps its current details. You can rename the second part.'),
            ListTile(title: const Text('Split at'), subtitle: Text(_dateTimeLabel(context, split)), onTap: () async { final DateTime? value = await _pickDateTime(sheetContext, split); if (value != null) setSheetState(() => split = value); }),
            TextField(controller: secondNote, decoration: const InputDecoration(labelText: 'Second activity description')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                try {
                  await ref.read(timelineControllerProvider.notifier).splitEntry(entryId: entry.id, splitAt: split, secondNote: secondNote.text);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                } on StateError catch (error) {
                  if (sheetContext.mounted) ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(error.message)));
                } on ArgumentError catch (error) {
                  if (sheetContext.mounted) ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(error.message?.toString() ?? 'Choose a time inside the activity.')));
                }
              },
              child: const Text('Split activity'),
            ),
          ]),
        ),
      ),
    );
    secondNote.dispose();
  }

  Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
    final DateTime? date = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (date == null || !context.mounted) return null;
    final TimeOfDay? time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    return time == null ? null : DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _dateTimeLabel(BuildContext context, DateTime value) => '${value.day}/${value.month}/${value.year} ${TimeOfDay.fromDateTime(value).format(context)}';

  List<_TimelineRow> _timelineRows(DateTime day, List<TimelineItem> entries, TrackingSettings tracking) {
    if (!tracking.isWorkingDay(day)) {
      return entries
          .map<_TimelineRow>((TimelineItem entry) => _TimelineRow.entry(entry))
          .toList(growable: false);
    }
    final DateTime workStart = DateTime(day.year, day.month, day.day, tracking.startHour).toUtc();
    final DateTime workEnd = DateTime(day.year, day.month, day.day, tracking.endHour).toUtc();
    DateTime cursor = workStart;
    final List<_TimelineRow> rows = <_TimelineRow>[];
    for (final TimelineItem entry in entries) {
      final DateTime start = entry.startAt.isBefore(workStart) ? workStart : entry.startAt;
      if (!start.isBefore(workEnd)) continue;
      if (start.difference(cursor) >= const Duration(minutes: 15)) {
        rows.add(_TimelineRow.gap(cursor, start));
      }
      rows.add(_TimelineRow.entry(entry));
      final DateTime rawEnd = entry.endAt ?? DateTime.now().toUtc();
      final DateTime end = rawEnd.isAfter(workEnd) ? workEnd : rawEnd;
      if (end.isAfter(cursor)) cursor = end;
    }
    if (workEnd.difference(cursor) >= const Duration(minutes: 15)) {
      rows.add(_TimelineRow.gap(cursor, workEnd));
    }
    return rows;
  }
}

class _TimelineRow {
  const _TimelineRow.entry(this.entry) : start = null, end = null;
  const _TimelineRow.gap(this.start, this.end) : entry = null;
  final TimelineItem? entry;
  final DateTime? start;
  final DateTime? end;
}

class _GapCard extends StatelessWidget {
  const _GapCard({required this.start, required this.end, required this.onClassify});
  final DateTime start;
  final DateTime end;
  final Future<void> Function(String type) onClassify;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: ListTile(
      onTap: () async {
        final String? type = await showDialog<String>(
          context: context,
          builder: (BuildContext dialogContext) => SimpleDialog(
            title: const Text('What were you doing?'),
            children: <Widget>[
              SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'manual'), child: const Text('Add activity')),
              SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'break'), child: const Text('Mark Break')),
              SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'meeting'), child: const Text('Mark Meeting')),
            ],
          ),
        );
        if (type != null) await onClassify(type);
      },
      leading: const Icon(Icons.help_outline_rounded),
      title: const Text('Untracked time'),
      subtitle: Text('${start.toLocal().hour}:${start.toLocal().minute.toString().padLeft(2, '0')} - ${end.toLocal().hour}:${end.toLocal().minute.toString().padLeft(2, '0')}'),
    ),
  );
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onEdit, required this.onSplit, required this.onDelete});
  final TimelineItem entry;
  final Future<void> Function() onEdit;
  final Future<void> Function() onSplit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.timeline_rounded),
      title: Text(entry.taskTitle ?? entry.note ?? 'Activity'),
      subtitle: Text('${_time(context, entry.startAt)} - ${entry.endAt == null ? 'Running' : _time(context, entry.endAt!)}${entry.categoryName == null ? '' : ' | ${entry.categoryName}'}'),
      trailing: entry.endAt == null ? null : PopupMenuButton<String>(
        tooltip: 'Activity actions',
        onSelected: (String action) async {
          if (action == 'edit') return onEdit();
          if (action == 'split') return onSplit();
          final bool? confirmed = await showDialog<bool>(
            context: context,
            builder: (BuildContext dialogContext) => AlertDialog(
              title: const Text('Remove entry?'),
              content: const Text('The entry will be removed from the timeline but kept for future recovery.'),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep')),
                FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
              ],
            ),
          );
          if (confirmed == true) await onDelete();
        },
        itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
          PopupMenuItem(value: 'edit', child: Text('Edit / reassign')),
          PopupMenuItem(value: 'split', child: Text('Split activity')),
          PopupMenuItem(value: 'delete', child: Text('Remove')),
        ],
      ),
    ),
  );
  String _time(BuildContext context, DateTime value) => TimeOfDay.fromDateTime(value.toLocal()).format(context);
}
