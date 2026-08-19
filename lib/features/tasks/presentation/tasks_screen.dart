import 'package:daytrace/features/tasks/application/task_list_controller.dart';
import 'package:daytrace/features/tasks/data/task_repository.dart';
import 'package:daytrace/features/today/application/today_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<TaskItem>> tasks = ref.watch(taskListControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _TaskLoadError(
          onRetry: () => ref.read(taskListControllerProvider.notifier).refresh(),
        ),
        data: (List<TaskItem> items) {
          final List<TaskItem> filtered = items.where((TaskItem task) {
            final String needle = query.trim().toLowerCase();
            return needle.isEmpty || task.title.toLowerCase().contains(needle) || (task.categoryName?.toLowerCase().contains(needle) ?? false) || task.status.contains(needle);
          }).toList(growable: false);
          return RefreshIndicator(
          onRefresh: () => ref.read(taskListControllerProvider.notifier).refresh(),
          child: items.isEmpty
              ? const _TaskEmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: <Widget>[
                    TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search tasks, category or status'), onChanged: (String value) => setState(() => query = value)),
                    const SizedBox(height: 16),
                    if (filtered.isEmpty) const Padding(padding: EdgeInsets.only(top: 32), child: Center(child: Text('No matching tasks.'))),
                    for (final _TaskSection section in _sections(filtered)) ...<Widget>[
                      Text(section.title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        child: Column(
                          children: section.tasks
                              .map((TaskItem task) => _TaskRow(task: task))
                              .toList(growable: false),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
        );
        },
      ),
    );
  }

  List<_TaskSection> _sections(List<TaskItem> tasks) {
    const List<(String, String)> groups = <(String, String)>[
      ('in_progress', 'In progress'),
      ('paused', 'Paused'),
      ('planned', 'Planned'),
      ('completed', 'Completed'),
      ('cancelled', 'Cancelled'),
    ];
    return <_TaskSection>[
      for (final (String status, String title) in groups)
        if (tasks.any((TaskItem task) => task.status == status))
          _TaskSection(
            title: title,
            tasks: tasks
                .where((TaskItem task) => task.status == status)
                .toList(growable: false),
          ),
    ];
  }
}

class _TaskSection {
  const _TaskSection({required this.title, required this.tasks});

  final String title;
  final List<TaskItem> tasks;
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color categoryColor = task.categoryColorValue == null
        ? Theme.of(context).colorScheme.primary
        : Color(task.categoryColorValue!);
    return ListTile(
      onTap: () async {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (BuildContext context) => _TaskDetailsSheet(taskId: task.id),
        );
        ref.read(taskListControllerProvider.notifier).refresh();
      },
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: categoryColor.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(_statusIcon(task.status), color: categoryColor),
      ),
      title: Text(task.title),
      subtitle: Text(task.categoryName ?? 'No category'),
    );
  }

  IconData _statusIcon(String status) => switch (status) {
    'in_progress' => Icons.play_circle_fill_rounded,
    'paused' => Icons.pause_circle_outline_rounded,
    'completed' => Icons.check_circle_outline_rounded,
    'cancelled' => Icons.cancel_outlined,
    _ => Icons.radio_button_unchecked_rounded,
  };
}

class _TaskDetailsSheet extends ConsumerStatefulWidget {
  const _TaskDetailsSheet({required this.taskId});

  final String taskId;

  @override
  ConsumerState<_TaskDetailsSheet> createState() => _TaskDetailsSheetState();
}

class _TaskDetailsSheetState extends ConsumerState<_TaskDetailsSheet> {
  late Future<TaskDetails> _details;

  @override
  void initState() {
    super.initState();
    _details = _load();
  }

  Future<TaskDetails> _load() =>
      ref.read(taskRepositoryProvider).loadTaskDetails(widget.taskId);

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FutureBuilder<TaskDetails>(
      future: _details,
      builder: (BuildContext context, AsyncSnapshot<TaskDetails> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Text('This task is no longer available.'),
          );
        }
        final TaskDetails details = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(details.title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (details.categoryName != null) Chip(label: Text(details.categoryName!)),
                    Chip(label: Text(details.priority.toUpperCase())),
                    if (details.recurrenceLabel != null)
                      Chip(
                        avatar: const Icon(Icons.repeat_rounded, size: 18),
                        label: Text(details.recurrenceLabel!),
                      ),
                  ],
                ),
                if (details.description != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(details.description!),
                ],
                if (details.dueAt != null || details.estimatedMinutes != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    <String>[
                      if (details.dueAt != null) 'Due ${_dateTimeLabel(details.dueAt!)}',
                      if (details.estimatedMinutes != null) '${details.estimatedMinutes} min estimated',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 24),
                Text('Subtasks', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                if (details.subtasks.isEmpty)
                  const Text('No subtasks were added.')
                else
                  for (final SubtaskItem subtask in details.subtasks)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: subtask.isCompleted,
                      title: Text(
                        subtask.title,
                        style: TextStyle(
                          decoration: subtask.isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      onChanged: _canEditSubtasks(details.status)
                          ? (bool? value) => _toggleSubtask(subtask, value ?? false)
                          : null,
                    ),
              ],
            ),
          ),
        );
      },
    ),
  );

  bool _canEditSubtasks(String status) =>
      <String>['planned', 'paused', 'in_progress'].contains(status);

  Future<void> _toggleSubtask(SubtaskItem subtask, bool completed) async {
    try {
      await ref.read(taskRepositoryProvider).setSubtaskCompleted(
        subtaskId: subtask.id,
        completed: completed,
      );
      if (mounted) setState(() => _details = _load());
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  String _dateTimeLabel(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.day}/${local.month}/${local.year} ${TimeOfDay.fromDateTime(local).format(context)}';
  }
}

class _TaskEmptyState extends StatelessWidget {
  const _TaskEmptyState();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text('Your saved tasks will appear here.'),
    ),
  );
}

class _TaskLoadError extends StatelessWidget {
  const _TaskLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Try again'),
    ),
  );
}
