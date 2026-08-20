# DayTrace Dogfood Checklist

Run this checklist on a physical Android phone before calling the MVP release-ready.

## Core records

- [ ] Create a task, start it, background the app, force-stop it, then reopen it.
- [ ] Confirm the active timer is restored and there is exactly one open time entry.
- [ ] Pause, resume, complete, cancel, and switch tasks without overlaps.
- [ ] Create, edit, split, reassign, and delete a manual timeline entry.

## Notifications and widget

- [ ] Allow notifications; create a reminder and test Start, Complete, Snooze, and Dismiss.
- [ ] Configure tracking hours and a prompt interval; confirm the smart prompt stays inside those hours.
- [ ] Test smart-prompt Open DayTrace, Start break, Start meeting, and Ignore actions.
- [ ] Test smart-prompt **Add past activity**, and confirm no record is created until the form is saved.
- [ ] Start an activity; verify the ongoing notification shows Pause and Complete, then verify both actions.
- [ ] Confirm end-of-day review only appears on selected working days and opens Reports.
- [ ] Add **DayTrace quick activity** from the Android widget picker; test both widget buttons while the app is closed and already open.
- [ ] Reboot the phone and confirm future reminders and prompts restore where Android permits it.

## Reports and safety

- [ ] Verify daily/weekly totals against known manual entries, including an entry crossing midnight.
- [ ] Open the generated PDF and share both PDF and plain-text report.
- [ ] Export a backup, restore it, and compare record counts/relationships.
- [ ] Type `CLEAR` in Settings; confirm a safety backup is created, data is removed, default categories remain, and first-launch setup returns.
- [ ] Test denied notification and microphone permissions; manual capture must stay usable.

## Release

- [ ] Test System, Light, and Dark modes, including all primary screens and dialogs.
- [ ] Build and inspect a fresh signed APK; record its path, size, timestamp, and SHA-256.
- [ ] Install the fresh APK and use the app for at least one normal workday before wider dogfooding.
