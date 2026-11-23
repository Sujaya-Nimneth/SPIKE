import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/daily_activity.dart';
import '../models/sleep_session.dart';
import '../utils/app_logger.dart';
import 'colmi_protocol.dart';
import 'foreground_service_bridge.dart';

/// Connection states for the BLE service.
enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

/// Service class for Bluetooth Low Energy communication with the Colmi R02
/// smart ring.
///
/// Handles scanning for 'R02' devices, connecting, subscribing to the Colmi
/// UART notify characteristic, maintaining all-day real-time heart rate
/// streaming with periodic keep-alive packets, syncing activity (`0x43`) and
/// sleep (`0xBC`/`0x27`) telemetry, managing the Android `connectedDevice`
/// foreground service, and auto-reconnecting with exponential backoff.
class BleService {
  BleService({ForegroundServiceBridge? foregroundServiceBridge})
      : _foregroundService =
            foregroundServiceBridge ?? ForegroundServiceBridge();

  static const _tag = 'BLE';

  /// Interval between keep-alive continue packets during real-time HR streaming.
  static const _keepAliveInterval = Duration(seconds: 12);

  /// If no HR sample arrives within this window while streaming, re-send Start.
  static const _hrWatchdogTimeout = Duration(seconds: 30);

  /// Backoff delays for automatic reconnection attempts.
  static const List<Duration> _reconnectBackoff = [
    Duration(seconds: 3),
    Duration(seconds: 6),
    Duration(seconds: 12),
    Duration(seconds: 25),
    Duration(seconds: 60),
  ];

  final ForegroundServiceBridge _foregroundService;
  final ColmiSportDetailAccumulator _sportDetailAccumulator =
      ColmiSportDetailAccumulator();

  // ── Private State ───────────────────────────────────────────
  BluetoothDevice? _connectedDevice;
  BluetoothDevice? _lastKnownDevice;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  BluetoothAdapterState? _lastAdapterState;

  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  DateTime? _lastHrReceivedAt;
  int _keepAliveTickCount = 0;
  int _reconnectAttempt = 0;

  bool _isConnecting = false;
  bool _isHandlingDisconnect = false;
  bool _isStreamingHr = false;
  bool _keepAliveInFlight = false;
  bool _isSyncingTelemetry = false;
  bool _userRequestedDisconnect = false;
  bool _sawScanningTrue = false;

  final _heartRateController = StreamController<int>.broadcast();
  final _connectionStateController =
      StreamController<BleConnectionState>.broadcast();
  final _batteryController =
      StreamController<({int percent, bool isCharging})>.broadcast();
  final _activitySyncController =
      StreamController<DailyActivityRecord>.broadcast();
  final _sleepSyncController =
      StreamController<SleepSessionRecord>.broadcast();

  BleConnectionState _currentState = BleConnectionState.disconnected;
  ({int percent, bool isCharging})? _latestBattery;

  /// Buffer for assembling complete 16-byte / BigData packets from potentially
  /// chunked MTU payloads.
  final List<int> _packetBuffer = [];

  /// Whether the service has been disposed (prevents post-dispose ops).
  bool _disposed = false;

  // ── Public Streams & Getters ────────────────────────────────

  /// Stream of real-time heart rate values (BPM) from the ring.
  Stream<int> get heartRateStream => _heartRateController.stream;

  /// Stream of BLE connection state changes.
  Stream<BleConnectionState> get connectionStream =>
      _connectionStateController.stream;

  /// Stream of battery status updates.
  Stream<({int percent, bool isCharging})> get batteryStream =>
      _batteryController.stream;

  /// Stream of synced daily activity summaries (`0x43` Sports Detail).
  Stream<DailyActivityRecord> get activitySyncStream =>
      _activitySyncController.stream;

  /// Stream of synced nightly sleep sessions (`0xBC` / `0x27` BigData).
  Stream<SleepSessionRecord> get sleepSyncStream => _sleepSyncController.stream;

  /// The current connection state.
  BleConnectionState get currentState => _currentState;

  /// The most recently received battery status, if any.
  ({int percent, bool isCharging})? get latestBattery => _latestBattery;

  /// The currently connected device, if any.
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // ── Adapter State Watcher ───────────────────────────────────

