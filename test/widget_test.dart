import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_ring/main.dart';
import 'package:smart_ring/models/daily_activity.dart';
import 'package:smart_ring/models/device_sync_status.dart';
import 'package:smart_ring/models/sleep_session.dart';
import 'package:smart_ring/models/stress_event.dart';
import 'package:smart_ring/providers/ble_providers.dart';
import 'package:smart_ring/providers/health_sync_providers.dart';
import 'package:smart_ring/providers/stress_providers.dart';
import 'package:smart_ring/providers/update_providers.dart';
import 'package:smart_ring/services/ble_service.dart';
import 'package:smart_ring/services/stress/stress_detector.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          autoScanProvider.overrideWith((ref) async {}),
          bleConnectionStateProvider.overrideWith(
            (ref) => Stream.value(BleConnectionState.disconnected),
          ),
          heartRateStreamProvider.overrideWith(
            (ref) => const Stream<int>.empty(),
          ),
          calmScoreProvider.overrideWith((ref) => Stream.value(88)),
          stressPhaseProvider.overrideWith(
            (ref) => Stream.value(StressDetectionPhase.warmingUp),
          ),
          baselineHrProvider.overrideWith((ref) => Stream.value(null)),
          activeStressEventProvider.overrideWith(
            (ref) => const Stream<StressEvent>.empty(),
          ),
          healthSyncCoordinatorProvider.overrideWithValue(null),
          deviceSyncStatusProvider.overrideWith(
            (ref) async => DeviceSyncStatus.empty,
          ),
          latestHrSummaryProvider.overrideWith((ref) async => null),
          recentHrSummariesProvider.overrideWith((ref) async => const []),
          dailyHrAveragesProvider.overrideWith(
            (ref) async => (avgDailyHr: null, avgRestingHr: null, daysCount: 0),
          ),
          latestActivityProvider.overrideWith((ref) async => null),
          activityAveragesProvider.overrideWith(
            (ref) async => ActivityAverages.empty,
          ),
          latestSleepProvider.overrideWith((ref) async => null),
          sleepAveragesProvider.overrideWith(
            (ref) async => SleepAverages.empty,
          ),
          todayStressCountProvider.overrideWith((ref) async => 0),
          autoUpdateCheckProvider.overrideWith((ref) async => null),
        ],
        child: const SmartRingApp(),
      ),
    );
    await tester.pump();

    expect(find.text('SPIKE'), findsOneWidget);
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('Awaiting Ring Sync'), findsOneWidget);
  });
}
