import 'package:daytrace/features/settings/data/settings_repository.dart';
import 'package:daytrace/features/backup/data/backup_service.dart';
import 'package:daytrace/features/updates/data/app_update_service.dart';
import 'package:daytrace/features/today/application/today_controller.dart';
import 'package:daytrace/features/ai_summary/data/ai_summary_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final trackingSettingsProvider = FutureProvider<TrackingSettings>((Ref ref) => SettingsRepository(ref.watch(appDatabaseProvider)).loadTracking());

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TrackingSettings> settings = ref.watch(trackingSettingsProvider);
    return Scaffold(appBar: AppBar(title: const Text('Settings')), body: settings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Could not load settings.')),
      data: (TrackingSettings value) => _TrackingSettingsForm(value: value),
    ));
  }
}

class _TrackingSettingsForm extends ConsumerStatefulWidget {
  const _TrackingSettingsForm({required this.value});
  final TrackingSettings value;
  @override ConsumerState<_TrackingSettingsForm> createState() => _TrackingSettingsFormState();
}
class _TrackingSettingsFormState extends ConsumerState<_TrackingSettingsForm> {
  late int start = widget.value.startHour; late int end = widget.value.endHour; late int prompt = widget.value.promptMinutes;
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: <Widget>[
    Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 4),
    const Text('Choose how DayTrace follows light and dark colors.'),
    const SizedBox(height: 12),
    _ThemeModePicker(),
    const SizedBox(height: 32),
    Text('Tracking hours', style: Theme.of(context).textTheme.titleMedium),
    const Text('Timeline gaps and smart prompts only apply inside these hours.'),
    DropdownButtonFormField<int>(initialValue: start, decoration: const InputDecoration(labelText: 'Start'), items: List.generate(24, (int h) => DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))), onChanged: (int? h) => setState(() => start = h!)),
    DropdownButtonFormField<int>(initialValue: end, decoration: const InputDecoration(labelText: 'End'), items: List.generate(24, (int h) => DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))), onChanged: (int? h) => setState(() => end = h!)),
    const SizedBox(height: 24), Text('Untracked-time prompt', style: Theme.of(context).textTheme.titleMedium),
    DropdownButtonFormField<int>(initialValue: prompt, decoration: const InputDecoration(labelText: 'Prompt interval'), items: const <DropdownMenuItem<int>>[DropdownMenuItem(value: 0, child: Text('Off')), DropdownMenuItem(value: 30, child: Text('30 minutes')), DropdownMenuItem(value: 45, child: Text('45 minutes')), DropdownMenuItem(value: 60, child: Text('60 minutes')), DropdownMenuItem(value: 90, child: Text('90 minutes')), DropdownMenuItem(value: 120, child: Text('120 minutes'))], onChanged: (int? v) => setState(() => prompt = v!)),
    const SizedBox(height: 28), FilledButton(onPressed: end <= start ? null : () async { await SettingsRepository(ref.read(appDatabaseProvider)).saveTracking(TrackingSettings(startHour: start, endHour: end, promptMinutes: prompt)); await ref.read(todayControllerProvider.notifier).refresh(); ref.invalidate(trackingSettingsProvider); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tracking settings saved'))); }, child: const Text('Save settings')),
    const SizedBox(height: 32), Text('Data safety', style: Theme.of(context).textTheme.titleMedium),
    const Text('Create a portable JSON backup before changing devices or restoring app data.'),
    ListTile(leading: const Icon(Icons.backup_outlined), title: const Text('Export backup'), subtitle: const Text('Share a schema-versioned JSON file'), onTap: () async { try { await BackupService(ref.read(appDatabaseProvider)).shareBackup(); } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup could not be created.'))); } }),
    ListTile(leading: const Icon(Icons.settings_backup_restore_rounded), title: const Text('Restore backup'), subtitle: const Text('Replaces local data after an automatic safety backup'), onTap: () async { final bool? confirmed = await showDialog<bool>(context: context, builder: (BuildContext dialog) => AlertDialog(title: const Text('Restore backup?'), content: const Text('Current local data will be replaced. DayTrace creates a safety backup first.'), actions: <Widget>[TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Choose backup'))])); if (confirmed != true || !mounted) return; try { final bool restored = await BackupService(ref.read(appDatabaseProvider)).pickAndRestore(); if (mounted && restored) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup restored. Restart DayTrace to reload all screens.'))); } on FormatException catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message))); } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup could not be restored.'))); } }),
    const SizedBox(height: 32), Text('App updates', style: Theme.of(context).textTheme.titleMedium),
    ListTile(leading: const Icon(Icons.system_update_rounded), title: const Text('Check for update'), subtitle: const Text('Checks the latest GitHub release'), onTap: () => _checkUpdate(context)),
    ListTile(leading: const Icon(Icons.link_rounded), title: const Text('Update source'), subtitle: const Text('GitHub repository and optional direct APK link'), onTap: () => _editUpdateSource(context)),
    const SizedBox(height: 32), Text('Optional AI summary', style: Theme.of(context).textTheme.titleMedium),
    const Text('Use only your own HTTPS proxy. DayTrace never embeds or stores an AI provider key.'),
    ListTile(leading: const Icon(Icons.auto_awesome_outlined), title: const Text('Configure AI proxy'), subtitle: const Text('Disabled until you enable it here'), onTap: () => _editAiProxy(context)),
  ]);

  Future<void> _checkUpdate(BuildContext context) async {
    try { final AppUpdateInfo update = await AppUpdateService(ref.read(appDatabaseProvider)).checkForUpdate(); if (!mounted) return; if (!update.isAvailable) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You are up to date (${update.currentVersion}).'))); return; } final bool? download = await showDialog<bool>(context: context, builder: (BuildContext dialog) => AlertDialog(title: const Text('Update available'), content: Text('${update.latestTag} is available. Current: ${update.currentVersion}.'), actions: <Widget>[TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Later')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Download APK'))])); if (download == true) await AppUpdateService(ref.read(appDatabaseProvider)).openDownload(update.downloadUrl); } on StateError catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message))); } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not check for updates.'))); }
  }

  Future<void> _editUpdateSource(BuildContext context) async {
    final AppUpdateService service = AppUpdateService(ref.read(appDatabaseProvider)); final UpdateConfig config = await service.loadConfig(); final TextEditingController repo = TextEditingController(text: config.repository); final TextEditingController url = TextEditingController(text: config.directApkUrl); await showDialog<void>(context: context, builder: (BuildContext dialog) => AlertDialog(title: const Text('Update source'), content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[TextField(controller: repo, decoration: const InputDecoration(labelText: 'GitHub repository', hintText: 'owner/repository')), TextField(controller: url, decoration: const InputDecoration(labelText: 'Direct APK URL (optional)'), keyboardType: TextInputType.url)]), actions: <Widget>[TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')), FilledButton(onPressed: () async { await service.saveConfig(UpdateConfig(repository: repo.text, directApkUrl: url.text)); if (dialog.mounted) Navigator.pop(dialog); }, child: const Text('Save'))])); repo.dispose(); url.dispose();
  }

  Future<void> _editAiProxy(BuildContext context) async {
    final AiSummaryService service = AiSummaryService(ref.read(appDatabaseProvider));
    final AiSummaryConfig config = await service.loadConfig();
    final TextEditingController endpoint = TextEditingController(text: config.endpoint);
    bool enabled = config.enabled;
    await showDialog<void>(context: context, builder: (BuildContext dialog) => StatefulBuilder(builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(title: const Text('AI summary proxy'), content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      const Text('Your proxy must use HTTPS and accept a report JSON payload, then return {"summary":"..."}. No provider key is saved in DayTrace.'),
      SwitchListTile(value: enabled, onChanged: (bool value) => setDialogState(() => enabled = value), title: const Text('Enable optional AI summary')),
      TextField(controller: endpoint, decoration: const InputDecoration(labelText: 'HTTPS proxy URL'), keyboardType: TextInputType.url),
    ]), actions: <Widget>[TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')), FilledButton(onPressed: () async { await service.saveConfig(AiSummaryConfig(enabled: enabled, endpoint: endpoint.text)); if (dialog.mounted) Navigator.pop(dialog); }, child: const Text('Save'))])));
    endpoint.dispose();
  }
}

class _ThemeModePicker extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ThemeMode> mode = ref.watch(themeModeProvider);
    final ThemeMode selected = mode.value ?? ThemeMode.system;
    return SegmentedButton<ThemeMode>(
      segments: const <ButtonSegment<ThemeMode>>[
        ButtonSegment<ThemeMode>(
          value: ThemeMode.system,
          icon: Icon(Icons.brightness_auto_rounded),
          label: Text('System'),
        ),
        ButtonSegment<ThemeMode>(
          value: ThemeMode.light,
          icon: Icon(Icons.light_mode_outlined),
          label: Text('Light'),
        ),
        ButtonSegment<ThemeMode>(
          value: ThemeMode.dark,
          icon: Icon(Icons.dark_mode_outlined),
          label: Text('Dark'),
        ),
      ],
      selected: <ThemeMode>{selected},
      showSelectedIcon: false,
      onSelectionChanged: mode.isLoading
          ? null
          : (Set<ThemeMode> values) async {
              try {
                await ref.read(themeModeProvider.notifier).select(values.single);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Theme preference could not be saved.')),
                  );
                }
              }
            },
    );
  }
}
import 'package:daytrace/app/theme/theme_mode_controller.dart';
