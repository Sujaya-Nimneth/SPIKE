import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/app_logger.dart';
import 'colmi_protocol.dart';

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
/// streaming with periodic keep-alive packets, and auto-reconnecting with
/// exponential backoff.
class BleService {
  BleService();

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

  // ── Private State ───────────────────────────────────────────
  BluetoothDevice? _connectedDevice;
  BluetoothDevice? _lastKnownDevice;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;

  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  DateTime? _lastHrReceivedAt;
  int _keepAliveTickCount = 0;
  int _reconnectAttempt = 0;

  bool _isConnecting = false;
  bool _isStreamingHr = false;
  bool _userRequestedDisconnect = false;
  bool _sawScanningTrue = false;

  final _heartRateController = StreamController<int>.broadcast();
  final _connectionStateController =
      StreamController<BleConnectionState>.broadcast();
  final _batteryController =
      StreamController<({int percent, bool isCharging})>.broadcast();

  BleConnectionState _currentState = BleConnectionState.disconnected;
  ({int percent, bool isCharging})? _latestBattery;

  /// Buffer for assembling complete 16-byte packets from potentially
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

  /// The current connection state.
  BleConnectionState get currentState => _currentState;

  /// The most recently received battery status, if any.
  ({int percent, bool isCharging})? get latestBattery => _latestBattery;

  /// The currently connected device, if any.
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // ── Scanning ────────────────────────────────────────────────

  /// Start scanning for nearby BLE devices whose name contains 'R02'.
  ///
  /// Once found, automatically connects to the first matching device.
  Future<void> startScan() async {
    if (_disposed) return;
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

  /// Internal scan logic shared by [startScan] and [forceStartScan].
  Future<void> _performScan() async {
    if (_disposed) return;
    AppLogger.info(_tag, '_performScan: checking adapter state...');

    try {
      final adapterState = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 3));
      AppLogger.info(_tag, '_performScan: adapter state = $adapterState');

      if (adapterState != BluetoothAdapterState.on) {
        AppLogger.info(_tag, '_performScan: BT is off, trying to turn on...');
        try {
          await FlutterBluePlus.turnOn();
        } catch (e) {
          AppLogger.warn(_tag, '_performScan: turnOn failed', e);
          _updateState(BleConnectionState.error);
          return;
        }
      }
    } catch (e) {
      AppLogger.warn(_tag, '_performScan: adapter check timed out', e);
    }

    _updateState(BleConnectionState.scanning);

    await _scanSub?.cancel();
    await _isScanningSub?.cancel();
    _sawScanningTrue = false;

    // Listen for scan results
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (_isConnecting ||
          _currentState == BleConnectionState.connecting ||
          _currentState == BleConnectionState.connected) {
        return;
      }

