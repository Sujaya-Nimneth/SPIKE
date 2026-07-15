import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ble_service.dart';
import 'ble_providers.dart';

/// A single data point representing a vital reading at a specific time.
class VitalSample {
  final DateTime timestamp;
  final double value;

  const VitalSample(this.timestamp, this.value);
}

/// Holds the current values and recent live scrolling history (last 20 samples) for all vitals.
class LiveVitalsState {
  final int heartRate;
  final int hrv;
  final double bodyTempDeviation;
  final double respiratoryRate;
  final int spo2;

  // Recent buffers (max 20 items) for real-time scrolling charts
  final List<VitalSample> heartRateHistory;
  final List<VitalSample> hrvHistory;
  final List<VitalSample> bodyTempHistory;
  final List<VitalSample> respiratoryRateHistory;
  final List<VitalSample> spo2History;

  const LiveVitalsState({
    required this.heartRate,
    required this.hrv,
    required this.bodyTempDeviation,
    required this.respiratoryRate,
    required this.spo2,
    required this.heartRateHistory,
    required this.hrvHistory,
    required this.bodyTempHistory,
    required this.respiratoryRateHistory,
    required this.spo2History,
  });

  factory LiveVitalsState.initial() {
    final now = DateTime.now();
    final random = Random();

    // Helper to pre-populate histories with realistic resting data
    List<VitalSample> generateInitialHistory(double minVal, double maxVal, int count) {
      return List.generate(count, (index) {
        final time = now.subtract(Duration(seconds: (count - index) * 2));
        final val = minVal + random.nextDouble() * (maxVal - minVal);
        return VitalSample(time, double.parse(val.toStringAsFixed(1)));
      });
    }

    return LiveVitalsState(
      heartRate: 72,
      hrv: 45,
      bodyTempDeviation: 0.2,
      respiratoryRate: 15.2,
      spo2: 97,
      heartRateHistory: generateInitialHistory(68, 76, 20),
      hrvHistory: generateInitialHistory(42, 48, 20),
      bodyTempHistory: generateInitialHistory(0.1, 0.3, 20),
      respiratoryRateHistory: generateInitialHistory(14.8, 15.6, 20),
      spo2History: generateInitialHistory(96, 98, 20),
    );
  }

  LiveVitalsState copyWith({
    int? heartRate,
    int? hrv,
    double? bodyTempDeviation,
    double? respiratoryRate,
    int? spo2,
    List<VitalSample>? heartRateHistory,
    List<VitalSample>? hrvHistory,
    List<VitalSample>? bodyTempHistory,
    List<VitalSample>? respiratoryRateHistory,
    List<VitalSample>? spo2History,
  }) {
    return LiveVitalsState(
      heartRate: heartRate ?? this.heartRate,
      hrv: hrv ?? this.hrv,
      bodyTempDeviation: bodyTempDeviation ?? this.bodyTempDeviation,
      respiratoryRate: respiratoryRate ?? this.respiratoryRate,
      spo2: spo2 ?? this.spo2,
      heartRateHistory: heartRateHistory ?? this.heartRateHistory,
      hrvHistory: hrvHistory ?? this.hrvHistory,
      bodyTempHistory: bodyTempHistory ?? this.bodyTempHistory,
      respiratoryRateHistory: respiratoryRateHistory ?? this.respiratoryRateHistory,
      spo2History: spo2History ?? this.spo2History,
    );
  }
}

/// Notifier that manages the LiveVitalsState.
///
/// It listens to the BLE connection status and:
/// - If connected: Starts a timer to fluctuate stats and push new points to history.
/// - Synchronizes Heart Rate with the actual BLE stream.
class LiveVitalsNotifier extends StateNotifier<LiveVitalsState> {
  final Ref _ref;
  Timer? _updateTimer;
  final Random _random = Random();
  StreamSubscription? _hrSubscription;
  ProviderSubscription? _connectionSubscription;

  LiveVitalsNotifier(this._ref) : super(LiveVitalsState.initial()) {
    _setupListeners();
  }

  void _setupListeners() {
    // Listen to BLE connection state transitions
    _connectionSubscription = _ref.listen<AsyncValue<BleConnectionState>>(
      bleConnectionStateProvider,
      (previous, next) {
        final state = next.valueOrNull;
        if (state == BleConnectionState.connected) {
          _startLiveStreaming();
        } else {
          _stopLiveStreaming();
        }
      },
      fireImmediately: true,
    );

    // Listen directly to the latest heart rate provider
    _ref.listen<int?>(latestHeartRateProvider, (previous, next) {
      if (next != null) {
        _updateHeartRate(next);
      }
    });
  }

