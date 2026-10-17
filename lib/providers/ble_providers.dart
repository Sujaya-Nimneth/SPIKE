import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';

// ── BLE Service ─────────────────────────────────────────────────

/// Provides the [BleService] instance owned by the current [ProviderScope].
final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

// ── Connection State ────────────────────────────────────────────

/// Streams the current [BleConnectionState], immediately yielding the
/// service's current state so late subscribers never miss prior transitions.
final bleConnectionStateProvider =
    StreamProvider<BleConnectionState>((ref) async* {
  final service = ref.watch(bleServiceProvider);
  yield service.currentState;
  yield* service.connectionStream;
});

// ── Heart Rate Stream ───────────────────────────────────────────

/// Streams real-time heart rate values (BPM) from the connected ring.
final heartRateStreamProvider = StreamProvider<int>((ref) {
  final service = ref.watch(bleServiceProvider);
  return service.heartRateStream;
});

// ── Latest Heart Rate ───────────────────────────────────────────

/// Holds the most recent heart rate value for synchronous widget reads.
///
/// Resets to `null` when the ring disconnects so the UI never displays
/// stale BPM readings as "Live".
final latestHeartRateProvider = StateProvider<int?>((ref) {
  ref.listen<AsyncValue<int>>(heartRateStreamProvider, (_, next) {
    next.whenData((hr) {
      ref.controller.state = hr;
    });
  });

  ref.listen<AsyncValue<BleConnectionState>>(
    bleConnectionStateProvider,
    (_, next) {
      final state = next.valueOrNull;
      if (state != null && state != BleConnectionState.connected) {
        ref.controller.state = null;
      }
    },
  );

  return null;
});

// ── Battery Status ──────────────────────────────────────────────

/// Streams battery status updates from the connected ring, seeding with
/// the latest cached reading if available.
final batteryStatusProvider =
    StreamProvider<({int percent, bool isCharging})>((ref) async* {
  final service = ref.watch(bleServiceProvider);
  final initial = service.latestBattery;
  if (initial != null) {
    yield initial;
  }
  yield* service.batteryStream;
});

// ── Auto-Scan Initializer ───────────────────────────────────────

/// Triggers BLE scanning automatically at app startup.
///
/// Once connected, [BleService] automatically starts all-day HR streaming
/// and queries battery status.
final autoScanProvider = FutureProvider<void>((ref) async {
  final service = ref.read(bleServiceProvider);
  await service.startScan();
});

// ── Scan Results ────────────────────────────────────────────────

/// Streams discovered BLE devices during an active scan.
final scanResultsProvider = StreamProvider<List<ScanResult>>((ref) {
  return FlutterBluePlus.scanResults;
});

// ── Connected Device Name ───────────────────────────────────────

/// Exposes the platform name of the currently connected device.
final connectedDeviceNameProvider = Provider<String?>((ref) {
  final connectionState = ref.watch(bleConnectionStateProvider);
  final service = ref.watch(bleServiceProvider);

  return connectionState.whenOrNull(
    data: (state) => state == BleConnectionState.connected
        ? service.connectedDevice?.platformName
        : null,
  );
});

// ── Bluetooth Adapter State ─────────────────────────────────────

/// Streams the Bluetooth adapter state (on/off/turning on/etc).
final bleAdapterStateProvider = StreamProvider<BluetoothAdapterState>((ref) {
  return FlutterBluePlus.adapterState;
});
