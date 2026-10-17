import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/ble_providers.dart';
import 'providers/stress_providers.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'screens/home_screen.dart';
import 'screens/sleep_screen.dart';
import 'screens/activity_screen.dart';
import 'screens/vitals_screen.dart';
import 'screens/leaderboard_screen.dart';
import 'widgets/bottom_nav_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Force dark status bar icons on the dark background
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
/// Lazily mounts tabs on first visit and disables tickers on inactive tabs
/// so offscreen screens do not consume CPU/GPU frames.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;
  final Set<int> _visitedTabs = {0};

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
    Future.microtask(() {
      ref.read(autoScanProvider);
      ref.read(stressAnalyzerProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(_screens.length, (index) {
          if (!_visitedTabs.contains(index)) {
            return const SizedBox.shrink();
          }
          return TickerMode(
            enabled: index == _currentIndex,
            child: _screens[index],
          );
        }),
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == _currentIndex) return;
          setState(() {
            _visitedTabs.add(index);
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