  void _ensureAdapterStateListener() {
    if (_adapterStateSub != null || _disposed) return;
    try {
      _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
        final previous = _lastAdapterState;
        _lastAdapterState = state;
        if (_disposed) return;

        if (previous != null &&
            previous != BluetoothAdapterState.on &&
            state == BluetoothAdapterState.on &&
            !_userRequestedDisconnect &&
            !_isConnecting &&
            (_currentState == BleConnectionState.disconnected ||
                _currentState == BleConnectionState.error)) {
          AppLogger.info(_tag, 'Bluetooth turned ON — resuming scan/reconnect');
          _reconnectAttempt = 0;
          unawaited(startScan());
        }
      });
    } catch (e) {
      AppLogger.warn(_tag, 'Unable to attach adapterState listener', e);
    }
  }

  // ── Scanning ────────────────────────────────────────────────

  /// Start scanning for nearby BLE devices whose name contains 'R02'.
  Future<void> startScan() async {
    if (_disposed) return;
    _ensureAdapterStateListener();

    if (_isConnecting ||
        _currentState == BleConnectionState.scanning ||
        _currentState == BleConnectionState.connecting ||
        _currentState == BleConnectionState.connected) {
      return;
    }

    _userRequestedDisconnect = false;
    await _performScan();
  }

  /// Force a fresh scan, resetting any existing scan state first.
  Future<void> forceStartScan() async {
    if (_disposed) {
      AppLogger.info(_tag, 'forceStartScan: disposed, returning');
      return;
    }
    _ensureAdapterStateListener();

    if (_currentState == BleConnectionState.connected || _isConnecting) {
      AppLogger.info(_tag, 'forceStartScan: already connected/connecting');
      return;
    }

    _userRequestedDisconnect = false;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    AppLogger.info(_tag, 'forceStartScan: starting fresh scan...');

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    await _isScanningSub?.cancel();

    await _performScan();
  }

  Future<void> _performScan() async {
    if (_disposed) return;
    AppLogger.info(_tag, '_performScan: waiting for known adapter state...');

    try {
      final adapterState = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 4));
      _lastAdapterState = adapterState;
      AppLogger.info(_tag, '_performScan: adapter state = $adapterState');

      if (adapterState != BluetoothAdapterState.on) {
        if (!kIsWeb && Platform.isAndroid) {
          AppLogger.info(_tag, '_performScan: BT is off, trying to turn on...');
          try {
            await FlutterBluePlus.turnOn();
          } catch (e) {
            AppLogger.warn(_tag, '_performScan: turnOn failed', e);
            _updateState(BleConnectionState.error);
            return;
          }
        } else {
          // On iOS/macOS, Bluetooth cannot be toggled programmatically.
          AppLogger.info(
            _tag,
            '_performScan: BT unavailable ($adapterState) on non-Android',
          );
          _updateState(BleConnectionState.disconnected);
          return;
        }
      }
    } catch (e) {
      AppLogger.warn(_tag, '_performScan: adapter check timed out', e);
    }

    if (_disposed) return;
    _updateState(BleConnectionState.scanning);

    await _scanSub?.cancel();
    await _isScanningSub?.cancel();
    _sawScanningTrue = false;

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (_isConnecting ||
          _currentState == BleConnectionState.connecting ||
          _currentState == BleConnectionState.connected) {
        return;
      }

      for (final result in results) {
        final name = _resolveScanName(result);
        if (name.isNotEmpty) {
          AppLogger.verbose(
            _tag,
            'Discovered $name (RSSI: ${result.rssi})',
          );
        }
        if (name.toLowerCase().contains('r02')) {
          AppLogger.info(_tag, 'Found R02 ($name)! Connecting...');
          _isConnecting = true;
          unawaited(FlutterBluePlus.stopScan());
          unawaited(_scanSub?.cancel());
          unawaited(_isScanningSub?.cancel());
          unawaited(_connect(result.device, displayName: name));
          return;
        }
      }
    });

    _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (scanning) {
        _sawScanningTrue = true;
      } else if (_sawScanningTrue &&
          !_isConnecting &&
          _currentState == BleConnectionState.scanning) {
        AppLogger.info(_tag, 'Scan finished without finding R02');
        _updateState(BleConnectionState.disconnected);
        if (!_userRequestedDisconnect && _lastKnownDevice != null) {
          _scheduleReconnect();
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      AppLogger.error(_tag, 'startScan error', e);
      if (!_isConnecting) {
        _updateState(BleConnectionState.error);
      }
    }
  }

  static String _resolveScanName(ScanResult result) {
    if (result.device.platformName.isNotEmpty) {
      return result.device.platformName;
    }
    return result.advertisementData.advName;
  }

  /// Stop an active scan.
  Future<void> stopScan() async {
    await _isScanningSub?.cancel();
    _isScanningSub = null;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    if (_currentState == BleConnectionState.scanning) {
      _updateState(BleConnectionState.disconnected);
    }
  }

  // ── Connection ──────────────────────────────────────────────

  /// Connect to a specific BLE device (e.g. selected from Settings).
  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_disposed || _isConnecting) return;
    _ensureAdapterStateListener();
    _userRequestedDisconnect = false;
    _isConnecting = true;
    await stopScan();
    await _connect(device);
  }

  Future<void> _connect(
    BluetoothDevice device, {
    String? displayName,
  }) async {
    _isConnecting = true;
    _reconnectTimer?.cancel();
    final label = device.platformName.isNotEmpty
        ? device.platformName
        : (displayName ?? device.remoteId.str);
    AppLogger.info(_tag, 'Connecting to $label (${device.remoteId})...');
    _updateState(BleConnectionState.connecting);

    try {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      AppLogger.info(_tag, 'device.connect() succeeded');

      // Discover services and verify Colmi UART characteristics BEFORE
      // saving _connectedDevice / _lastKnownDevice so non-Colmi devices
      // never poison reconnect state.
      await _discoverAndSubscribe(device);
      AppLogger.info(_tag, 'Service discovery and subscription succeeded');

      _connectedDevice = device;
      _lastKnownDevice = device;

      await _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        AppLogger.info(_tag, 'connectionState event: $state');
        if (state == BluetoothConnectionState.disconnected &&
            !_isConnecting &&
            !_isHandlingDisconnect &&
            _connectedDevice == device) {
          unawaited(_onDisconnected());
        }
      });

      _isConnecting = false;
      _reconnectAttempt = 0;
      _updateState(BleConnectionState.connected);

      unawaited(
        _foregroundService.start(
          title: 'Spike · $label',
          text: 'Streaming heart rate & stress telemetry',
        ),
      );

      // Start all-day HR streaming, sync ring clock, and query battery
      await startHeartRateStream();
      await syncDeviceTime();
      await requestBattery();
      unawaited(_syncInitialTelemetry());
    } catch (e, stack) {
      AppLogger.error(_tag, 'Error connecting to device', e, stack);
      _isConnecting = false;
      try {
        await device.disconnect();
      } catch (_) {}
      await _cleanup();
      _updateState(BleConnectionState.error);
      if (!_userRequestedDisconnect &&
          !_disposed &&
          _lastKnownDevice != null) {
        _scheduleReconnect();
      }
    }
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();

    BluetoothService? uartService;
    for (final service in services) {
      if (service.uuid.toString().toLowerCase() ==
          ColmiUuids.service.toLowerCase()) {
        uartService = service;
        break;
      }
    }

    if (uartService == null) {
      throw Exception('Colmi UART service not found on device');
    }

    BluetoothCharacteristic? writeChar;
    BluetoothCharacteristic? notifyChar;
    for (final char in uartService.characteristics) {
      final uuid = char.uuid.toString().toLowerCase();
      if (uuid == ColmiUuids.writeChar.toLowerCase()) {
        writeChar = char;
      } else if (uuid == ColmiUuids.notifyChar.toLowerCase()) {
        notifyChar = char;
      }
    }

    if (writeChar == null || notifyChar == null) {
      throw Exception('Required Colmi characteristics not found');
    }

    _writeChar = writeChar;
    _notifyChar = notifyChar;

    await _notifyChar!.setNotifyValue(true);
    await _notifySub?.cancel();
    _notifySub = _notifyChar!.onValueReceived.listen(_onNotificationReceived);
  }

  /// Disconnect from the currently connected device (user-initiated).
  Future<void> disconnect() async {
    _userRequestedDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _connectionSub?.cancel();
    _connectionSub = null;

    await stopHeartRateStream();
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    await _cleanup();
    await _foregroundService.stop();
    _updateState(BleConnectionState.disconnected);
  }

  // ── Heart Rate Streaming & Keep-Alive ───────────────────────

  /// Start real-time heart rate streaming from the ring and maintain it
  /// all day with a periodic continue/keep-alive timer.
  Future<void> startHeartRateStream() async {
    if (_writeChar == null) return;
    _isStreamingHr = true;
    _lastHrReceivedAt = DateTime.now();
    _keepAliveTickCount = 0;

    await _safeWrite(ColmiPacket.startRealtimeHeartRate());

    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (_) {
      unawaited(_sendKeepAliveTick());
    });
  }

  Future<void> _sendKeepAliveTick() async {
    if (_disposed ||
        !_isStreamingHr ||
        _keepAliveInFlight ||
        _currentState != BleConnectionState.connected ||
        _writeChar == null) {
      return;
    }

    _keepAliveInFlight = true;
    try {
      _keepAliveTickCount++;
      final now = DateTime.now();

      if (_lastHrReceivedAt != null &&
          now.difference(_lastHrReceivedAt!) > _hrWatchdogTimeout) {
        AppLogger.info(_tag, 'HR watchdog triggered — re-sending start command');
        _lastHrReceivedAt = now;
        await _safeWrite(ColmiPacket.startRealtimeHeartRate());
      } else {
        await _safeWrite(ColmiPacket.continueRealtimeHeartRate());
      }

      if (_keepAliveTickCount % 10 == 0) {
        await requestBattery();
      }
    } finally {
      _keepAliveInFlight = false;
    }
  }

  /// Stop real-time heart rate streaming.
  Future<void> stopHeartRateStream() async {
    _isStreamingHr = false;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;

    if (_writeChar == null) return;
    await _safeWrite(ColmiPacket.stopRealtimeHeartRate());
  }

  // ── Ring Commands & Telemetry Sync ──────────────────────────

  /// Request battery status from the ring.
  Future<void> requestBattery() async {
    if (_writeChar == null) return;
    await _safeWrite(ColmiPacket.requestBattery());
  }

  /// Blink the ring LED to help locate it (`Cmd 80`).
  Future<void> findDevice() async {
    if (_writeChar == null) return;
    await _safeWrite(ColmiPacket.findDevice());
  }

  /// Synchronize the ring's internal RTC clock with local system time (`Cmd 1`).
  Future<void> syncDeviceTime() async {
    if (_writeChar == null) return;
    await _safeWrite(ColmiPacket.setTime(DateTime.now()));
  }

  /// Request daily step/calorie/distance history (`0x43`) for [daysBack] days.
  Future<void> syncActivity({int daysBack = 7}) async {
    if (_writeChar == null || _currentState != BleConnectionState.connected) {
      return;
    }
    _sportDetailAccumulator.reset();
    final count = daysBack.clamp(1, 14);
    for (int offset = 0; offset < count; offset++) {
      if (_disposed ||
          _writeChar == null ||
          _currentState != BleConnectionState.connected) {
        break;
      }
      await _safeWrite(ColmiPacket.requestSportDetail(dayOffset: offset));
      await Future<void>.delayed(const Duration(milliseconds: 140));
    }
    // Flush any pending slots if the ring didn't send an explicit 0xFF marker.
    final remaining = _sportDetailAccumulator.drainCompleted();
    for (final record in remaining) {
      if (!_activitySyncController.isClosed) {
        _activitySyncController.add(record);
      }
    }
  }

  /// Request BigData sleep logs (`0xBC` / `0x27`) from the ring.
  Future<void> syncSleep() async {
    if (_writeChar == null || _currentState != BleConnectionState.connected) {
      return;
    }
    await _safeWrite(ColmiPacket.requestSleepBigData());
  }

  /// Run a full clock + battery + activity + sleep synchronization pass.
  Future<void> syncAllTelemetry({int activityDaysBack = 7}) async {
    if (_isSyncingTelemetry ||
        _writeChar == null ||
        _currentState != BleConnectionState.connected) {
      return;
    }
    _isSyncingTelemetry = true;
    try {
      await syncDeviceTime();
      await requestBattery();
      await syncActivity(daysBack: activityDaysBack);
      await syncSleep();
    } finally {
      _isSyncingTelemetry = false;
    }
  }

  Future<void> _syncInitialTelemetry() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_disposed || _currentState != BleConnectionState.connected) return;
    await syncAllTelemetry(activityDaysBack: 3);
  }

  Future<void> _safeWrite(List<int> packet) async {
    final characteristic = _writeChar;
    if (characteristic == null) return;
    try {
      final withoutResponse = characteristic.properties.writeWithoutResponse;
      await characteristic.write(packet, withoutResponse: withoutResponse);
    } catch (e) {
      AppLogger.warn(_tag, 'BLE write failed', e);
    }
  }

  // ── Adapter State ───────────────────────────────────────────

  /// Stream of Bluetooth adapter state (on/off/etc).
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  // ── Private Helpers ─────────────────────────────────────────

  void _onNotificationReceived(List<int> data) {
    _packetBuffer.addAll(data);

    final frames = ColmiParser.extractFrames(_packetBuffer);
    for (final frame in frames) {
      switch (frame) {
        case ColmiStandardFrame(:final packet):
          _handleStandardPacket(packet);
        case ColmiBigDataFrame(:final dataId, :final payload):
          _handleBigDataFrame(dataId, payload);
      }
    }
  }

  void _handleStandardPacket(List<int> packet) {
    final cmdId = ColmiParser.commandId(packet);

    switch (cmdId) {
      case ColmiCommandId.realtimeHeartRate:
      case ColmiCommandId.dataRequest:
        final hr = ColmiParser.parseRealtimeHeartRate(packet);
        if (hr != null && !_heartRateController.isClosed) {
          _lastHrReceivedAt = DateTime.now();
          _heartRateController.add(hr);
        }

      case ColmiCommandId.battery:
        final battery = ColmiParser.parseBattery(packet);
        if (battery != null && !_batteryController.isClosed) {
          _latestBattery = battery;
          _batteryController.add(battery);
        }

      case ColmiCommandId.sportDetail:
        final records = _sportDetailAccumulator.feed(packet);
        for (final record in records) {
          if (!_activitySyncController.isClosed) {
            _activitySyncController.add(record);
          }
        }
    }
  }

  void _handleBigDataFrame(int dataId, List<int> payload) {
    if (dataId == ColmiBigDataId.sleep) {
      final sessions = ColmiParser.parseSleepBigData(payload);
      for (final session in sessions) {
        if (!_sleepSyncController.isClosed) {
          _sleepSyncController.add(session);
        }
      }
    }
  }

  /// Called when the device disconnects unexpectedly.
  Future<void> _onDisconnected() async {
    if (_isHandlingDisconnect) return;
    _isHandlingDisconnect = true;
    try {
      await _cleanup();
      _updateState(BleConnectionState.disconnected);

      if (!_disposed && !_userRequestedDisconnect) {
        unawaited(
          _foregroundService.update(
            title: 'Spike · Reconnecting…',
            text: 'Waiting for Colmi R02 ring',
          ),
        );
        _scheduleReconnect();
      } else {
        await _foregroundService.stop();
      }
    } finally {
      _isHandlingDisconnect = false;
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _userRequestedDisconnect) return;
    _reconnectTimer?.cancel();

    final backoffIndex =
        _reconnectAttempt.clamp(0, _reconnectBackoff.length - 1);
    final delay = _reconnectBackoff[backoffIndex];
    _reconnectAttempt++;

    AppLogger.info(
      _tag,
      'Scheduling auto-reconnect attempt #$_reconnectAttempt in ${delay.inSeconds}s',
    );

    _reconnectTimer = Timer(delay, () async {
      if (_disposed ||
          _userRequestedDisconnect ||
          _isConnecting ||
          _currentState == BleConnectionState.connected ||
          _currentState == BleConnectionState.connecting) {
        return;
      }

      final knownDevice = _lastKnownDevice;
      if (knownDevice != null && _reconnectAttempt % 2 == 1) {
        await _connect(knownDevice);
      } else {
        await startScan();
      }
    });
  }

  void _updateState(BleConnectionState state) {
    _currentState = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  /// Clean up all active connection subscriptions, timers, and buffers.
  Future<void> _cleanup() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _isStreamingHr = false;
    _keepAliveInFlight = false;
    _isSyncingTelemetry = false;
    await _notifySub?.cancel();
    _notifySub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    _writeChar = null;
    _notifyChar = null;
    _connectedDevice = null;
    _latestBattery = null;
    _packetBuffer.clear();
    _sportDetailAccumulator.reset();
  }

  /// Dispose of all resources.
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _adapterStateSub?.cancel();
    _adapterStateSub = null;
    await _isScanningSub?.cancel();
    await _scanSub?.cancel();
    await disconnect();
    await _heartRateController.close();
    await _connectionStateController.close();
    await _batteryController.close();
    await _activitySyncController.close();
    await _sleepSyncController.close();
  }
}
