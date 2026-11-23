import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/app_release_info.dart';
import 'models/stress_event.dart';
import 'providers/ble_providers.dart';
import 'providers/health_sync_providers.dart';
import 'providers/stress_providers.dart';
import 'providers/update_providers.dart';
import 'screens/activity_screen.dart';
import 'screens/home_screen.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/sleep_screen.dart';
import 'screens/vitals_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/bottom_nav_bar.dart';
import 'widgets/update_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Force light status bar icons on the dark background
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.navBarBackground,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ProviderScope(child: SmartRingApp()));
}

/// Root application widget.
class SmartRingApp extends StatelessWidget {
  const SmartRingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spike',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainShell(),
    );
  }
}

/// The main shell that hosts the bottom navigation and screen stack.
///
/// Lazily mounts tabs on first visit, disables tickers on inactive tabs,
/// and surfaces live stress spike alerts globally.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  final Set<int> _visitedTabs = {0};
  bool _updateDialogShown = false;

  static const _screens = <Widget>[
    HomeScreen(),
    VitalsScreen(),
    SleepScreen(),
    ActivityScreen(),
    LeaderboardScreen(),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(Future.microtask(() {
      ref.read(autoScanProvider);
      ref.read(stressAnalyzerProvider);
      ref.read(healthSyncCoordinatorProvider);
    }));
  }

  void _switchTab(int index) {
    if (index < 0 || index >= _screens.length) return;
    if (!_visitedTabs.contains(index)) {
      setState(() => _visitedTabs.add(index));
    }
    ref.read(selectedTabProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(selectedTabProvider);
    if (!_visitedTabs.contains(currentIndex)) {
      _visitedTabs.add(currentIndex);
    }

    // Non-blocking startup check for newer signed APK releases on GitHub
    ref.listen<AsyncValue<UpdateCheckResult?>>(autoUpdateCheckProvider, (
      _,
      next,
    ) {
      next.whenData((result) {
        if (!mounted || _updateDialogShown) return;
        if (result != null && result.hasUpdate) {
          _updateDialogShown = true;
          unawaited(AppUpdateDialog.show(context, result));
        }
      });
    });

    // Listen for real-time detected stress spikes and offer quick tagging
    ref.listen<AsyncValue<StressEvent>>(activeStressEventProvider, (_, next) {
      next.whenData((event) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.surfaceLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            content: Text(
              event.isTagged
                  ? 'Stress spike (${event.peakHr} bpm) auto-tagged to ${event.attendees.join(', ')}'
                  : 'Stress spike detected (${event.peakHr} bpm)',
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            action: event.isTagged
                ? null
                : SnackBarAction(
                    label: 'Tag',
                    textColor: AppColors.pastelCoral,
                    onPressed: () => _switchTab(4),
                  ),
          ),
        );
      });
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: IndexedStack(
        index: currentIndex,
        children: List.generate(_screens.length, (index) {
          if (!_visitedTabs.contains(index)) {
            return const SizedBox.shrink();
          }
          return TickerMode(
            enabled: index == currentIndex,
            child: _screens[index],
          );
        }),
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: currentIndex,
        onTap: _switchTab,
      ),
    );
  }
}
