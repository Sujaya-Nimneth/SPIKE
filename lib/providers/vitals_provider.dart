import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ble_service.dart';
import '../services/database_service.dart';
import 'ble_providers.dart';
import 'stress_providers.dart';

/// A single data point representing a vital reading at a specific time.
class VitalSample {
  final DateTime timestamp;
  final double value;

  const VitalSample(this.timestamp, this.value);
}

/// Holds real-time heart rate telemetry and session statistics from the ring.
class LiveVitalsState {
  final int? heartRate;
  final int? minHeartRate;
  final int? maxHeartRate;
  final int? avgHeartRate;
  final List<VitalSample> heartRateHistory;

  const LiveVitalsState({
    this.heartRate,
    this.minHeartRate,
    this.maxHeartRate,
    this.avgHeartRate,
    required this.heartRateHistory,
  });

  factory LiveVitalsState.initial() {
    return const LiveVitalsState(
      heartRate: null,
      heartRateHistory: [],
    );
  }

  LiveVitalsState copyWith({
    int? heartRate,
    bool clearHeartRate = false,
    int? minHeartRate,
    int? maxHeartRate,
    int? avgHeartRate,
    List<VitalSample>? heartRateHistory,
  }) {
    return LiveVitalsState(
      heartRate: clearHeartRate ? null : (heartRate ?? this.heartRate),
      minHeartRate: minHeartRate ?? this.minHeartRate,
      maxHeartRate: maxHeartRate ?? this.maxHeartRate,
      avgHeartRate: avgHeartRate ?? this.avgHeartRate,
      heartRateHistory: heartRateHistory ?? this.heartRateHistory,
    );
  }
}

/// Manages [LiveVitalsState] from real BLE heart rate notifications.
///
/// Subscribes directly to the raw [Stream<int>] so consecutive identical BPM
/// packets are never deduplicated or dropped from the chart or session stats.
class LiveVitalsNotifier extends StateNotifier<LiveVitalsState> {
  static const int _maxHistoryLength = 30;
  static const Duration _dbPersistInterval = Duration(seconds: 5);

  final Ref _ref;
  final DatabaseService? _dbOverride;
  final bool _persistToDb;

  ProviderSubscription<AsyncValue<BleConnectionState>>? _connectionSubscription;
  StreamSubscription<int>? _rawHrSubscription;

  int _sampleCount = 0;
  int _hrSum = 0;
  DateTime? _lastDbPersistAt;

  LiveVitalsNotifier(
    this._ref, {
    Stream<int>? heartRateStreamOverride,
    DatabaseService? databaseServiceOverride,
    bool persistToDb = true,
  })  : _dbOverride = databaseServiceOverride,
        _persistToDb = persistToDb,
        super(LiveVitalsState.initial()) {
    _setupListeners(heartRateStreamOverride);
  }

  void _setupListeners(Stream<int>? streamOverride) {
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

    final stream = streamOverride ?? _ref.watch(bleServiceProvider).heartRateStream;
    _rawHrSubscription = stream.listen(_updateHeartRate);
  }

  void _resetToBaseline() {
    _sampleCount = 0;
    _hrSum = 0;
    _lastDbPersistAt = null;
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

    if (_persistToDb &&
        (_lastDbPersistAt == null ||
            now.difference(_lastDbPersistAt!) >= _dbPersistInterval)) {
      _lastDbPersistAt = now;
      unawaited(_persistSample(hr, now));
    }
  }

  Future<void> _persistSample(int hr, DateTime now) async {
    try {
      final DatabaseService db =
          _dbOverride ?? _ref.read<DatabaseService>(databaseServiceProvider);
      final restingHr = _ref.read(stressAnalyzerProvider).currentBaseline?.round();
      await db.recordHeartRateSample(
        hr,
        timestamp: now,
        restingHr: restingHr,
      );
      await db.updateSyncState(
        'last_connected_at',
        now.toUtc().toIso8601String(),
        notify: false,
      );
    } catch (_) {
      // Ignore DB errors in environments without sqflite plugin
    }
  }

  @override
  void dispose() {
    unawaited(_rawHrSubscription?.cancel());
    _connectionSubscription?.close();
    super.dispose();
  }
}

/// Exposes the live vitals state containing current heart rate and history.
final liveVitalsProvider =
    StateNotifierProvider<LiveVitalsNotifier, LiveVitalsState>((ref) {
  return LiveVitalsNotifier(ref);
});
