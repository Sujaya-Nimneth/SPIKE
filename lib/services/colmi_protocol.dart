/// Colmi BLE protocol encoder/decoder.
///
/// Implements the proprietary 16-byte packet format and BigData framing used by
/// Colmi R02/R06 smart rings. Based on the reverse-engineered protocol
/// documented at https://colmi.puxtril.com/commands/
library;

import 'dart:math' as math;
import '../models/daily_activity.dart';
import '../models/sleep_session.dart';

// ── Command IDs ────────────────────────────────────────────────

/// Known command identifiers in the Colmi protocol.
class ColmiCommandId {
  ColmiCommandId._();

  static const int setTime = 1;
  static const int battery = 3;
  static const int heartRate = 21;
  static const int realtimeHeartRate = 30;
  static const int sportDetail = 67; // 0x43
  static const int findDevice = 80; // 0x50
  static const int dataRequest = 105; // 0x69
  static const int stopDataRequest = 106; // 0x6A
  static const int deviceNotify = 115; // 0x73
  static const int bigDataMagic = 188; // 0xBC
}

/// BigData sub-type identifiers (`0xBC` header byte 1).
class ColmiBigDataId {
  ColmiBigDataId._();

  static const int sleep = 39; // 0x27
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

// ── Extracted Frame Types ──────────────────────────────────────

/// Base type for decoded frames extracted from the Colmi BLE stream buffer.
sealed class ColmiFrame {
  const ColmiFrame();
}

/// A validated 16-byte standard Colmi command packet.
class ColmiStandardFrame extends ColmiFrame {
  final List<int> packet;
  const ColmiStandardFrame(this.packet);
}

/// A validated variable-length BigData (`0xBC`) response payload.
class ColmiBigDataFrame extends ColmiFrame {
  final int dataId;
  final List<int> payload;
  const ColmiBigDataFrame(this.dataId, this.payload);
}

// ── Packet Builder ─────────────────────────────────────────────

/// Builds Colmi BLE command packets (16-byte standard & 6-byte BigData).
class ColmiPacket {
  ColmiPacket._();

  static int _encodeBcd(int value) {
    final clamped = value.clamp(0, 99);
    return (((clamped ~/ 10) % 10) << 4) | (clamped % 10);
  }

  /// Build a raw 16-byte packet from a command ID and up to 14 data bytes.
  /// Missing data bytes are zero-filled.
  static List<int> build(int commandId, [List<int> data = const []]) {
    final packet = List<int>.filled(16, 0);
    packet[0] = commandId & 0xFF;

    for (int i = 0; i < data.length && i < 14; i++) {
      packet[1 + i] = data[i] & 0xFF;
    }

    int crc = 0;
    for (int i = 0; i < 15; i++) {
      crc += packet[i];
    }
    packet[15] = crc & 0xFF;

    return packet;
  }

  /// Build a SetTime packet (Command ID 1) in BCD format to keep ring clocks
  /// synchronized with the host device.
  static List<int> setTime(DateTime time) {
    final local = time.toLocal();
    return build(ColmiCommandId.setTime, [
      _encodeBcd(local.year % 100),
      _encodeBcd(local.month),
      _encodeBcd(local.day),
      _encodeBcd(local.hour),
      _encodeBcd(local.minute),
      _encodeBcd(local.second),
      1, // 24h / sync flag
    ]);
  }

  /// Build a DataRequest packet (Command ID 105) to start/resume a measurement.
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
    return buildDataRequest(
      ColmiDataType.realtimeHeartRate,
      ColmiDataAction.start,
    );
  }

  /// Build a keep-alive packet to continue real-time heart rate streaming.
  static List<int> continueRealtimeHeartRate() {
    return buildDataRequest(
      ColmiDataType.realtimeHeartRate,
      ColmiDataAction.resume,
    );
  }

  /// Build a packet to stop real-time heart rate streaming (Command ID 106 / `0x6A`).
  static List<int> stopRealtimeHeartRate() {
    return build(
      ColmiCommandId.stopDataRequest,
      [ColmiDataType.realtimeHeartRate.value, 0, 0],
    );
  }

  /// Build a battery status request packet (Command ID 3).
  static List<int> requestBattery() {
    return build(ColmiCommandId.battery);
  }

  /// Build a Sports Detail request packet (Command ID 67 / `0x43`) for [dayOffset]
  /// days ago (`0` = today, `1` = yesterday).
  static List<int> requestSportDetail({int dayOffset = 0}) {
    final offset = dayOffset.clamp(0, 30);
    return build(ColmiCommandId.sportDetail, [offset, 0x0F, 0x00, 0x5F]);
  }

