import 'dart:async';

import 'package:daytrace/core/voice/voice_capture_service.dart';
import 'package:daytrace/core/voice/voice_command.dart';
import 'package:daytrace/features/tasks/data/task_repository.dart';
import 'package:daytrace/features/today/application/today_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(
      smartPromptOpenRequestProvider,
      (int? previous, int next) {
        if (next > 0 && next != previous) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) _showQuickAdd(context, ref, startNow: true);
          });
        }
      },
      fireImmediately: true,
    );
    ref.listen<int>(
      smartPromptPastActivityRequestProvider,
      (int? previous, int next) {
        if (next > 0 && next != previous) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/timeline');
          });
        }
      },
      fireImmediately: true,
    );
    ref.listen<AsyncValue<int>>(widgetQuickAddProvider, (
      AsyncValue<int>? previous,
      AsyncValue<int> next,
    ) {
      if (next.value != null && next.value != previous?.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) _showQuickAdd(context, ref, startNow: true);
        });
      }
    });
    final DateTime now = DateTime.now();
    final ColorScheme colors = Theme.of(context).colorScheme;
    final AsyncValue<TodayData> today = ref.watch(todayControllerProvider);
    final TodayData? data = today.value;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 104),
          children: <Widget>[
            _Header(date: now),
            const SizedBox(height: 24),
            _FocusCard(
              active: data?.active,
              onStart: () => _showQuickAdd(context, ref, startNow: true),
              onPause: () => _runTimerAction(context, ref, pause: true),
              onComplete: () => _runTimerAction(context, ref, pause: false),
            ),
            const SizedBox(height: 24),
            Text('Today at a glance', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _SummaryGrid(data: data),
            const SizedBox(height: 28),
            Row(
              children: <Widget>[
                Text('Your plan', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  onPressed: () => _showQuickAdd(context, ref),
                  child: const Text('Add task'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _PlanEmptyState(
              foreground: colors.onSurface,
              data: data,
              onAdd: () => _showQuickAdd(context, ref),
              onResume: (TaskItem task) => _resumeTask(context, ref, task),
              onStart: (TaskItem task) => _startTask(context, ref, task),
              onComplete: (TaskItem task) => _completeTask(context, ref, task),
              onCancel: (TaskItem task) => _confirmCancelTask(context, ref, task),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showQuickAdd(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Quick add'),
      ),
    );
  }

  void _showQuickAdd(BuildContext context, WidgetRef ref, {bool startNow = false}) {
    final TextEditingController controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: _QuickAddSheet(
            controller: controller,
            startNow: startNow,
            onSave: (_TaskPlanningDraft draft) async {
            try {
              final TodayController todayController = ref.read(todayControllerProvider.notifier);
              final bool shouldStartNow = draft.startNow;
              if (draft.scheduleReminder &&
                  !await todayController.requestNotificationPermission()) {
                if (sheetContext.mounted) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(
                      content: Text('Notifications are off. Allow them to set a reminder.'),
                    ),
                  );
                }
                return;
              }
              await todayController.createTask(
                    title: controller.text,
                    startNow: shouldStartNow,
                    categoryId: draft.categoryId,
                    description: draft.description,
                    priority: draft.priority,
                    dueAt: draft.dueAt,
                    estimatedMinutes: draft.estimatedMinutes,
                    subtaskTitles: draft.subtaskTitles,
                    recurrence: draft.recurrence,
                    scheduleReminder: draft.scheduleReminder,
                  );
              if (!sheetContext.mounted) return;
              Navigator.of(sheetContext).pop();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(shouldStartNow ? 'Activity started.' : 'Task saved.')),
              );
            } on ArgumentError catch (error) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(content: Text(error.message?.toString() ?? 'Enter a title.')),
              );
            } on StateError catch (error) {
              if (!shouldStartNow) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text(error.message)),
                );
                return;
              }
              final String taskTitle = controller.text;
              Navigator.of(sheetContext).pop();
              if (!context.mounted) return;
              _showSwitchDialog(context, ref, taskTitle);
            }
            },
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _runTimerAction(
    BuildContext context,
    WidgetRef ref, {
    required bool pause,
  }) async {
    try {
      final TodayController controller = ref.read(todayControllerProvider.notifier);
      if (pause) {
        await controller.pauseActiveTask();
      } else {
        await controller.completeActiveTask();
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pause ? 'Activity paused.' : 'Activity completed.')),
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _resumeTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    try {
      await ref.read(todayControllerProvider.notifier).resumeTask(task.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${task.title} resumed.')),
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _startTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    try {
      await ref.read(todayControllerProvider.notifier).startTask(task.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${task.title} started.')),
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      _showSwitchExistingTaskDialog(context, ref, task, error.message);
    }
  }

  Future<void> _completeTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    try {
      await ref.read(todayControllerProvider.notifier).completeTask(task.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${task.title} completed.')),
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _confirmCancelTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        icon: const Icon(Icons.cancel_outlined),
        title: const Text('Cancel task?'),
        content: Text('${task.title} will be removed from your active plan. Recorded time will stay intact.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep task'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel task'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(todayControllerProvider.notifier).cancelTask(task.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${task.title} cancelled.')),
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _showSwitchDialog(
    BuildContext context,
    WidgetRef ref,
    String title,
  ) {
    showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      icon: const Icon(Icons.swap_horiz_rounded),
      title: const Text('Switch activity?'),
      content: Text('You already have an activity running. What should happen before $title starts?'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => _switchTask(
            context,
            dialogContext,
            ref,
            title,
            ActiveTaskDisposition.pause,
          ),
          child: const Text('Pause current'),
        ),
        FilledButton(
          onPressed: () => _switchTask(
            context,
            dialogContext,
            ref,
            title,
            ActiveTaskDisposition.complete,
          ),
          child: const Text('Complete current'),
        ),
      ],
    ),
    );
  }

  void _showSwitchExistingTaskDialog(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
    String message,
  ) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        icon: const Icon(Icons.swap_horiz_rounded),
        title: const Text('Switch activity?'),
        content: Text('$message\n\nWhat should happen before ${task.title} starts?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => _switchExistingTask(
              context,
              dialogContext,
              ref,
              task,
              ActiveTaskDisposition.pause,
            ),
            child: const Text('Pause current'),
          ),
          FilledButton(
            onPressed: () => _switchExistingTask(
              context,
              dialogContext,
              ref,
              task,
              ActiveTaskDisposition.complete,
            ),
            child: const Text('Complete current'),
          ),
        ],
      ),
    );
  }

  Future<void> _switchTask(
    BuildContext context,
    BuildContext dialogContext,
    WidgetRef ref,
    String title,
    ActiveTaskDisposition disposition,
  ) async {
    try {
      await ref.read(todayControllerProvider.notifier).switchToNewTask(
            title: title,
            disposition: disposition,
          );
      if (!dialogContext.mounted) return;
      Navigator.of(dialogContext).pop();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title started.')),
      );
    } on StateError catch (error) {
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<void> _switchExistingTask(
    BuildContext context,
    BuildContext dialogContext,
    WidgetRef ref,
    TaskItem task,
    ActiveTaskDisposition disposition,
  ) async {
    try {
      await ref.read(todayControllerProvider.notifier).switchToTask(
            taskId: task.id,
            disposition: disposition,
          );
      if (!dialogContext.mounted) return;
      Navigator.of(dialogContext).pop();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${task.title} started.')),
      );
    } on StateError catch (error) {
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }
}

