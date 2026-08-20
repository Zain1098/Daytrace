import 'package:daytrace/features/onboarding/application/onboarding_controller.dart';
import 'package:daytrace/features/settings/data/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;
  bool _isCompleting = false;
  TrackingSettings? _trackingSettings;

  static const List<_OnboardingPage> _pages = <_OnboardingPage>[
    _OnboardingPage(
      icon: Icons.add_task_rounded,
      title: 'Capture in seconds',
      description:
          'Add a task whenever it comes to mind, then organize the details later.',
    ),
    _OnboardingPage(
      icon: Icons.timer_outlined,
      title: 'Track the real work',
      description:
          'Start, pause, and complete activities. DayTrace keeps one accurate timer at a time.',
    ),
    _OnboardingPage(
      icon: Icons.insights_outlined,
      title: 'Review your day',
      description:
          'See your timeline, find gaps, and create a clear report of what you did.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _complete({required bool requestNotifications}) async {
    if (_isCompleting) return;
    setState(() => _isCompleting = true);
    try {
      await ref
          .read(onboardingProvider.notifier)
          .complete(
            requestNotifications: requestNotifications,
            trackingSettings: _trackingSettings,
          );
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _configureTracking() async {
    final TrackingSettings? selection = await showDialog<TrackingSettings>(
      context: context,
      builder: (BuildContext context) => _TrackingSetupDialog(
        initial: _trackingSettings ?? const TrackingSettings(),
      ),
    );
    if (!mounted || selection == null) return;
    setState(() => _trackingSettings = selection);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isLastPage = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            children: <Widget>[
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: _isCompleting
                      ? null
                      : () => _complete(requestNotifications: false),
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (int page) => setState(() => _page = page),
                  itemBuilder: (BuildContext context, int index) =>
                      _OnboardingPageView(page: _pages[index]),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(
                  _pages.length,
                  (int index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: index == _page ? 28 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: index == _page
                          ? colors.primary
                          : colors.surfaceContainerHighest,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (!isLastPage)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    child: const Text('Continue'),
                  ),
                )
              else
                _CompletionActions(
                  isCompleting: _isCompleting,
                  hasTrackingSetup: _trackingSettings != null,
                  onConfigureTracking: _configureTracking,
                  onEnableNotifications: () =>
                      _complete(requestNotifications: true),
                  onContinueWithoutNotifications: () =>
                      _complete(requestNotifications: false),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({required this.page});

  final _OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(page.icon, size: 56, color: colors.onPrimaryContainer),
            ),
            const SizedBox(height: 40),
            Text(
              page.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              page.description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletionActions extends StatelessWidget {
  const _CompletionActions({
    required this.isCompleting,
    required this.hasTrackingSetup,
    required this.onConfigureTracking,
    required this.onEnableNotifications,
    required this.onContinueWithoutNotifications,
  });

  final bool isCompleting;
  final bool hasTrackingSetup;
  final VoidCallback onConfigureTracking;
  final VoidCallback onEnableNotifications;
  final VoidCallback onContinueWithoutNotifications;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Enable notifications for task reminders and optional time prompts. You can change this anytime in Settings.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: isCompleting ? null : onConfigureTracking,
            icon: const Icon(Icons.tune_rounded),
            label: Text(
              hasTrackingSetup ? 'Tracking hours configured' : 'Set tracking hours (optional)',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: isCompleting ? null : onEnableNotifications,
            child: const Text('Enable notifications'),
          ),
          TextButton(
            onPressed: isCompleting ? null : onContinueWithoutNotifications,
            child: const Text('Continue without notifications'),
          ),
        ],
      );
}

class _TrackingSetupDialog extends StatefulWidget {
  const _TrackingSetupDialog({required this.initial});

  final TrackingSettings initial;

  @override
  State<_TrackingSetupDialog> createState() => _TrackingSetupDialogState();
}

class _TrackingSetupDialogState extends State<_TrackingSetupDialog> {
  late int _start = widget.initial.startHour;
  late int _end = widget.initial.endHour;
  late int _prompt = widget.initial.promptMinutes;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Tracking hours'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('Smart prompts only run inside these hours.'),
              const SizedBox(height: 12),
              _HourSelector(
                label: 'Start',
                value: _start,
                onChanged: (int value) => setState(() => _start = value),
              ),
              _HourSelector(
                label: 'End',
                value: _end,
                onChanged: (int value) => setState(() => _end = value),
              ),
              DropdownButtonFormField<int>(
                initialValue: _prompt,
                decoration: const InputDecoration(labelText: 'Prompt interval'),
                items: const <DropdownMenuItem<int>>[
                  DropdownMenuItem(value: 0, child: Text('Off')),
                  DropdownMenuItem(value: 30, child: Text('30 minutes')),
                  DropdownMenuItem(value: 45, child: Text('45 minutes')),
                  DropdownMenuItem(value: 60, child: Text('60 minutes')),
                  DropdownMenuItem(value: 90, child: Text('90 minutes')),
                  DropdownMenuItem(value: 120, child: Text('120 minutes')),
                ],
                onChanged: (int? value) => setState(() => _prompt = value ?? 60),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _end <= _start
                ? null
                : () => Navigator.pop(
                      context,
                      TrackingSettings(
                        startHour: _start,
                        endHour: _end,
                        promptMinutes: _prompt,
                      ),
                    ),
            child: const Text('Use these hours'),
          ),
        ],
      );
}

class _HourSelector extends StatelessWidget {
  const _HourSelector({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: List<DropdownMenuItem<int>>.generate(
          24,
          (int hour) => DropdownMenuItem<int>(
            value: hour,
            child: Text('${hour.toString().padLeft(2, '0')}:00'),
          ),
        ),
        onChanged: (int? value) {
          if (value != null) onChanged(value);
        },
      );

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}
