import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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
/// UART notify characteristic, and streaming real-time heart rate data.
class BleService {
  // ── Singleton ───────────────────────────────────────────────
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  // ── Private State ───────────────────────────────────────────
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  final _heartRateController = StreamController<int>.broadcast();
  final _connectionStateController =
      StreamController<BleConnectionState>.broadcast();
  final _batteryController =
      StreamController<({int percent, bool isCharging})>.broadcast();

  BleConnectionState _currentState = BleConnectionState.disconnected;

  /// Buffer for assembling complete 16-byte packets from potentially
  /// chunked MTU payloads. On some Android devices the BLE stack may
  /// deliver partial notifications.
  final List<int> _packetBuffer = [];

  /// Whether the service has been disposed (prevents post-dispose ops).
  bool _disposed = false;

  // ── Public Streams ──────────────────────────────────────────

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

  /// The currently connected device, if any.
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // ── Scanning ────────────────────────────────────────────────

  /// Start scanning for nearby BLE devices whose name contains 'R02'.
  ///
  /// Once found, automatically connects to the first matching device.
  Future<void> startScan() async {
    if (_disposed) return;
    if (_currentState == BleConnectionState.scanning ||
        _currentState == BleConnectionState.connected) {
      return;
    }

    await _performScan();
  }

  /// Force a fresh scan, resetting any existing state first.
  ///
  /// Unlike [startScan], this bypasses the state guard so it can be
  /// triggered from the Settings screen even if a previous scan left
  /// the service in an unexpected state.
  Future<void> forceStartScan() async {
    if (_disposed) {
      debugPrint('[BLE] forceStartScan: disposed, returning');
      return;
    }

    // If already connected, don't scan
    if (_currentState == BleConnectionState.connected) {
      debugPrint('[BLE] forceStartScan: already connected, returning');
      return;
    }

    debugPrint('[BLE] forceStartScan: starting fresh scan...');

    // Stop any existing scan first
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();

    await _performScan();
  }

  /// Internal scan logic shared by [startScan] and [forceStartScan].
  Future<void> _performScan() async {
    debugPrint('[BLE] _performScan: checking adapter state...');

    // Check adapter state with a timeout to prevent hanging
    try {
      final adapterState = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 3));
      debugPrint('[BLE] _performScan: adapter state = $adapterState');