  void _startLiveStreaming() {
    _updateTimer?.cancel();
    // Update simulated values every 2.5 seconds
    _updateTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      _tickSimulatedVitals();
    });
  }

  void _stopLiveStreaming() {
    _updateTimer?.cancel();
    _updateTimer = null;
    state = LiveVitalsState.initial();
  }

  void _updateHeartRate(int hr) {
    final now = DateTime.now();
    final newHistory = List<VitalSample>.from(state.heartRateHistory)..add(VitalSample(now, hr.toDouble()));
    if (newHistory.length > 20) newHistory.removeAt(0);

    state = state.copyWith(
      heartRate: hr,
      heartRateHistory: newHistory,
    );
  }

  void _tickSimulatedVitals() {
    final now = DateTime.now();

    // 1. HRV: fluctuates slightly around 45ms, between 40 and 52
    final deltaHrv = _random.nextInt(5) - 2; // -2 to +2
    final newHrv = (state.hrv + deltaHrv).clamp(40, 52);
    final hrvHist = List<VitalSample>.from(state.hrvHistory)..add(VitalSample(now, newHrv.toDouble()));
    if (hrvHist.length > 20) hrvHist.removeAt(0);

    // 2. Temp Deviation: fluctuates around +0.2°, between +0.0° and +0.4°
    final tempDelta = (_random.nextDouble() * 0.1) - 0.05; // -0.05 to +0.05
    final newTemp = double.parse((state.bodyTempDeviation + tempDelta).clamp(0.0, 0.4).toStringAsFixed(2));
    final tempHist = List<VitalSample>.from(state.bodyTempHistory)..add(VitalSample(now, newTemp));
    if (tempHist.length > 20) tempHist.removeAt(0);

    // 3. Respiratory Rate: fluctuates around 15.2, between 14.2 and 16.2
    final respDelta = (_random.nextDouble() * 0.4) - 0.2; // -0.2 to +0.2
    final newResp = double.parse((state.respiratoryRate + respDelta).clamp(14.0, 16.5).toStringAsFixed(1));
    final respHist = List<VitalSample>.from(state.respiratoryRateHistory)..add(VitalSample(now, newResp));
    if (respHist.length > 20) respHist.removeAt(0);

    // 4. SpO2: fluctuates around 97%, between 95% and 99%
    final spo2Delta = _random.nextInt(3) - 1; // -1, 0, or +1
    final newSpo2 = (state.spo2 + spo2Delta).clamp(95, 99);
    final spo2Hist = List<VitalSample>.from(state.spo2History)..add(VitalSample(now, newSpo2.toDouble()));
    if (spo2Hist.length > 20) spo2Hist.removeAt(0);

    // 5. Heart Rate: if device is connected but no active BLE HR value arrived yet,
    // we also tick/fluctuate it slightly around its current value
    List<VitalSample> hrHist = state.heartRateHistory;
    int hr = state.heartRate;
    final isBleHrUpdating = _ref.read(latestHeartRateProvider) != null;
    if (!isBleHrUpdating) {
      final hrDelta = _random.nextInt(3) - 1; // -1 to +1
      hr = (state.heartRate + hrDelta).clamp(65, 85);
      hrHist = List<VitalSample>.from(state.heartRateHistory)..add(VitalSample(now, hr.toDouble()));
      if (hrHist.length > 20) hrHist.removeAt(0);
    }

    state = state.copyWith(
      hrv: newHrv,
      hrvHistory: hrvHist,
      bodyTempDeviation: newTemp,
      bodyTempHistory: tempHist,
      respiratoryRate: newResp,
      respiratoryRateHistory: respHist,
      spo2: newSpo2,
      spo2History: spo2Hist,
      heartRate: hr,
      heartRateHistory: hrHist,
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _hrSubscription?.cancel();
    _connectionSubscription?.close();
    super.dispose();
  }
}

/// Exposes the live vitals state containing current values and history.
final liveVitalsProvider = StateNotifierProvider<LiveVitalsNotifier, LiveVitalsState>((ref) {
  return LiveVitalsNotifier(ref);
});
