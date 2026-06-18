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
/// Uses [ConsumerStatefulWidget] to initialize the auto-scan provider
/// at startup, which begins searching for the R02 ring immediately.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  final _screens = const <Widget>[
    HomeScreen(),
    VitalsScreen(),
    SleepScreen(),
    ActivityScreen(),
    LeaderboardScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Trigger auto-scan for the R02 ring on app launch
    Future.microtask(() {
      ref.read(autoScanProvider);
      // Initialize the stress analyzer (starts listening to HR stream)
      ref.read(stressAnalyzerProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true, // content flows behind the nav bar
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}

