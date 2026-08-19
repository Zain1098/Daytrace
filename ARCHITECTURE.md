# DayTrace Architecture

## Architectural Goal
Build an Android-only, offline-first Flutter application whose core timer, task, timeline, reminder, and reporting behavior remains reliable without network access. Keep interfaces ready for future cloud sync, but do not introduce remote complexity into MVP workflows.

## Layers

### Presentation
- Flutter screens, dialogs, notification action entry points.
- Riverpod Notifiers/AsyncNotifiers expose immutable state.
- Widgets contain rendering and user-event forwarding, not SQL or plugin calls.

### Domain
- Entities: Task, TimeEntry, Category, Reminder, RecurrenceRule, DailyReport.
- Value objects: TaskStatus, Priority, TimeRange, DurationMinutes.
- Use cases: CreateTask, StartTask, PauseTask, ResumeTask, CompleteTask, SwitchTask, EditTimeEntry, GenerateDailyReport, ScheduleReminder.
- Repository contracts live here or in feature domain folders.

### Data/Infrastructure
- Drift database and DAOs.
- Repository implementations.
- Local notification adapter.
- Speech recognition adapter.
- AI summary adapter.
- Backup/export adapter.

## State Ownership
- Database is the source of truth.
- Timer UI derives elapsed time from `start_at` plus current clock. A periodic UI tick may repaint, but must not own duration.
- A single `TimerCoordinator` serializes state changes and uses database transactions.
- Notification actions call the same use cases as UI actions.

## Folder Structure
```text
lib/
  main.dart
  app/
    app.dart
    router.dart
    theme/
  core/
    database/
    errors/
    logging/
    notifications/
    time/
    utils/
  features/
    onboarding/
    categories/
    tasks/
    timer/
    today/
    timeline/
    reminders/
    reports/
    voice/
    ai_summary/
    settings/
    backup/
  shared/
    widgets/
    models/
test/
  unit/
  database/
  widget/
integration_test/
docs/
```

## Dependency Direction
Presentation -> Domain contracts/use cases -> Data implementations. Infrastructure plugins must never be imported directly into feature widgets.

## Timer Transaction Examples
Start task:
1. Query open time entry.
2. If one exists, require an explicit switch decision.
3. Update selected task to in_progress.
4. Insert open time entry.
5. Commit.
6. Schedule/update optional active-timer notification.

Pause task:
1. Find open time entry.
2. Set end_at to now.
3. Mark task paused.
4. Commit.

Complete task:
1. Close open entry if it belongs to task.
2. Mark task completed and set completed_at.
3. Cancel reminders.
4. Commit.

## Time Rules
- Persist UTC timestamps.
- Convert to local time only at presentation/report boundaries.
- Inject a Clock service for tests.
- Reports must clip intervals to the selected local-day boundaries without corrupting original entries.

## Notifications
- Stable integer notification IDs derived from stored identifiers through a collision-safe registry.
- Payload contains action type and entity ID, not private task details when unnecessary.
- Action handlers are idempotent.
- Reschedule future reminders on app startup and reboot receiver execution.

## AI Boundary
`SummaryGenerator` interface:
- `LocalSummaryGenerator`: always available, deterministic.
- `RemoteAiSummaryGenerator`: optional, networked, explicit consent.
The report feature calls local generation first and treats remote text as an enhancement.

## Future Sync Boundary
Repositories use local IDs and update timestamps now. A later sync engine can observe changes without replacing UI/domain code. Do not implement sync queues in MVP unless cloud sync is explicitly added.

## Coding Rules
- Prefer small files and cohesive classes.
- No service locator hidden globals.
- No business logic in build methods.
- No database writes from UI widgets.
- No broad catch blocks that suppress failures.
- Add tests for every bug involving persisted state.
