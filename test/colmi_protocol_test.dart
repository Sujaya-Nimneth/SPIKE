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

      expect(startPacket.length, ColmiConstants.packetLength);
      expect(continuePacket.length, ColmiConstants.packetLength);
      expect(stopPacket.length, ColmiConstants.packetLength);
      expect(batteryPacket.length, ColmiConstants.packetLength);

      expect(ColmiParser.isValidCrc(startPacket), isTrue);
      expect(ColmiParser.isValidCrc(continuePacket), isTrue);
      expect(ColmiParser.isValidCrc(stopPacket), isTrue);
      expect(ColmiParser.isValidCrc(batteryPacket), isTrue);

      expect(continuePacket[0], ColmiConstants.cmdRealtimeHeartRate);
      expect(continuePacket[1], ColmiConstants.hrTypeHeartRate);
      expect(continuePacket[2], ColmiConstants.hrActionContinue);
    });
  });

  group('ColmiParser', () {
    test('parses valid heart rate notification', () {
      final packet = ColmiPacket.build(
        ColmiConstants.cmdRealtimeHeartRate,
        [ColmiConstants.hrTypeHeartRate, 0x00, 76],
      );

      final parsed = ColmiParser.parseHeartRateResponse(packet);
      expect(parsed, isNotNull);
      expect(parsed!.bpm, 76);
      expect(parsed.hasError, isFalse);
      expect(parsed.isValid, isTrue);
    });

    test('parses valid battery notification', () {
      final packet = ColmiPacket.build(
        ColmiConstants.cmdBattery,
        [84, 1],
      );

      final parsed = ColmiParser.parseBatteryResponse(packet);
      expect(parsed, isNotNull);
      expect(parsed!.percent, 84);
      expect(parsed.isCharging, isTrue);
    });

    test('extractValidPackets resynchronizes across stray corrupted bytes', () {
      final validHrPacket = ColmiPacket.build(
        ColmiConstants.cmdRealtimeHeartRate,
        [ColmiConstants.hrTypeHeartRate, 0x00, 82],
      );
      final validBatteryPacket = ColmiPacket.build(
        ColmiConstants.cmdBattery,
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
      expect(ColmiParser.parseHeartRateResponse(packets[0])?.bpm, 82);
      expect(ColmiParser.parseBatteryResponse(packets[1])?.percent, 65);

      // Trailing 2 incomplete bytes remain in the buffer for the next notification chunk
      expect(streamBuffer, equals([0x1E, 0x01]));
    });

    test('rejects packet with corrupted CRC', () {
      final packet = Uint8List.fromList(
        ColmiPacket.build(
          ColmiConstants.cmdRealtimeHeartRate,
          [ColmiConstants.hrTypeHeartRate, 0x00, 72],
        ),
      );
      packet[15] = (packet[15] + 1) & 0xFF;

      expect(ColmiParser.isValidCrc(packet), isFalse);
      expect(ColmiParser.parseHeartRateResponse(packet), isNull);
    });
  });
}
