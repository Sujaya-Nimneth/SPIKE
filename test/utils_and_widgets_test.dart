import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_ring/models/leaderboard_entry.dart';
import 'package:smart_ring/models/stress_event.dart';
import 'package:smart_ring/providers/ble_providers.dart';
import 'package:smart_ring/providers/stress_providers.dart';
import 'package:smart_ring/screens/leaderboard_screen.dart';
import 'package:smart_ring/screens/settings_screen.dart';
import 'package:smart_ring/services/ble_service.dart';
import 'package:smart_ring/services/calendar_service.dart';
import 'package:smart_ring/theme/app_theme.dart';
import 'package:smart_ring/utils/date_formatter.dart';
import 'package:smart_ring/widgets/leaderboard/leaderboard_helpers.dart';
import 'package:smart_ring/widgets/readiness_ring.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('DateFormatter & LeaderboardHelpers', () {
    test('formats dates, clock times, relative timestamps, and weekday labels', () {
      final dt = DateTime(2026, 11, 24, 14, 5);
      expect(DateFormatter.formatHeaderDate(dt), 'Tuesday, Nov 24');
      expect(DateFormatter.formatClockTime(dt), '2:05 PM');
      expect(DateFormatter.formatShortDateTime(dt), 'Nov 24 · 2:05 PM');

      expect(
        DateFormatter.formatRelative(
          dt.subtract(const Duration(minutes: 12)),
          now: dt,
        ),
        '12m ago',
      );
      expect(DateFormatter.lastSevenDayLabels(dt).last, 'Tue');
    });

    test('safely extracts initials and masks names', () {
      expect(getInitials('Alice Smith'), 'AS');
      expect(getInitials('alice.smith@company.com'), 'AS');
      expect(getInitials('   '), '?');
      expect(truncateName('Alice Smith'), 'Alice');
      expect(
        formatCoworkerName('Alice Smith', privacyMode: true),
        'Coworker AS',
      );
    });
  });

  group('Widget Regression Tests', () {
    testWidgets('CalmRing handles score 0 and null without SweepGradient error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: Column(
              children: [
                CalmRing(score: 0, label: 'READY', unitSuffix: '%'),
                CalmRing(score: null, label: 'READY'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
      expect(find.text('--'), findsOneWidget);
    });

    testWidgets('LeaderboardScreen masks active meeting attendees in Privacy Mode', (tester) async {
      final calendarService = CalendarService();
      calendarService.startMeetingSession(
        attendees: ['Alice Smith', 'Bob Jones'],
        title: 'Secret Escalation',
      );
      addTearDown(calendarService.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            calendarServiceProvider.overrideWithValue(calendarService),
            leaderboardPrivacyModeProvider.overrideWith((ref) => true),
            leaderboardProvider.overrideWith(
              (ref) async => [
                LeaderboardEntry(
                  name: 'Alice Smith',
                  spikeCount: 3,
                  avgPeakHr: 108,
                  lastSeen: DateTime.now(),
                ),
              ],
            ),
            stressEventCountProvider.overrideWith((ref) async => 3),
            untaggedStressEventsProvider.overrideWith(
              (ref) async => const <StressEvent>[],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(body: LeaderboardScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active Meeting Session'), findsOneWidget);
      expect(find.text('Auto-tagging: AS, BJ'), findsOneWidget);
      expect(find.text('Alice Smith'), findsNothing);
      expect(find.text('Coworker AS'), findsOneWidget);
    });

    testWidgets('SettingsScreen opens Clear All Stress Data confirmation dialog', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bleConnectionStateProvider.overrideWith(
              (ref) => Stream.value(BleConnectionState.disconnected),
            ),
            bleAdapterStateProvider.overrideWith(
              (ref) => const Stream.empty(),
            ),
            scanResultsProvider.overrideWith((ref) => const Stream.empty()),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Clear Stress & Leaderboard Data'),
        200,
      );
      await tester.tap(find.text('Clear Stress & Leaderboard Data'));
      await tester.pumpAndSettle();

      expect(find.text('Clear All Stress Data?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Clear All Stress Data?'), findsNothing);
    });
  });
}