class _QuickAddSheet extends ConsumerStatefulWidget {
  const _QuickAddSheet({
    required this.controller,
    required this.startNow,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool startNow;
  final Future<void> Function(_TaskPlanningDraft draft) onSave;

  @override
  ConsumerState<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<_QuickAddSheet> {
  String? _categoryId;
  String _priority = 'medium';
  DateTime? _dueAt;
  bool _scheduleReminder = false;
  late final Future<List<CategoryItem>> _categories;
  late final TextEditingController _descriptionController;
  late final TextEditingController _estimateController;
  late final TextEditingController _subtasksController;
  String _recurrence = 'none';
  final Set<int> _selectedWeekdays = <int>{};
  bool _listening = false;
  bool _voiceStartNow = false;

  @override
  void initState() {
    super.initState();
    _categories = ref.read(todayControllerProvider.notifier).loadCategories();
    _descriptionController = TextEditingController();
    _estimateController = TextEditingController();
    _subtasksController = TextEditingController();
  }

  @override
  void dispose() {
    unawaited(ref.read(voiceCaptureServiceProvider).stop());
    _descriptionController.dispose();
    _estimateController.dispose();
    _subtasksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        (widget.startNow || _voiceStartNow) ? 'Start an activity' : 'Quick add',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(
        (widget.startNow || _voiceStartNow)
            ? 'Give this activity a clear title before starting the timer.'
            : 'Capture the task first. You can organise the details later.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 20),
      TextField(
        controller: widget.controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: 'What do you need to do?',
          prefixIcon: Icon(Icons.edit_outlined),
          suffixIcon: IconButton(
            tooltip: _listening ? 'Stop listening' : 'Dictate task title',
            icon: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded),
            onPressed: _toggleVoice,
          ),
        ),
      ),
      const SizedBox(height: 16),
      FutureBuilder<List<CategoryItem>>(
        future: _categories,
        builder: (BuildContext context, AsyncSnapshot<List<CategoryItem>> snapshot) {
          final List<CategoryItem> categories = snapshot.data ?? const <CategoryItem>[];
          if (categories.isEmpty) return const SizedBox.shrink();
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories.map((CategoryItem category) => ChoiceChip(
              label: Text(category.name),
              selected: _categoryId == category.id,
              onSelected: (bool selected) => setState(
                () => _categoryId = selected ? category.id : null,
              ),
            )).toList(growable: false),
          );
        },
      ),
      const SizedBox(height: 8),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Plan details'),
        children: <Widget>[
          TextField(
            controller: _descriptionController,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'low', child: Text('Low')),
              DropdownMenuItem(value: 'medium', child: Text('Medium')),
              DropdownMenuItem(value: 'high', child: Text('High')),
              DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
            ],
            onChanged: (String? value) => setState(() => _priority = value ?? 'medium'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _estimateController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Estimated minutes',
              suffixText: 'min',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickDueAt,
            icon: const Icon(Icons.schedule_outlined),
            label: Text(_dueAt == null ? 'Set due date and time' : _dueLabel(_dueAt!)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _scheduleReminder,
            onChanged: _dueAt == null ? null : (bool value) => setState(() => _scheduleReminder = value),
            title: const Text('Remind me at due time'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _recurrence,
            decoration: const InputDecoration(labelText: 'Repeat'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'none', child: Text('Does not repeat')),
              DropdownMenuItem(value: 'daily', child: Text('Daily')),
              DropdownMenuItem(value: 'weekdays', child: Text('Selected weekdays')),
              DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
            ],
            onChanged: (String? value) => setState(() => _recurrence = value ?? 'none'),
          ),
          if (_recurrence == 'weekdays') ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: <Widget>[
                for (final (int weekday, String label) in <(int, String)>[
                  (1, 'M'), (2, 'T'), (3, 'W'), (4, 'T'), (5, 'F'), (6, 'S'), (7, 'S'),
                ])
                  FilterChip(
                    label: Text(label),
                    selected: _selectedWeekdays.contains(weekday),
                    onSelected: (bool selected) => setState(() {
                      if (selected) {
                        _selectedWeekdays.add(weekday);
                      } else {
                        _selectedWeekdays.remove(weekday);
                      }
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _subtasksController,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Subtasks',
              hintText: 'One item per line',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () {
            if (_recurrence == 'weekdays' && _selectedWeekdays.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Choose at least one weekday for this repeat.')),
              );
              return;
            }
            final String estimateText = _estimateController.text.trim();
            final int? estimatedMinutes = estimateText.isEmpty
                ? null
                : int.tryParse(estimateText);
            if (estimateText.isNotEmpty && estimatedMinutes == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Estimated duration must be a whole number.')),
              );
              return;
            }
            widget.onSave(_TaskPlanningDraft(
              startNow: widget.startNow || _voiceStartNow,
              categoryId: _categoryId,
              description: _descriptionController.text,
              priority: _priority,
              dueAt: _dueAt,
              estimatedMinutes: estimatedMinutes,
              subtaskTitles: _subtasksController.text.split('\n'),
              recurrence: _recurrenceDraft(),
              scheduleReminder: _scheduleReminder,
            ));
          },
          icon: Icon(
            (widget.startNow || _voiceStartNow)
                ? Icons.play_arrow_rounded
                : Icons.add_task_rounded,
          ),
          label: Text(
            (widget.startNow || _voiceStartNow) ? 'Start activity' : 'Save task',
          ),
        ),
      ),
    ],
  );

  Future<void> _pickDueAt() async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: _dueAt == null ? TimeOfDay.fromDateTime(now) : TimeOfDay.fromDateTime(_dueAt!),
    );
    if (time == null || !mounted) return;
    setState(() => _dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _toggleVoice() async {
    final VoiceCaptureService voice = ref.read(voiceCaptureServiceProvider);
    if (_listening) {
      await voice.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final bool started = await voice.start(onResult: (String transcript, bool isFinal) {
      final VoiceCommand command = VoiceCommand.parse(transcript);
      widget.controller.text = command.title;
      widget.controller.selection = TextSelection.collapsed(offset: command.title.length);
      if (mounted) {
        setState(() {
          _voiceStartNow = command.intent == VoiceCommandIntent.startTask;
          if (isFinal) _listening = false;
        });
      }
    });
    if (!mounted) return;
    setState(() => _listening = started);
    if (!started) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission or speech recognition is unavailable. You can still type the task.')));
  }

  String _dueLabel(DateTime dueAt) =>
      'Due ${dueAt.day}/${dueAt.month} at ${TimeOfDay.fromDateTime(dueAt).format(context)}';

  RecurrenceDraft? _recurrenceDraft() {
    if (_recurrence == 'none') return null;
    final int mask = _selectedWeekdays.fold<int>(0, (int value, int weekday) => value | (1 << (weekday - 1)));
    return RecurrenceDraft(
      frequency: _recurrence == 'weekdays' ? 'weekly' : _recurrence,
      weekdaysMask: _recurrence == 'weekdays' ? mask : null,
      dayOfMonth: _recurrence == 'monthly' ? (_dueAt ?? DateTime.now()).day : null,
    );
  }
}

class _TaskPlanningDraft {
  const _TaskPlanningDraft({
    required this.startNow,
    required this.categoryId,
    required this.description,
    required this.priority,
    required this.dueAt,
    required this.estimatedMinutes,
    required this.subtaskTitles,
    required this.recurrence,
    required this.scheduleReminder,
  });

  final bool startNow;
  final String? categoryId;
  final String description;
  final String priority;
  final DateTime? dueAt;
  final int? estimatedMinutes;
  final List<String> subtaskTitles;
  final RecurrenceDraft? recurrence;
  final bool scheduleReminder;
}

class _Header extends StatelessWidget {
  const _Header({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.auto_awesome_rounded,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Good ${_dayPart()}', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 2),
            Text(_dateLabel(date), style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
      IconButton(onPressed: () {}, icon: const Icon(Icons.search_rounded), tooltip: 'Search'),
      IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded), tooltip: 'Notifications'),
    ],
  );

  String _dayPart() {
    final int hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  String _dateLabel(DateTime value) {
    const List<String> weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const List<String> months = <String>[
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${weekdays[value.weekday - 1]}, ${months[value.month - 1]} ${value.day}';
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({
    required this.active,
    required this.onStart,
    required this.onPause,
    required this.onComplete,
  });

  final ActiveActivity? active;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.play_circle_fill_rounded, color: colors.onPrimary),
              const SizedBox(width: 8),
              Text(
                active == null ? 'Ready when you are' : 'Activity in progress',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.onPrimary.withValues(alpha: .76),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            active?.title ?? 'What are you doing next?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: colors.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (active == null)
            Text(
              'Start with a title. DayTrace will turn it into a clear record of your day.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onPrimary.withValues(alpha: .76),
              ),
            )
          else
            _ActiveTimerDetails(startedAt: active!.startedAt),
          const SizedBox(height: 20),
          if (active == null)
            FilledButton.icon(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                backgroundColor: colors.onPrimary,
                foregroundColor: colors.primary,
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start activity'),
            )
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPause,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.onPrimary,
                      side: BorderSide(
                        color: colors.onPrimary.withValues(alpha: .55),
                      ),
                    ),
                    icon: const Icon(Icons.pause_rounded),
                    label: const Text('Pause'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onComplete,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.onPrimary,
                      foregroundColor: colors.primary,
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Complete'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ActiveTimerDetails extends StatefulWidget {
  const _ActiveTimerDetails({required this.startedAt});

  final DateTime startedAt;

  @override
  State<_ActiveTimerDetails> createState() => _ActiveTimerDetailsState();
}

class _ActiveTimerDetailsState extends State<_ActiveTimerDetails> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Duration elapsed = DateTime.now().toUtc().difference(widget.startedAt);
    return Text(
      '${_durationLabel(elapsed)} tracked - started ${_timeLabel(widget.startedAt)}',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .76),
      ),
    );
  }

  String _durationLabel(Duration duration) {
    final int totalMinutes = duration.isNegative ? 0 : duration.inMinutes;
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes.remainder(60);
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  String _timeLabel(DateTime dateTime) {
    final DateTime local = dateTime.toLocal();
    final int hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final String minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.data});

  final TodayData? data;

  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 2,
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,
    childAspectRatio: 1.72,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: <Widget>[
      _MetricCard(
        icon: Icons.timer_outlined,
        label: 'Tracked time',
        value: data == null ? '-' : _durationLabel(data!.trackedMinutes),
        tone: _MetricTone.primary,
      ),
      _MetricCard(
        icon: Icons.check_circle_outline_rounded,
        label: 'Completed',
        value: '${data?.completedCount ?? 0} tasks',
        tone: _MetricTone.success,
      ),
      _MetricCard(
        icon: Icons.pending_actions_outlined,
        label: 'Still planned',
        value: '${data?.pendingCount ?? 0} tasks',
        tone: _MetricTone.warning,
      ),
      const _MetricCard(
        icon: Icons.timeline_rounded,
        label: 'Time gaps',
        value: 'Next phase',
        tone: _MetricTone.neutral,
      ),
    ],
  );

  String _durationLabel(int totalMinutes) {
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes.remainder(60);
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final _MetricTone tone;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color background = switch (tone) {
      _MetricTone.primary => colors.primaryContainer,
      _MetricTone.success => colors.tertiaryContainer,
      _MetricTone.warning => colors.errorContainer,
      _MetricTone.neutral => colors.surfaceContainerHighest,
    };
    final Color foreground = switch (tone) {
      _MetricTone.primary => colors.onPrimaryContainer,
      _MetricTone.success => colors.onTertiaryContainer,
      _MetricTone.warning => colors.onErrorContainer,
      _MetricTone.neutral => colors.onSurface,
    };
    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Icon(icon, size: 20, color: foreground),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground.withValues(alpha: .78),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _MetricTone { primary, success, warning, neutral }

class _PlanEmptyState extends StatelessWidget {
  const _PlanEmptyState({
    required this.foreground,
    required this.data,
    required this.onAdd,
    required this.onResume,
    required this.onStart,
    required this.onComplete,
    required this.onCancel,
  });

  final Color foreground;
  final TodayData? data;
  final VoidCallback onAdd;
  final ValueChanged<TaskItem> onResume;
  final ValueChanged<TaskItem> onStart;
  final ValueChanged<TaskItem> onComplete;
  final ValueChanged<TaskItem> onCancel;

  @override
  Widget build(BuildContext context) {
    final List<TaskItem> tasks = data?.tasks ?? const <TaskItem>[];
    if (tasks.isNotEmpty) {
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Column(
          children: <Widget>[
            for (final TaskItem task in tasks)
              ListTile(
                leading: _TaskStatusIcon(task: task),
                title: Text(task.title),
                subtitle: Text(_taskSubtitle(task)),
                trailing: task.status == 'in_progress'
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            onPressed: () => task.status == 'paused'
                                ? onResume(task)
                                : onStart(task),
                            tooltip: task.status == 'paused'
                                ? 'Resume ${task.title}'
                                : 'Start ${task.title}',
                            icon: const Icon(Icons.play_arrow_rounded),
                          ),
                          IconButton(
                            onPressed: () => onComplete(task),
                            tooltip: 'Complete ${task.title}',
                            icon: const Icon(Icons.check_circle_outline_rounded),
                          ),
                          PopupMenuButton<_TaskMenuAction>(
                            tooltip: 'More actions for ${task.title}',
                            onSelected: (_TaskMenuAction action) {
                              if (action == _TaskMenuAction.cancel) onCancel(task);
                            },
                            itemBuilder: (BuildContext context) => const <PopupMenuEntry<_TaskMenuAction>>[
                              PopupMenuItem<_TaskMenuAction>(
                                value: _TaskMenuAction.cancel,
                                child: Text('Cancel task'),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
          ],
        ),
      );
    }
    return Card(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.event_available_rounded, color: foreground),
          const SizedBox(height: 16),
          Text('Nothing planned yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Add the next thing on your mind. You can start it whenever you are ready.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('Add your first task')),
        ],
      ),
    ),
  );
  }

  String _taskSubtitle(TaskItem task) {
    final String status = switch (task.status) {
      'in_progress' => 'In progress',
      'paused' => 'Paused',
      _ => 'Planned',
    };
    return task.categoryName == null ? status : '$status - ${task.categoryName}';
  }
}

enum _TaskMenuAction { cancel }

class _TaskStatusIcon extends StatelessWidget {
  const _TaskStatusIcon({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final Color color = task.categoryColorValue == null
        ? Theme.of(context).colorScheme.primary
        : Color(task.categoryColorValue!);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Icon(
        task.status == 'in_progress'
            ? Icons.play_circle_fill_rounded
            : Icons.radio_button_unchecked_rounded,
        color: color,
      ),
    );
  }
}