      if (adapterState != BluetoothAdapterState.on) {
        debugPrint('[BLE] _performScan: BT is off, trying to turn on...');
        try {
          await FlutterBluePlus.turnOn();
          debugPrint('[BLE] _performScan: turnOn succeeded');
        } catch (e) {
          debugPrint('[BLE] _performScan: turnOn failed: $e');
          _updateState(BleConnectionState.error);
          return;
        }
      }
    } catch (e) {
      // Timeout or error checking adapter — proceed anyway
      debugPrint('[BLE] _performScan: adapter check timed out/failed: $e, proceeding...');
    }

    debugPrint('[BLE] _performScan: setting state to scanning');
    _updateState(BleConnectionState.scanning);

    // Cancel any prior scan subscription
    await _scanSub?.cancel();

    // Listen for scan results
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      debugPrint('[BLE] scanResults: ${results.length} device(s) found');
      for (final result in results) {
        final name = result.device.platformName;
        if (name.isNotEmpty) {
          debugPrint('[BLE]   → ${result.device.platformName} (RSSI: ${result.rssi})');
        }
        if (name.toLowerCase().contains('r02')) {
          // Found our ring — stop scanning and connect
          debugPrint('[BLE] Found R02! Connecting...');
          FlutterBluePlus.stopScan();
          _scanSub?.cancel();
          _connect(result.device);
          return;
        }
      }
    });

    // Start the scan (timeout after 15 seconds)
    try {
      debugPrint('[BLE] _performScan: calling FlutterBluePlus.startScan()...');
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );
      debugPrint('[BLE] _performScan: scan completed (timed out)');

      // If scan completes without finding a device
      if (_currentState == BleConnectionState.scanning) {
        _updateState(BleConnectionState.disconnected);
      }
    } catch (e) {
      debugPrint('[BLE] _performScan: startScan error: $e');
      _updateState(BleConnectionState.error);
    }
  }

  /// Stop an active scan.
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    if (_currentState == BleConnectionState.scanning) {
      _updateState(BleConnectionState.disconnected);
    }
  }

  // ── Connection ──────────────────────────────────────────────

  /// Connect to a specific BLE device, discover the Colmi UART service,
  /// and subscribe to notifications.
  Future<void> _connect(BluetoothDevice device) async {
    debugPrint('[BLE] _connect: Starting connection to ${device.platformName} (${device.remoteId})...');
    _updateState(BleConnectionState.connecting);

    try {
      // Connect directly without autoConnect queue (faster on Android)
      debugPrint('[BLE] _connect: Calling device.connect(autoConnect: false)...');
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      debugPrint('[BLE] _connect: device.connect() succeeded!');

      _connectedDevice = device;

      // Listen for disconnection events
      _connectionSub = device.connectionState.listen((state) {
        debugPrint('[BLE] connectionState event: $state');
        if (state == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      // Discover services and set up characteristics
      debugPrint('[BLE] _connect: Discovering services...');
      await _discoverAndSubscribe(device);
      debugPrint('[BLE] _connect: Service discovery and subscription succeeded!');

      _updateState(BleConnectionState.connected);
    } catch (e, stack) {
      debugPrint('[BLE] _connect: Error connecting to device: $e');
      debugPrint('[BLE] Stacktrace: $stack');
      _updateState(BleConnectionState.error);
      await _cleanup();
    }
  }

  /// Discover the Colmi UART service and subscribe to the notify
  /// characteristic.
  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();

    // Find the Colmi UART service
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

    // Locate write and notify characteristics
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

    // Enable notifications
    await _notifyChar!.setNotifyValue(true);

    // Listen for incoming data packets
    _notifySub = _notifyChar!.onValueReceived.listen(_onNotificationReceived);
  }

  /// Disconnect from the currently connected device.
  Future<void> disconnect() async {
    await stopHeartRateStream();
    await _connectedDevice?.disconnect();
    await _cleanup();
    _updateState(BleConnectionState.disconnected);
  }

  // ── Heart Rate Streaming ────────────────────────────────────

  /// Start real-time heart rate streaming from the ring.
  ///
  /// Sends the DataRequest command to begin HR measurement. Heart rate
  /// values will appear on [heartRateStream].
  Future<void> startHeartRateStream() async {
    if (_writeChar == null) return;

    final packet = ColmiPacket.startRealtimeHeartRate();
    await _writeChar!.write(packet, withoutResponse: true);
  }

  /// Stop real-time heart rate streaming.
  Future<void> stopHeartRateStream() async {
    if (_writeChar == null) return;

    final packet = ColmiPacket.stopRealtimeHeartRate();
    try {
      await _writeChar!.write(packet, withoutResponse: true);
    } catch (_) {
      // Device may already be disconnected
    }
  }

  /// Request battery status from the ring.
  Future<void> requestBattery() async {
    if (_writeChar == null) return;

    final packet = ColmiPacket.requestBattery();
    await _writeChar!.write(packet, withoutResponse: true);
  }

  // ── Adapter State ───────────────────────────────────────────

  /// Stream of Bluetooth adapter state (on/off/etc).
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  // ── Private Helpers ─────────────────────────────────────────

  /// Handle an incoming notification payload from the ring.
  ///
  /// Buffers incoming bytes and processes complete 16-byte packets.
  /// This handles MTU fragmentation where the BLE stack may deliver
  /// partial payloads across multiple notifications.
  /// Validates CRC before parsing to reject corrupted data.
  void _onNotificationReceived(List<int> data) {
    _packetBuffer.addAll(data);

    // Process all complete 16-byte packets in the buffer
    while (_packetBuffer.length >= 16) {
      final packet = _packetBuffer.sublist(0, 16);
      _packetBuffer.removeRange(0, 16);

      // Validate CRC before processing — reject corrupted packets
      if (!ColmiParser.isValidCrc(packet)) continue;

      final cmdId = ColmiParser.commandId(packet);

      switch (cmdId) {
        case ColmiCommandId.realtimeHeartRate:
          final hr = ColmiParser.parseRealtimeHeartRate(packet);
          if (hr != null && !_heartRateController.isClosed) {
            _heartRateController.add(hr);
          }
          break;

        case ColmiCommandId.battery:
          final battery = ColmiParser.parseBattery(packet);
          if (battery != null && !_batteryController.isClosed) {
            _batteryController.add(battery);
          }
          break;

        // Future: handle other command responses here
      }
    }
  }

  /// Called when the device disconnects unexpectedly.
  ///
  /// Cleans up state and automatically attempts to reconnect after
  /// a short delay. This prevents the HR stream from dying permanently
  /// when the ring goes out of range or the battery drops briefly.
  void _onDisconnected() async {
    await _cleanup();
    _updateState(BleConnectionState.disconnected);

    // Auto-reconnect after a short delay (unless disposed)
    if (!_disposed) {
      await Future.delayed(const Duration(seconds: 3));
      if (_currentState == BleConnectionState.disconnected && !_disposed) {
        startScan();
      }
    }
  }

  /// Update the connection state and broadcast it.
  void _updateState(BleConnectionState state) {
    _currentState = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  /// Clean up all subscriptions, references, and the packet buffer.
  Future<void> _cleanup() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    _writeChar = null;
    _notifyChar = null;
    _connectedDevice = null;
    _packetBuffer.clear();
  }

  /// Dispose of all resources. Call when the app is shutting down.
  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _heartRateController.close();
    await _connectionStateController.close();
    await _batteryController.close();
    await _scanSub?.cancel();
  }
}
