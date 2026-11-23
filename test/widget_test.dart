import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_ring/main.dart';
import 'package:smart_ring/models/stress_event.dart';
import 'package:smart_ring/providers/ble_providers.dart';
import 'package:smart_ring/providers/health_sync_providers.dart';
import 'package:smart_ring/providers/stress_providers.dart';
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
          activeStressEventProvider.overrideWith(
            (ref) => const Stream<StressEvent>.empty(),
          ),
          healthSyncCoordinatorProvider.overrideWithValue(null),
        ],
        child: const SmartRingApp(),
      ),
    );
    await tester.pump();

    expect(find.text('SPIKE'), findsOneWidget);
    expect(find.text('88'), findsNWidgets(2));
  });
}