  /// Build a BigData sleep history request packet (`0xBC`, `0x27`).
  static List<int> requestSleepBigData() {
    return const [
      ColmiCommandId.bigDataMagic,
      ColmiBigDataId.sleep,
      0x00,
      0x00,
      0xFF,
      0xFF,
    ];
  }

  /// Build a find-device packet (Command ID 80) — blinks the ring's LED.
  static List<int> findDevice() {
    return build(ColmiCommandId.findDevice, [85, 170]);
  }
}

// ── Packet Parser ──────────────────────────────────────────────

/// Parses incoming 16-byte and BigData (`0xBC`) notification frames from the ring.
class ColmiParser {
  ColmiParser._();

  static const int _maxBigDataLength = 4096;

  /// Extract the command ID from a raw packet (lower 7 bits; bit 7 = error).
  static int commandId(List<int> packet) => packet[0] & 0x7F;

  /// Check if the error bit is set in the command ID byte.
  static bool isError(List<int> packet) => (packet[0] & 0x80) != 0;

  /// Validate the 8-bit sum CRC of a 16-byte Colmi packet.
  static bool isValidCrc(List<int> packet) {
    if (packet.length < 16) return false;
    int sum = 0;
    for (int i = 0; i < 15; i++) {
      sum += packet[i] & 0xFF;
    }
    return (sum & 0xFF) == (packet[15] & 0xFF);
  }

