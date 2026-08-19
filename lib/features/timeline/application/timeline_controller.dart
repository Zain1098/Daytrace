import 'package:daytrace/features/tasks/data/task_repository.dart';
import 'package:daytrace/features/today/application/today_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final NotifierProvider<_TimelineDayNotifier, DateTime> timelineDayProvider =
    NotifierProvider<_TimelineDayNotifier, DateTime>(_TimelineDayNotifier.new);
final NotifierProvider<_TimelineFilterNotifier, TimelineFilter>
    timelineFilterProvider = NotifierProvider<
        _TimelineFilterNotifier,
        TimelineFilter>(_TimelineFilterNotifier.new);

class _TimelineDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();
}

class _TimelineFilterNotifier extends Notifier<TimelineFilter> {
  @override
  TimelineFilter build() => TimelineFilter.all;
}

enum TimelineFilter { all, tracked, untracked, breaks, meetings }
final timelineControllerProvider = AsyncNotifierProvider<TimelineController, List<TimelineItem>>(TimelineController.new);

class TimelineController extends AsyncNotifier<List<TimelineItem>> {
  @override
  Future<List<TimelineItem>> build() {
    ref.watch(timelineDayProvider);
    return _load();
  }

  Future<void> refresh() async => state = AsyncData(await _load());

  void changeDay(int dayOffset) {
    final DateTime current = ref.read(timelineDayProvider);
    ref.read(timelineDayProvider.notifier).state = current.add(Duration(days: dayOffset));
  }

  Future<void> addManualEntry({required DateTime startAt, required DateTime endAt, required String note, String entryType = 'manual'}) async {
    await ref.read(taskRepositoryProvider).createManualEntry(startAt: startAt, endAt: endAt, note: note, entryType: entryType);
    await refresh();
  }

  Future<void> classifyGap({required DateTime startAt, required DateTime endAt, required String entryType}) async {
    await ref.read(taskRepositoryProvider).createManualEntry(
      startAt: startAt,
      endAt: endAt,
      note: entryType == 'break' ? 'Break' : entryType == 'meeting' ? 'Meeting' : 'Past activity',
      entryType: entryType,
    );
    await refresh();
  }

  Future<void> deleteEntry(String entryId) async {
    await ref.read(taskRepositoryProvider).deleteTimeEntry(entryId);
    await refresh();
  }

  Future<void> updateEntry({
    required String entryId,
    required DateTime startAt,
    required DateTime endAt,
    required String note,
    required String entryType,
    String? taskId,
  }) async {
    await ref.read(taskRepositoryProvider).updateTimeEntry(
      entryId: entryId,
      startAt: startAt,
      endAt: endAt,
      note: note,
      entryType: entryType,
      taskId: taskId,
    );
    await refresh();
  }

  Future<void> splitEntry({
    required String entryId,
    required DateTime splitAt,
    String? secondNote,
  }) async {
    await ref.read(taskRepositoryProvider).splitTimeEntry(
      entryId: entryId,
      splitAt: splitAt,
      secondNote: secondNote,
    );
    await refresh();
  }

  Future<List<TimelineItem>> _load() => ref.read(taskRepositoryProvider).loadTimeline(ref.read(timelineDayProvider));
}
