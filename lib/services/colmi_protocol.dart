/// Colmi BLE protocol encoder/decoder.
///
/// Implements the proprietary 16-byte packet format used by Colmi R02/R06
/// smart rings. Based on the reverse-engineered protocol documented at
/// https://colmi.puxtril.com/commands/
library;

// ── Command IDs ────────────────────────────────────────────────

/// Known command identifiers in the Colmi protocol.
class ColmiCommandId {
  ColmiCommandId._();

  static const int setTime = 1;
  static const int battery = 3;
  static const int heartRate = 21;
  static const int realtimeHeartRate = 30;
  static const int findDevice = 80;
  static const int dataRequest = 105;
  static const int stopDataRequest = 106;
  static const int deviceNotify = 115;
}

// ── Data Type enum for Command 105 ────────────────────────────

/// Data types used in the DataRequest command (ID 105).
enum ColmiDataType {
  heartRate(1),
  bloodPressure(2),
  bloodOxygen(3),
  fatigue(4),
  healthCheck(5),
  realtimeHeartRate(6),
  ecg(7),
  pressure(8),
  bloodSugar(9),
  hrv(10);

  final int value;
  const ColmiDataType(this.value);
}

/// Data actions used in the DataRequest command (ID 105).
enum ColmiDataAction {
  start(1),
  pause(2),
  resume(3),
  stop(4);

  final int value;
  const ColmiDataAction(this.value);
}

// ── GATT UUIDs ─────────────────────────────────────────────────

/// The Colmi UART-over-BLE service and characteristic UUIDs.
class ColmiUuids {
  ColmiUuids._();

  /// Primary GATT service UUID.
  static const String service = '6e40fff0-b5a3-f393-e0a9-e50e24dcca9e';

  /// Write characteristic (phone → ring).
  static const String writeChar = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

  /// Notify characteristic (ring → phone).
  static const String notifyChar = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
}

// ── Packet Builder ─────────────────────────────────────────────

/// Builds a 16-byte Colmi command packet.
///
/// Packet structure:
/// ```
/// [commandId, data[0], data[1], ..., data[13], crc]
/// ```
/// CRC = (sum of bytes 0–14) & 0xFF.
class ColmiPacket {
  ColmiPacket._();

  /// Build a raw 16-byte packet from a command ID and up to 14 data bytes.
  /// Missing data bytes are zero-filled.
  static List<int> build(int commandId, [List<int> data = const []]) {
    final packet = List<int>.filled(16, 0);
    packet[0] = commandId & 0xFF;

    // Fill data bytes (indices 1–14)
    for (int i = 0; i < data.length && i < 14; i++) {
      packet[1 + i] = data[i] & 0xFF;
    }

    // CRC: sum of bytes 0–14, masked to 8 bits
    int crc = 0;
    for (int i = 0; i < 15; i++) {
      crc += packet[i];
    }
    packet[15] = crc & 0xFF;

    return packet;
  }

  /// Build a DataRequest packet (Command ID 105) to start/stop a measurement.
  ///
  /// Used to trigger real-time heart rate, blood pressure, HRV, etc.
  static List<int> buildDataRequest(
    ColmiDataType dataType,
    ColmiDataAction action,
  ) {
    return build(
      ColmiCommandId.dataRequest,
      [dataType.value, action.value],
    );
  }

  /// Build a packet to start real-time heart rate streaming.
  static List<int> startRealtimeHeartRate() {
    return buildDataRequest(ColmiDataType.realtimeHeartRate, ColmiDataAction.start);
  }

  /// Build a packet to stop real-time heart rate streaming.
  static List<int> stopRealtimeHeartRate() {
    return buildDataRequest(ColmiDataType.realtimeHeartRate, ColmiDataAction.stop);
  }

  /// Build a battery status request packet (Command ID 3).
  static List<int> requestBattery() {
    return build(ColmiCommandId.battery);
  }

  /// Build a find-device packet (Command ID 80) — blinks the ring's LED.
  static List<int> findDevice() {
    return build(ColmiCommandId.findDevice, [85, 170]);
  }
}

// ── Packet Parser ──────────────────────────────────────────────

/// Parses incoming 16-byte notification packets from the ring.
class ColmiParser {
  ColmiParser._();

  /// Extract the command ID from a raw packet (lower 7 bits; bit 7 = error).
  static int commandId(List<int> packet) => packet[0] & 0x7F;

  /// Check if the error bit is set in the command ID byte.
  static bool isError(List<int> packet) => (packet[0] & 0x80) != 0;

  /// Validate the CRC of a packet.
  static bool isValidCrc(List<int> packet) {
    if (packet.length < 16) return false;
    int sum = 0;
    for (int i = 0; i < 15; i++) {
      sum += packet[i];
    }
    return (sum & 0xFF) == packet[15];
  }

  /// Parse a real-time heart rate response (Command ID 30).
  ///
  /// Returns the heart rate in BPM, or `null` if the packet is not
  /// a valid real-time HR response or the HR value is 0 (sensor warming up).
  static int? parseRealtimeHeartRate(List<int> packet) {
    if (packet.length < 16) return null;
    if (commandId(packet) != ColmiCommandId.realtimeHeartRate) return null;
    if (isError(packet)) return null;

    final hr = packet[1];
    // HR of 0 means the sensor is still warming up
    return hr > 0 ? hr : null;
  }

  /// Parse a battery response (Command ID 3).
  ///
  /// Returns a record of (chargePercent, isCharging).
  static ({int percent, bool isCharging})? parseBattery(List<int> packet) {
    if (packet.length < 16) return null;
    if (commandId(packet) != ColmiCommandId.battery) return null;
    if (isError(packet)) return null;

    return (
      percent: packet[1],
      isCharging: packet[2] != 0,
    );
  }
}
