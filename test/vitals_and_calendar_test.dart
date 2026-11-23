import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ring/providers/ble_providers.dart';
import 'package:smart_ring/providers/stress_providers.dart';
import 'package:smart_ring/providers/vitals_provider.dart';
import 'package:smart_ring/services/ble_service.dart';
import 'package:smart_ring/services/calendar_service.dart';

void main() {
  group('LiveVitalsNotifier', () {
    test('records consecutive identical BPM samples and resets on disconnect', () async {
      final connController = StreamController<BleConnectionState>.broadcast();
      final hrController = StreamController<int>.broadcast();

      final container = ProviderContainer(
        overrides: [
          bleConnectionStateProvider.overrideWith((ref) => connController.stream),
          liveVitalsProvider.overrideWith(
            (ref) => LiveVitalsNotifier(
              ref,
              heartRateStreamOverride: hrController.stream,
              persistToDb: false,
            ),
          ),
        ],
      );

      addTearDown(() async {
        container.dispose();
        await connController.close();
        await hrController.close();
      });

      // Read provider and enter connected state
      expect(container.read(liveVitalsProvider).heartRate, isNull);
      connController.add(BleConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      // Push identical consecutive BPM readings (72, 72, 72, 76)
      hrController.add(72);
      hrController.add(72);
      hrController.add(72);
      hrController.add(76);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(liveVitalsProvider);
      expect(state.heartRate, 76);
      expect(state.heartRateHistory.length, 4);
      expect(state.minHeartRate, 72);
      expect(state.maxHeartRate, 76);
      expect(state.avgHeartRate, 73);

      // Disconnecting resets live session stats to null
      connController.add(BleConnectionState.disconnected);
      await Future<void>.delayed(Duration.zero);

      final resetState = container.read(liveVitalsProvider);
      expect(resetState.heartRate, isNull);
      expect(resetState.heartRateHistory, isEmpty);
    });
  });

  group('CalendarService & ActiveMeetingNotifier', () {
    test('auto-expires meeting session and syncs ActiveMeetingNotifier', () async {
      final service = CalendarService();
      final notifier = ActiveMeetingNotifier(service);
      addTearDown(() {
        notifier.dispose();
        service.dispose();
      });

      notifier.startSession(
        attendees: ['Alice', 'Bob'],
        title: 'Quick Sync',
        maxDuration: const Duration(milliseconds: 60),
      );

      expect(notifier.state, isNotNull);
      expect(notifier.state!.title, 'Quick Sync');
      expect(notifier.state!.attendees, ['Alice', 'Bob']);

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(service.activeMeeting, isNull);
      expect(notifier.state, isNull);
    });
  });
}