      for (final result in results) {
        final name = result.device.platformName;
        if (name.isNotEmpty) {
          AppLogger.verbose(
            _tag,
            'Discovered ${result.device.platformName} (RSSI: ${result.rssi})',
          );
        }
        if (name.toLowerCase().contains('r02')) {
          AppLogger.info(_tag, 'Found R02 ($name)! Connecting...');
          _isConnecting = true;
          unawaited(FlutterBluePlus.stopScan());
          unawaited(_scanSub?.cancel());
          unawaited(_isScanningSub?.cancel());
          unawaited(_connect(result.device));
          return;
        }
      }
    });

    // Track actual scan lifecycle via FlutterBluePlus.isScanning
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
    _userRequestedDisconnect = false;
    _isConnecting = true;
    await stopScan();
    await _connect(device);
  }

  /// Connect to a specific BLE device, discover the Colmi UART service,
  /// and subscribe to notifications.
  Future<void> _connect(BluetoothDevice device) async {
    _isConnecting = true;
    _reconnectTimer?.cancel();
    AppLogger.info(
      _tag,
      'Connecting to ${device.platformName} (${device.remoteId})...',
    );
    _updateState(BleConnectionState.connecting);

    try {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      AppLogger.info(_tag, 'device.connect() succeeded');

      _connectedDevice = device;
      _lastKnownDevice = device;

      // Discover services and set up characteristics before marking connected
      await _discoverAndSubscribe(device);
      AppLogger.info(_tag, 'Service discovery and subscription succeeded');

      // Listen for unexpected disconnection events
      await _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        AppLogger.info(_tag, 'connectionState event: $state');
        if (state == BluetoothConnectionState.disconnected) {
          unawaited(_onDisconnected());
        }
      });

      _isConnecting = false;
      _reconnectAttempt = 0;
      _updateState(BleConnectionState.connected);

      // Start all-day HR streaming & query initial battery automatically
      await startHeartRateStream();
      await requestBattery();
    } catch (e, stack) {
      AppLogger.error(_tag, 'Error connecting to device', e, stack);
      _isConnecting = false;
      await _cleanup();
      _updateState(BleConnectionState.error);
      if (!_userRequestedDisconnect && !_disposed) {
        _scheduleReconnect();
      }
    }
  }

  /// Discover the Colmi UART service and subscribe to the notify
  /// characteristic.
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

    for (final char in uartService.characteristics) {
      final uuid = char.uuid.toString().toLowerCase();
      if (uuid == ColmiUuids.writeChar.toLowerCase()) {
        _writeChar = char;
      } else if (uuid == ColmiUuids.notifyChar.toLowerCase()) {
        _notifyChar = char;
      }
    }

    if (_writeChar == null || _notifyChar == null) {
      throw Exception('Required Colmi characteristics not found');
    }

    await _notifyChar!.setNotifyValue(true);
    await _notifySub?.cancel();
    _notifySub = _notifyChar!.onValueReceived.listen(_onNotificationReceived);
  }

  /// Disconnect from the currently connected device (user-initiated).
  ///
  /// Sets [_userRequestedDisconnect] so auto-reconnect does not immediately
  /// reconnect behind the user's back.
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
        _currentState != BleConnectionState.connected ||
        _writeChar == null) {
      return;
    }

    _keepAliveTickCount++;
    final now = DateTime.now();

    // If the ring stopped emitting HR packets for >30s, send a fresh Start
    // command to re-engage the optical sensor; otherwise send Continue.
    if (_lastHrReceivedAt != null &&
        now.difference(_lastHrReceivedAt!) > _hrWatchdogTimeout) {
      AppLogger.info(_tag, 'HR watchdog triggered — re-sending start command');
      _lastHrReceivedAt = now;
      await _safeWrite(ColmiPacket.startRealtimeHeartRate());
    } else {
      await _safeWrite(ColmiPacket.continueRealtimeHeartRate());
    }

    // Refresh battery level roughly every 2 minutes (10 * 12s)
    if (_keepAliveTickCount % 10 == 0) {
      await requestBattery();
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

  /// Request battery status from the ring.
  Future<void> requestBattery() async {
    if (_writeChar == null) return;
    await _safeWrite(ColmiPacket.requestBattery());
  }

  Future<void> _safeWrite(List<int> packet) async {
    final characteristic = _writeChar;
    if (characteristic == null) return;
    try {
      await characteristic.write(packet, withoutResponse: true);
    } catch (e) {
      AppLogger.warn(_tag, 'BLE write failed', e);
    }
  }

  // ── Adapter State ───────────────────────────────────────────

  /// Stream of Bluetooth adapter state (on/off/etc).
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  // ── Private Helpers ─────────────────────────────────────────

  /// Handle an incoming notification payload from the ring.
  ///
  /// Uses [ColmiParser.extractValidPackets] for 1-byte sliding-window CRC
  /// resynchronization so partial or corrupted notifications never wedge
  /// the packet stream.
  void _onNotificationReceived(List<int> data) {
    _packetBuffer.addAll(data);

    final packets = ColmiParser.extractValidPackets(_packetBuffer);
    for (final packet in packets) {
      final cmdId = ColmiParser.commandId(packet);

      switch (cmdId) {
        case ColmiCommandId.realtimeHeartRate:
        case ColmiCommandId.dataRequest:
          final hr = ColmiParser.parseRealtimeHeartRate(packet);
          if (hr != null && !_heartRateController.isClosed) {
            _lastHrReceivedAt = DateTime.now();
            _heartRateController.add(hr);
          }
          break;

        case ColmiCommandId.battery:
          final battery = ColmiParser.parseBattery(packet);
          if (battery != null && !_batteryController.isClosed) {
            _latestBattery = battery;
            _batteryController.add(battery);
          }
          break;
      }
    }
  }

  /// Called when the device disconnects unexpectedly.
  Future<void> _onDisconnected() async {
    await _cleanup();
    _updateState(BleConnectionState.disconnected);

    if (!_disposed && !_userRequestedDisconnect) {
      _scheduleReconnect();
    }
  }

  /// Schedules an automatic reconnect with exponential backoff.
  ///
  /// Attempts direct connection to [_lastKnownDevice] first before falling
  /// back to a BLE scan.
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

  /// Update the connection state and broadcast it.
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
    await _notifySub?.cancel();
    _notifySub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    _writeChar = null;
    _notifyChar = null;
    _connectedDevice = null;
    _packetBuffer.clear();
  }

  /// Dispose of all resources.
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _isScanningSub?.cancel();
    await _scanSub?.cancel();
    await disconnect();
    await _heartRateController.close();
    await _connectionStateController.close();
    await _batteryController.close();
  }
}