  /// Compute standard CRC-16/MODBUS over [bytes].
  static int crc16Modbus(List<int> bytes) {
    int crc = 0xFFFF;
    for (final b in bytes) {
      crc ^= (b & 0xFF);
      for (int i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc & 0xFFFF;
  }

  /// Decode a single BCD byte into decimal (e.g. `0x26` -> `26`).
  static int decodeBcd(int byte) =>
      (((byte >> 4) & 0x0F) * 10) + (byte & 0x0F);

  /// Extracts all valid 16-byte packets from [buffer], mutating [buffer] in place.
  ///
  /// Uses 1-byte sliding-window resynchronization when a CRC check fails and
  /// rejects all-zero dummy frames.
  static List<List<int>> extractValidPackets(List<int> buffer) {
    final validPackets = <List<int>>[];

    while (buffer.length >= 16) {
      final candidate = buffer.sublist(0, 16);
      final cmd = candidate[0] & 0x7F;
      if (cmd != 0 && isValidCrc(candidate)) {
        buffer.removeRange(0, 16);
        validPackets.add(candidate);
      } else {
        buffer.removeAt(0);
      }
    }

    return validPackets;
  }

  /// Extracts both 16-byte standard frames and variable-length `0xBC` BigData
  /// frames from [buffer], mutating [buffer] in place.
  static List<ColmiFrame> extractFrames(List<int> buffer) {
    final frames = <ColmiFrame>[];

    while (buffer.isNotEmpty) {
      final first = buffer[0] & 0xFF;

      if (first == ColmiCommandId.bigDataMagic) {
        if (buffer.length < 6) break;

        final dataId = buffer[1] & 0xFF;
        final dataLen = (buffer[2] & 0xFF) | ((buffer[3] & 0xFF) << 8);
        final headerCrc = (buffer[4] & 0xFF) | ((buffer[5] & 0xFF) << 8);

        if (dataId == 0 || dataLen > _maxBigDataLength) {
          buffer.removeAt(0);
          continue;
        }

        final totalLength = 6 + dataLen;
        if (buffer.length < totalLength) break;

        final payload = buffer.sublist(6, totalLength);
        final computedCrc = crc16Modbus(payload);
        // Some ring firmware revisions send 0xFFFF when CRC-16 is omitted
        if (headerCrc == computedCrc || headerCrc == 0xFFFF) {
          buffer.removeRange(0, totalLength);
          frames.add(ColmiBigDataFrame(dataId, payload));
        } else {
          buffer.removeAt(0);
        }
        continue;
      }

      if (buffer.length < 16) break;
      final candidate = buffer.sublist(0, 16);
      final cmd = candidate[0] & 0x7F;
      if (cmd != 0 && isValidCrc(candidate)) {
        buffer.removeRange(0, 16);
        frames.add(ColmiStandardFrame(candidate));
      } else {
        buffer.removeAt(0);
      }
    }

    return frames;
  }

  /// Parse a real-time heart rate response (Command ID 30) or DataRequest
  /// HR notification (Command ID 105 with DataType 1 or 6).
  ///
  /// Returns the heart rate in BPM, or `null` if invalid/warming up.
  static int? parseRealtimeHeartRate(List<int> packet) {
    if (packet.length < 16) return null;
    if (!isValidCrc(packet)) return null;
    if (isError(packet)) return null;

    final cmd = commandId(packet);
    int hr = 0;

    if (cmd == ColmiCommandId.realtimeHeartRate) {
      hr = packet[1] & 0xFF;
    } else if (cmd == ColmiCommandId.dataRequest) {
      final dataType = packet[1] & 0xFF;
      if (dataType != ColmiDataType.realtimeHeartRate.value &&
          dataType != ColmiDataType.heartRate.value) {
        return null;
      }
      final errCode = packet[2] & 0xFF;
      if (errCode != 0) return null;
      hr = packet[3] & 0xFF;
    } else {
      return null;
    }

    return (hr > 0 && hr <= 220) ? hr : null;
  }

  /// Parse a battery response (Command ID 3).
  static ({int percent, bool isCharging})? parseBattery(List<int> packet) {
    if (packet.length < 16) return null;
    if (!isValidCrc(packet)) return null;
    if (commandId(packet) != ColmiCommandId.battery) return null;
    if (isError(packet)) return null;

    return (
      percent: (packet[1] & 0xFF).clamp(0, 100),
      isCharging: packet[2] != 0,
    );
  }

  /// Parse a `0xBC` / `0x27` BigData sleep payload into nightly [SleepSessionRecord]s.
  static List<SleepSessionRecord> parseSleepBigData(
    List<int> payload, {
    DateTime? now,
  }) {
    if (payload.isEmpty) return const [];

    final refNow = now ?? DateTime.now();
    final sleepDays = payload[0] & 0xFF;
    final sessions = <SleepSessionRecord>[];
    int offset = 1;

    for (int d = 0; d < sleepDays && offset + 6 <= payload.length; d++) {
      final daysAgo = payload[offset] & 0xFF;
      final curDayBytes = payload[offset + 1] & 0xFF;
      final sleepStartMin = _readInt16LE(payload, offset + 2);
      final sleepEndMin = _readInt16LE(payload, offset + 4);

      // Handle both firmware encodings of `curDayBytes`:
      // (a) total day body size (4 + stageBytes) -> ends at offset + 2 + curDayBytes
      // (b) stage bytes only -> ends at offset + 6 + curDayBytes
      int periodsEnd;
      if (curDayBytes >= 4 &&
          (d == sleepDays - 1
              ? offset + 2 + curDayBytes == payload.length
              : offset + 2 + curDayBytes <= payload.length &&
                  (offset + 6 + curDayBytes > payload.length ||
                      curDayBytes % 2 == 0))) {
        periodsEnd = offset + 2 + curDayBytes;
      } else {
        periodsEnd = offset + 6 + curDayBytes;
      }
      periodsEnd = periodsEnd.clamp(offset + 6, payload.length);

      int light = 0;
      int deep = 0;
      int rem = 0;
      int awake = 0;

      for (int i = offset + 6; i + 1 < periodsEnd; i += 2) {
        final stage = SleepStageType.fromCode(payload[i] & 0xFF);
        final mins = payload[i + 1] & 0xFF;
        switch (stage) {
          case SleepStageType.light:
            light += mins;
          case SleepStageType.deep:
            deep += mins;
          case SleepStageType.rem:
            rem += mins;
          case SleepStageType.awake:
            awake += mins;
          case SleepStageType.noData:
          case SleepStageType.error:
            break;
        }
      }

      final wakeDate = refNow.subtract(Duration(days: daysAgo));
      final midnight = DateTime(wakeDate.year, wakeDate.month, wakeDate.day);
      final wakeTime = midnight.add(Duration(minutes: sleepEndMin));
      final bedtime = sleepStartMin > sleepEndMin
          ? midnight
              .subtract(const Duration(days: 1))
              .add(Duration(minutes: sleepStartMin))
          : midnight.add(Duration(minutes: sleepStartMin));

      final totalSleep = light + deep + rem;
      final fallbackTib =
          wakeTime.difference(bedtime).inMinutes.clamp(0, 1440);
      final timeInBed =
          (totalSleep + awake) > 0 ? (totalSleep + awake) : fallbackTib;
      final efficiency = timeInBed > 0
          ? ((totalSleep / timeInBed) * 100).round().clamp(0, 100)
          : 0;

      if (totalSleep > 0) {
        final score = SleepSessionRecord.computeSleepScore(
          totalSleepMinutes: totalSleep,
          efficiencyPercent: efficiency,
          deepMinutes: deep,
          remMinutes: rem,
        );
        sessions.add(
          SleepSessionRecord(
            date: _formatDateKey(wakeDate),
            bedtime: bedtime.toUtc(),
            wakeTime: wakeTime.toUtc(),
            totalSleepMinutes: totalSleep,
            timeInBedMinutes: timeInBed,
            awakeMinutes: awake,
            lightMinutes: light,
            deepMinutes: deep,
            remMinutes: rem,
            efficiencyPercent: efficiency,
            sleepScore: score,
            syncedAt: refNow.toUtc(),
          ),
        );
      }

      offset = periodsEnd;
    }

    return sessions;
  }

  static int _readInt16LE(List<int> bytes, int index) {
    final unsigned = (bytes[index] & 0xFF) | ((bytes[index + 1] & 0xFF) << 8);
    return (unsigned & 0x8000) != 0 ? unsigned - 0x10000 : unsigned;
  }

  static String _formatDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

// ── Multi-Packet Sport Detail (`0x43`) Accumulator ──────────────

class _DayActivityAccumulator {
  int steps = 0;
  int calories = 0;
  int distanceMeters = 0;
  final Set<int> activeSlots = <int>{};
}

/// Accumulates sequential `0x43` (Sports Detail) 16-byte packets from the ring
/// into daily [DailyActivityRecord] summaries.
class ColmiSportDetailAccumulator {
  bool _hasHeader = false;
  final Map<String, _DayActivityAccumulator> _days = {};

  /// Feed a single 16-byte packet. Returns completed [DailyActivityRecord]s when
  /// the ring sends the end-of-day/no-data marker (`0xFF`) or the final packet
  /// in a multi-packet sequence.
  List<DailyActivityRecord> feed(List<int> packet, {DateTime? now}) {
    if (packet.length < 16) return const [];
    if (!ColmiParser.isValidCrc(packet)) return const [];
    if (ColmiParser.isError(packet)) return const [];
    if (ColmiParser.commandId(packet) != ColmiCommandId.sportDetail) {
      return const [];
    }

    final subByte = packet[1] & 0xFF;

    // 0xFF signals no more data / stream end
    if (subByte == 0xFF) {
      return drainCompleted(now: now);
    }

    // 0xF0 header packet precedes multi-packet sport detail intervals
    if (subByte == 0xF0) {
      _hasHeader = true;
      return const [];
    }

    final year = 2000 + ColmiParser.decodeBcd(packet[1] & 0xFF);
    final month = ColmiParser.decodeBcd(packet[2] & 0xFF);
    final day = ColmiParser.decodeBcd(packet[3] & 0xFF);
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return const [];
    }

    final dateKey =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    final timeIndex = packet[4] & 0xFF;
    final packetIndex = packet[5] & 0xFF;
    final packetCount = packet[6] & 0xFF;

    final int calories;
    final int steps;
    final int distance;

    final hasExtendedCols = packet[11] != 0 || packet[12] != 0;
    final looksIndexed = packetCount > 0 && packetIndex < packetCount;

    if (_hasHeader || hasExtendedCols || looksIndexed) {
      calories = _le16(packet, 7);
      steps = _le16(packet, 9);
      distance = _le16(packet, 11);
    } else {
      calories = _le16(packet, 5);
      steps = _le16(packet, 7);
      distance = _le16(packet, 9);
    }

    final acc = _days.putIfAbsent(dateKey, _DayActivityAccumulator.new);
    acc.steps += steps;
    acc.calories += calories;
    acc.distanceMeters += distance;
    if (steps > 0 || calories > 0) {
      acc.activeSlots.add(timeIndex);
    }

    // If this was the final packet of the day (`packetIndex == packetCount - 1`),
    // flush all accumulated days immediately.
    if (looksIndexed && packetIndex == packetCount - 1) {
      return drainCompleted(now: now);
    }

    return const [];
  }

  /// Flush and return any accumulated [DailyActivityRecord]s.
  List<DailyActivityRecord> drainCompleted({DateTime? now}) {
    if (_days.isEmpty) {
      _hasHeader = false;
      return const [];
    }

    final syncedAt = (now ?? DateTime.now()).toUtc();
    final records = _days.entries.map((entry) {
      final acc = entry.value;
      return DailyActivityRecord(
        date: entry.key,
        steps: acc.steps,
        calories: acc.calories,
        distanceMeters: acc.distanceMeters,
        activeMinutes: math.max(0, acc.activeSlots.length * 15),
        syncedAt: syncedAt,
      );
    }).toList();

    _days.clear();
    _hasHeader = false;
    return records;
  }

  void reset() {
    _days.clear();
    _hasHeader = false;
  }

  static int _le16(List<int> p, int i) =>
      (p[i] & 0xFF) | ((p[i + 1] & 0xFF) << 8);
}
