import 'package:daytrace/features/reports/presentation/reports_screen.dart';
import 'package:daytrace/features/settings/presentation/settings_screen.dart';
import 'package:daytrace/features/tasks/presentation/tasks_screen.dart';
import 'package:daytrace/features/timeline/presentation/timeline_screen.dart';
import 'package:daytrace/features/today/presentation/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/today',
  routes: <RouteBase>[
    ShellRoute(
      builder: (BuildContext context, GoRouterState state, Widget child) =>
          _AppShell(child: child),
      routes: <RouteBase>[
        GoRoute(
          path: '/today',
          builder: (BuildContext context, GoRouterState state) =>
              const TodayScreen(),
        ),
        GoRoute(
          path: '/tasks',
          builder: (BuildContext context, GoRouterState state) => const TasksScreen(),
        ),
        GoRoute(
          path: '/timeline',
          builder: (BuildContext context, GoRouterState state) => const TimelineScreen(),
        ),
        GoRoute(
          path: '/reports',
          builder: (BuildContext context, GoRouterState state) => const ReportsScreen(),
        ),
        GoRoute(path: '/settings', builder: (BuildContext context, GoRouterState state) => const SettingsScreen()),
        ..._placeholderRoutes,
      ],
    ),
  ],
);

final List<GoRoute> _placeholderRoutes = <GoRoute>[
  for (final _NavigationItem item in _navigationItems.skip(5))
    GoRoute(
      path: item.path,
      builder: (BuildContext context, GoRouterState state) =>
          _PlaceholderScreen(title: item.label, icon: item.icon),
    ),
];

class _AppShell extends StatelessWidget {
  const _AppShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    final int currentIndex = _navigationItems.indexWhere(
      (_NavigationItem item) => item.path == location,
    );
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex < 0 ? 0 : currentIndex,
        onDestinationSelected: (int index) =>
            context.go(_navigationItems[index].path),
        destinations: <NavigationDestination>[
          for (final _NavigationItem item in _navigationItems)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text('$title will be added in its planned phase.'),
        ],
      ),
    ),
  );
}

class _NavigationItem {
  const _NavigationItem(this.label, this.path, this.icon, this.selectedIcon);

  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_NavigationItem> _navigationItems = <_NavigationItem>[
  _NavigationItem('Today', '/today', Icons.today_outlined, Icons.today_rounded),
  _NavigationItem('Tasks', '/tasks', Icons.checklist_outlined, Icons.checklist_rounded),
  _NavigationItem('Timeline', '/timeline', Icons.timeline_outlined, Icons.timeline_rounded),
  _NavigationItem('Reports', '/reports', Icons.assessment_outlined, Icons.assessment_rounded),
  _NavigationItem('Settings', '/settings', Icons.settings_outlined, Icons.settings_rounded),
];
