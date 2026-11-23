import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ring/services/colmi_protocol.dart';

void main() {
  group('ColmiPacket', () {
    test('builds valid 16-byte packets with matching CRC', () {
      final startPacket = ColmiPacket.startRealtimeHeartRate();
      final continuePacket = ColmiPacket.continueRealtimeHeartRate();
      final stopPacket = ColmiPacket.stopRealtimeHeartRate();
      final batteryPacket = ColmiPacket.requestBattery();

      expect(startPacket.length, 16);
      expect(continuePacket.length, 16);
      expect(stopPacket.length, 16);
      expect(batteryPacket.length, 16);

      expect(ColmiParser.isValidCrc(startPacket), isTrue);
      expect(ColmiParser.isValidCrc(continuePacket), isTrue);
      expect(ColmiParser.isValidCrc(stopPacket), isTrue);
      expect(ColmiParser.isValidCrc(batteryPacket), isTrue);

      expect(continuePacket[0], ColmiCommandId.dataRequest);
      expect(continuePacket[1], ColmiDataType.realtimeHeartRate.value);
      expect(continuePacket[2], ColmiDataAction.resume.value);
    });
  });

  group('ColmiParser', () {
    test('parses valid DataRequest heart rate notification', () {
      final packet = ColmiPacket.build(
        ColmiCommandId.dataRequest,
        [ColmiDataType.realtimeHeartRate.value, 0x00, 76],
      );

      final bpm = ColmiParser.parseRealtimeHeartRate(packet);
      expect(bpm, 76);
    });

    test('parses valid legacy realtimeHeartRate notification', () {
      final packet = ColmiPacket.build(
        ColmiCommandId.realtimeHeartRate,
        [84],
      );

      final bpm = ColmiParser.parseRealtimeHeartRate(packet);
      expect(bpm, 84);
    });

    test('returns null on error bit or non-zero error code', () {
      final errPacket = ColmiPacket.build(
        ColmiCommandId.dataRequest,
        [ColmiDataType.realtimeHeartRate.value, 0x01, 76],
      );
      expect(ColmiParser.parseRealtimeHeartRate(errPacket), isNull);

      final errBitPacket = ColmiPacket.build(
        ColmiCommandId.realtimeHeartRate | 0x80,
        [76],
      );
      expect(ColmiParser.parseRealtimeHeartRate(errBitPacket), isNull);
    });

    test('parses valid battery notification', () {
      final packet = ColmiPacket.build(
        ColmiCommandId.battery,
        [84, 1],
      );

      final parsed = ColmiParser.parseBattery(packet);
      expect(parsed, isNotNull);
      expect(parsed!.percent, 84);
      expect(parsed.isCharging, isTrue);
    });

    test('extractValidPackets resynchronizes across stray corrupted bytes', () {
      final validHrPacket = ColmiPacket.build(
        ColmiCommandId.dataRequest,
        [ColmiDataType.realtimeHeartRate.value, 0x00, 82],
      );
      final validBatteryPacket = ColmiPacket.build(
        ColmiCommandId.battery,
        [65, 0],
      );

      // Inject 3 garbage bytes before the first packet and 2 garbage bytes between packets
      final streamBuffer = <int>[
        0xDE,
        0xAD,
        0xBE,
        ...validHrPacket,
        0xFF,
        0x99,
        ...validBatteryPacket,
        0x1E, // trailing incomplete fragment
        0x01,
      ];

      final packets = ColmiParser.extractValidPackets(streamBuffer);
      expect(packets.length, 2);
      expect(ColmiParser.parseRealtimeHeartRate(packets[0]), 82);
      expect(ColmiParser.parseBattery(packets[1])?.percent, 65);

      // Trailing 2 incomplete bytes remain in the buffer for the next notification chunk
      expect(streamBuffer, equals([0x1E, 0x01]));
    });

    test('rejects packet with corrupted CRC', () {
      final packet = Uint8List.fromList(
        ColmiPacket.build(
          ColmiCommandId.dataRequest,
          [ColmiDataType.realtimeHeartRate.value, 0x00, 72],
        ),
      );
      packet[15] = (packet[15] + 1) & 0xFF;

      expect(ColmiParser.isValidCrc(packet), isFalse);
    });
  });
}
