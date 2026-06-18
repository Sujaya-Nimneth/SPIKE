import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ble_service.dart';

// ── BLE Service (singleton) ─────────────────────────────────────

/// Provides the singleton [BleService] instance.
final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  ref.onDispose(() => service.dispose());
  return service;
});

// ── Connection State ────────────────────────────────────────────

/// Streams the current [BleConnectionState].
///
/// Starts as [BleConnectionState.disconnected] and updates whenever
/// the BLE service reports a state change (scanning, connecting,
/// connected, disconnected, error).
final bleConnectionStateProvider =
    StreamProvider<BleConnectionState>((ref) {
  final service = ref.watch(bleServiceProvider);
  return service.connectionStream;
});

// ── Heart Rate Stream ───────────────────────────────────────────

/// Streams real-time heart rate values (BPM) from the connected ring.
///
/// Only emits values when the ring is connected and HR streaming has
/// been started. Values of 0 (sensor warming up) are filtered out by
/// the protocol parser.
final heartRateStreamProvider = StreamProvider<int>((ref) {
  final service = ref.watch(bleServiceProvider);
  return service.heartRateStream;
});

// ── Latest Heart Rate ───────────────────────────────────────────

/// Holds the most recent heart rate value for synchronous widget reads.
///
/// Returns `null` until the first HR value arrives from the ring.
final latestHeartRateProvider = StateProvider<int?>((ref) {
  ref.listen<AsyncValue<int>>(heartRateStreamProvider, (_, next) {
    next.whenData((hr) {
      ref.controller.state = hr;
    });
  });
  return null;
});

// ── Battery Status ──────────────────────────────────────────────

/// Streams battery status updates from the connected ring.
final batteryStatusProvider =
    StreamProvider<({int percent, bool isCharging})>((ref) {
  final service = ref.watch(bleServiceProvider);
  return service.batteryStream;
});

// ── Auto-Scan Initializer ───────────────────────────────────────

/// A provider that triggers BLE scanning automatically.
///
/// Read this provider once at app startup to begin scanning for the
/// R02 ring. It also starts the heart rate stream once connected.
final autoScanProvider = FutureProvider<void>((ref) async {
  final service = ref.read(bleServiceProvider);

  // Start scanning immediately
  await service.startScan();

  // Listen for connection and auto-start HR streaming
  ref.listen<AsyncValue<BleConnectionState>>(
    bleConnectionStateProvider,
    (_, next) {
      next.whenData((state) async {
        if (state == BleConnectionState.connected) {
          await service.startHeartRateStream();
          await service.requestBattery();
        }
      });
    },
  );
});
