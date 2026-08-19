# DayTrace Decision Log

## D-001 - Android-only MVP
Status: Accepted
Decision: Version 1 targets Android through Flutter.
Reason: Initial user and testing environment are Android; reduces scope.

## D-002 - Offline-first and no mandatory login
Status: Accepted
Decision: Core features use local Drift storage and work without internet or an account.
Reason: Reliability and fast onboarding.

## D-003 - Smart prompts, voice entry, and AI summary included in MVP
Status: Accepted
Decision: These features are included, but voice and AI remain optional and degrade gracefully.
Reason: They materially improve capture and reporting.

## D-004 - Local summary is mandatory; remote AI is enhancement
Status: Accepted
Decision: Reports never depend on an AI provider.
Reason: Cost, privacy, connectivity, and reliability.

## D-005 - Phase 0 local foundation dependencies
Status: Accepted
Decision: Use Riverpod for state boundaries, go_router for declarative
navigation, and Drift/drift_flutter for local persistence. Their resolved
versions are locked in pubspec.lock; typed tables begin in Phase 1.
Reason: These packages match the approved architecture while keeping Phase 0
limited to a buildable, empty local-store shell.

## D-006 - Versioned local schema expansion for Phases 2 and 3
Status: Accepted
Decision: Extend the existing generator-free Drift wrapper through an idempotent
version 3 migration recorded in `schema_migrations`, rather than deleting or
recreating the on-device database.
Reason: Existing dogfood data must survive the approved planning, reminders,
timeline, and smart-prompt expansion. Typed Drift tables remain the planned
future consolidation, but this migration preserves the current architecture.

## D-007 - Version 4 report and backup schema migration
Status: Accepted
Decision: Add `daily_notes` and `generated_summaries` through an additive,
idempotent version 4 migration before exporting a complete backup.
Reason: Backup must include every approved local record type without deleting
or recreating existing dogfood data.

## D-008 - AGP 9-compatible backup file picker
Status: Accepted
Decision: Use `file_picker` 12 and its supported file-handle API for backup
restore, replacing the legacy version 3 Android plugin.
Reason: The legacy plugin depends on the removed `jcenter()` repository and
cannot configure under Android Gradle Plugin 9. The upgrade keeps the same
single-JSON-file restore workflow while using maintained Android tooling.
