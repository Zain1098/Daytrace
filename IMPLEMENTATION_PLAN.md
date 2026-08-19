# DayTrace MVP Implementation Plan

Each phase is a buildable vertical slice. Do not start a later phase while the current gate is red.

## Phase 0 - Repository Foundation
Tasks:
- Create Flutter Android project and Git repository.
- Add strict analysis options and formatting rules.
- Establish feature-first folders and Riverpod setup.
- Add go_router, Drift database shell, Clock abstraction, typed failures, logging.
- Create light/dark themes and reusable loading/error/empty states.
- Copy all documentation into `/docs`; keep `AGENTS.md` at repository root.
- Add CI for format, analyze, and test.

Gate:
- App launches on physical Android device.
- Empty database migration succeeds.
- Analyzer and starter tests pass.

## Phase 1 - Categories, Tasks, and Reliable Timer
Tasks:
- Drift tables/migration for categories, tasks, subtasks, time entries.
- Seed default categories.
- Task repository and use cases.
- Quick Add: title, category, Save, Start Now.
- TimerCoordinator with start/pause/resume/complete/switch transaction rules.
- Today screen active card and today's task list.
- Unit/database/widget tests.

Gate:
- One active entry invariant tested.
- Active timer survives app restart.
- Task can complete with accurate accumulated intervals.

## Phase 2 - Full Task Planning and Reminder Engine
Tasks:
- Priority, description, planned/due time, estimate, subtasks.
- Reminder table and stable notification ID mapping.
- Notification permission UX and channels.
- Schedule/cancel/reschedule reminders.
- Notification actions: Start, Complete, Snooze, Dismiss.
- Recurrence rules and next-occurrence generation.
- Startup/reboot rescheduling strategy.

Gate:
- Editing or completing a task leaves no stale reminder.
- Action handlers are idempotent.
- Denied permission produces helpful in-app state, not failure loops.

## Phase 3 - Timeline, Manual Correction, and Smart Prompts
Tasks:
- Daily timeline query and UI.
- Gap calculation using configured tracking hours.
- Add past activity, Break, Meeting, Untracked.
- Edit/split/delete time entries with overlap validation and undo where possible.
- Working days/hours and quiet-hour settings.
- Inactivity prompt scheduler and actionable notification.

Gate:
- User can reconstruct an incomplete workday safely.
- No accidental overlapping intervals.
- Smart prompts stop outside configured hours and when disabled.

## Phase 4 - Reports and Export
Tasks:
- DailyReport and WeeklyReport domain models.
- Duration clipping/grouping and category totals.
- Deterministic local summary generator.
- Reports screens with date navigation.
- Copy/share text.
- On-device PDF generation and Android sharing.

Gate:
- Report totals match source entries in automated fixtures.
- Cross-midnight entry is calculated correctly.
- PDF opens and is readable on the test device.

## Phase 5 - Voice Entry and Optional AI Summary
Tasks:
- Speech-to-text adapter and permission UX.
- Conservative command parser for Start, Add, and Remind phrases.
- Editable confirmation before mutation when uncertain.
- SummaryGenerator interface and local implementation.
- Optional remote AI implementation via user key in secure storage for development or server proxy interface.
- Consent screen, transmitted-data preview, timeout/error/rate-limit handling.

Gate:
- No continuous listening.
- Manual flows remain available when speech fails.
- AI failure always falls back to local summary.
- No secret exists in committed source or generated APK configuration.

## Phase 6 - Backup, Hardening, and Dogfood APK
Tasks:
- JSON export with schema version.
- Validated replace-all restore with automatic safety backup.
- Search and filters.
- Accessibility pass and text scaling.
- Performance/index review with large fixture data.
- Migration tests, integration tests, and physical-device battery/background QA.
- Signed internal release APK and versioning.
- Create DOGFOOD_CHECKLIST.md.

Gate:
- Restore round trip preserves record counts and relationships.
- Core integration journey passes.
- 30-day dogfood build contains no known data-loss defect.

## AI Task Size Rule
Give the coding agent one phase task or one vertical slice at a time. Do not prompt "build the entire app" in one execution. The documentation removes repeated explanation, but engineering still requires checkpoints. Otherwise the agent will confidently produce a decorative pile of code, humanity's favorite software methodology.

## Recommended First Prompt
Use `MASTER_PROMPT.md`, then ask the agent to execute Phase 0 only.
