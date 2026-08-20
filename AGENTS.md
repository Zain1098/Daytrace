# AGENTS.md - DayTrace AI Coding Contract

Read these files before changing code:
1. `PRD.md`
2. `ARCHITECTURE.md`
3. `DATABASE_SCHEMA.sql`
4. `IMPLEMENTATION_PLAN.md`
5. `DECISIONS.md`

## Product Identity
DayTrace is an Android-only, offline-first personal task planner, activity timer, timeline, reminder, and report generator. It is not an ERP, team tracker, attendance system, or generic social productivity platform.

## Mandatory Workflow
1. Inspect current repository structure and relevant files.
2. State the smallest vertical slice being implemented.
3. Identify PRD acceptance criteria covered.
4. Implement production-quality code, migrations, and tests.
5. Run formatter, analyzer, tests, and an Android debug build when environment allows.
6. Report changed files, commands/results, assumptions, risks, and the next task.

## Hard Rules
- Preserve offline-first behavior.
- No mandatory authentication.
- Database is source of truth.
- Only one open time entry globally.
- Persist timer transitions transactionally.
- Use UTC timestamps in storage.
- Do not put plugin/database/network logic in widgets.
- Do not commit secrets or place permanent AI provider keys in the APK.
- Do not claim a placeholder or untested flow is complete.
- Do not make destructive schema changes. Add versioned Drift migrations.
- Do not expand scope without recording a decision.
- Reuse the same use cases for notification actions and screen actions.

## UI Priorities
Fast capture, readable timeline, large touch targets, clear active-state visibility, minimal setup, and graceful permission failures.

## Completion Response Template
- Goal completed
- PRD criteria satisfied
- Files changed
- Tests/build commands and results
- Known limitations
- Recommended next implementation step
