import 'package:daytrace/features/tasks/data/task_repository.dart';
import 'package:daytrace/features/today/application/today_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final AsyncNotifierProvider<TaskListController, List<TaskItem>>
taskListControllerProvider =
    AsyncNotifierProvider<TaskListController, List<TaskItem>>(
      TaskListController.new,
    );

class TaskListController extends AsyncNotifier<List<TaskItem>> {
  @override
  Future<List<TaskItem>> build() => ref.read(taskRepositoryProvider).loadAllTasks();

  Future<void> refresh() async {
    state = AsyncData(await ref.read(taskRepositoryProvider).loadAllTasks());
  }
}
