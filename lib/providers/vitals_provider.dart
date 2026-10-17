import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ble_service.dart';
import 'ble_providers.dart';

/// A single data point representing a vital reading at a specific time.
class VitalSample {
  final DateTime timestamp;
  final double value;

  const VitalSample(this.timestamp, this.value);
}

/// Holds real-time heart rate telemetry and session statistics from the ring.
///
/// Simulated random vitals (HRV, temperature, respiratory rate, SpO2) have been
/// removed so only genuine sensor data is streamed.
class LiveVitalsState {
  final int heartRate;
  final int? minHeartRate;
  final int? maxHeartRate;
  final int? avgHeartRate;
  final List<VitalSample> heartRateHistory;

  // Retained for backward compatibility with detail configs when not connected
  final int hrv;
  final double bodyTempDeviation;
  final double respiratoryRate;
  final int spo2;
  final List<VitalSample> hrvHistory;
  final List<VitalSample> bodyTempHistory;
  final List<VitalSample> respiratoryRateHistory;
  final List<VitalSample> spo2History;

  const LiveVitalsState({
    required this.heartRate,
    this.minHeartRate,
    this.maxHeartRate,
    this.avgHeartRate,
    required this.heartRateHistory,
    this.hrv = 45,
    this.bodyTempDeviation = 0.2,
    this.respiratoryRate = 15.2,
    this.spo2 = 97,
    this.hrvHistory = const [],
    this.bodyTempHistory = const [],
    this.respiratoryRateHistory = const [],
    this.spo2History = const [],
  });

  factory LiveVitalsState.initial() {
    return const LiveVitalsState(
      heartRate: 72,
      heartRateHistory: [],
    );
  }

  LiveVitalsState copyWith({
    int? heartRate,
    int? minHeartRate,
    int? maxHeartRate,
    int? avgHeartRate,
    List<VitalSample>? heartRateHistory,
  }) {
    return LiveVitalsState(
      heartRate: heartRate ?? this.heartRate,
      minHeartRate: minHeartRate ?? this.minHeartRate,
      maxHeartRate: maxHeartRate ?? this.maxHeartRate,
      avgHeartRate: avgHeartRate ?? this.avgHeartRate,
      heartRateHistory: heartRateHistory ?? this.heartRateHistory,
      hrv: hrv,
      bodyTempDeviation: bodyTempDeviation,
      respiratoryRate: respiratoryRate,
      spo2: spo2,
      hrvHistory: hrvHistory,
      bodyTempHistory: bodyTempHistory,
      respiratoryRateHistory: respiratoryRateHistory,
      spo2History: spo2History,
    );
  }
}

/// Manages [LiveVitalsState] from real BLE heart rate notifications.
///
/// Does not run any background random-number timers; updates occur strictly
/// when real heart rate packets arrive from the ring or when connection state
/// resets.
class LiveVitalsNotifier extends StateNotifier<LiveVitalsState> {
  static const int _maxHistoryLength = 30;

  final Ref _ref;
  ProviderSubscription<AsyncValue<BleConnectionState>>? _connectionSubscription;
  ProviderSubscription<int?>? _hrSubscription;

  int _sampleCount = 0;
  int _hrSum = 0;

  LiveVitalsNotifier(this._ref) : super(LiveVitalsState.initial()) {
    _setupListeners();
  }

  void _setupListeners() {
    _connectionSubscription = _ref.listen<AsyncValue<BleConnectionState>>(
      bleConnectionStateProvider,
      (previous, next) {
        final connState = next.valueOrNull;
        if (connState != null && connState != BleConnectionState.connected) {
          _resetToBaseline();
        }
      },
      fireImmediately: true,
    );

    _hrSubscription = _ref.listen<int?>(
      latestHeartRateProvider,
      (previous, next) {
        if (next != null) {
          _updateHeartRate(next);
        }
      },
    );
  }

  void _resetToBaseline() {
    _sampleCount = 0;
    _hrSum = 0;
    state = LiveVitalsState.initial();
  }

  void _updateHeartRate(int hr) {
    final now = DateTime.now();
    final updatedHistory = List<VitalSample>.of(state.heartRateHistory)
      ..add(VitalSample(now, hr.toDouble()));
    if (updatedHistory.length > _maxHistoryLength) {
      updatedHistory.removeRange(0, updatedHistory.length - _maxHistoryLength);
    }

    _sampleCount++;
    _hrSum += hr;

    final currentMin = state.minHeartRate;
    final currentMax = state.maxHeartRate;

    state = state.copyWith(
      heartRate: hr,
      minHeartRate: (currentMin == null || hr < currentMin) ? hr : currentMin,
      maxHeartRate: (currentMax == null || hr > currentMax) ? hr : currentMax,
      avgHeartRate: (_hrSum / _sampleCount).round(),
      heartRateHistory: List<VitalSample>.unmodifiable(updatedHistory),
    );
  }

  @override
  void dispose() {
    _hrSubscription?.close();
    _connectionSubscription?.close();
    super.dispose();
  }
}

/// Exposes the live vitals state containing current heart rate and history.
final liveVitalsProvider =
    StateNotifierProvider<LiveVitalsNotifier, LiveVitalsState>((ref) {
  return LiveVitalsNotifier(ref);
});
