import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ring/models/sleep_session.dart';
import 'package:smart_ring/services/colmi_protocol.dart';

void main() {
  group('ColmiPacket', () {
    test('builds valid 16-byte packets with matching CRC', () {
      final startPacket = ColmiPacket.startRealtimeHeartRate();
      final continuePacket = ColmiPacket.continueRealtimeHeartRate();
      final stopPacket = ColmiPacket.stopRealtimeHeartRate();
      final batteryPacket = ColmiPacket.requestBattery();
      final setTimePacket = ColmiPacket.setTime(DateTime(2026, 11, 24, 9, 5, 30));
      final sportPacket = ColmiPacket.requestSportDetail(dayOffset: 2);
      final sleepPacket = ColmiPacket.requestSleepBigData();

      expect(startPacket.length, 16);
      expect(continuePacket.length, 16);
      expect(stopPacket.length, 16);
      expect(batteryPacket.length, 16);
      expect(setTimePacket.length, 16);
      expect(sportPacket.length, 16);
      expect(sleepPacket.length, 6);

      expect(ColmiParser.isValidCrc(startPacket), isTrue);
      expect(ColmiParser.isValidCrc(continuePacket), isTrue);
      expect(ColmiParser.isValidCrc(stopPacket), isTrue);
      expect(ColmiParser.isValidCrc(batteryPacket), isTrue);
      expect(ColmiParser.isValidCrc(setTimePacket), isTrue);
      expect(ColmiParser.isValidCrc(sportPacket), isTrue);

      expect(continuePacket[0], ColmiCommandId.dataRequest);
      expect(continuePacket[1], ColmiDataType.realtimeHeartRate.value);
      expect(continuePacket[2], ColmiDataAction.resume.value);

      // Stop uses Cmd 106 (0x6A)
      expect(stopPacket[0], ColmiCommandId.stopDataRequest);
      expect(stopPacket[1], ColmiDataType.realtimeHeartRate.value);

      // SetTime uses BCD encoding
      expect(setTimePacket[0], ColmiCommandId.setTime);
      expect(setTimePacket[1], 0x26);
      expect(setTimePacket[2], 0x11);
      expect(setTimePacket[3], 0x24);
      expect(setTimePacket[4], 0x09);
      expect(setTimePacket[5], 0x05);
      expect(setTimePacket[6], 0x30);

      // Sport detail & sleep request headers
      expect(sportPacket[0], ColmiCommandId.sportDetail);
      expect(sportPacket[1], 2);
      expect(sleepPacket[0], ColmiCommandId.bigDataMagic);
      expect(sleepPacket[1], ColmiBigDataId.sleep);
    });
  });

  group('ColmiParser', () {
    test('parses valid DataRequest heart rate notifications (DataType 1 and 6)', () {
      final p6 = ColmiPacket.build(
        ColmiCommandId.dataRequest,
        [ColmiDataType.realtimeHeartRate.value, 0x00, 76],
      );
      final p1 = ColmiPacket.build(
        ColmiCommandId.dataRequest,
        [ColmiDataType.heartRate.value, 0x00, 81],
      );

      expect(ColmiParser.parseRealtimeHeartRate(p6), 76);
      expect(ColmiParser.parseRealtimeHeartRate(p1), 81);
    });

    test('parses valid legacy realtimeHeartRate notification', () {
      final packet = ColmiPacket.build(
        ColmiCommandId.realtimeHeartRate,
        [84],
      );

      expect(ColmiParser.parseRealtimeHeartRate(packet), 84);
    });

    test('rejects invalid CRC inside direct HR and battery parsers', () {
      final badHr = Uint8List.fromList(
        ColmiPacket.build(
          ColmiCommandId.dataRequest,
          [ColmiDataType.realtimeHeartRate.value, 0x00, 76],
        ),
      );
      badHr[15] ^= 0x01;
      expect(ColmiParser.parseRealtimeHeartRate(badHr), isNull);

      final badBattery = Uint8List.fromList(
        ColmiPacket.build(ColmiCommandId.battery, [88, 1]),
      );
      badBattery[15] ^= 0x01;
      expect(ColmiParser.parseBattery(badBattery), isNull);
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

    test('extractValidPackets resynchronizes across stray bytes and rejects all-zero frames', () {
      final validHrPacket = ColmiPacket.build(
        ColmiCommandId.dataRequest,
        [ColmiDataType.realtimeHeartRate.value, 0x00, 82],
      );
      final validBatteryPacket = ColmiPacket.build(
        ColmiCommandId.battery,
        [65, 0],
      );
      final allZeros = List<int>.filled(16, 0);

      final streamBuffer = <int>[
        ...allZeros,
        0xDE,
        0xAD,
        0xBE,
        ...validHrPacket,
        0xFF,
        0x99,
        ...validBatteryPacket,
        0x1E,
        0x01,
      ];

      final packets = ColmiParser.extractValidPackets(streamBuffer);
      expect(packets.length, 2);
      expect(ColmiParser.parseRealtimeHeartRate(packets[0]), 82);
      expect(ColmiParser.parseBattery(packets[1])?.percent, 65);
      expect(streamBuffer, equals([0x1E, 0x01]));
    });

    test('extractFrames decodes interleaved standard 16-byte and 0xBC BigData frames', () {
      final hrPacket = ColmiPacket.build(
        ColmiCommandId.dataRequest,
        [ColmiDataType.realtimeHeartRate.value, 0x00, 74],
      );

      final sleepPayload = <int>[
        1, // 1 day
        0, // daysAgo = 0
        10, // 10 bytes (4 header + 6 stages)
        0x70, 0x05, // 1392 min (23:12)
        0xA4, 0x01, // 420 min (07:00)
        2, 120, // light 120m
        3, 90, // deep 90m
        4, 60, // rem 60m
      ];
      final crc = ColmiParser.crc16Modbus(sleepPayload);
      final bigDataFrame = <int>[
        ColmiCommandId.bigDataMagic,
        ColmiBigDataId.sleep,
        sleepPayload.length & 0xFF,
        (sleepPayload.length >> 8) & 0xFF,
        crc & 0xFF,
        (crc >> 8) & 0xFF,
        ...sleepPayload,
      ];

      final buffer = <int>[
        0xAA, // stray byte
        ...hrPacket,
        ...bigDataFrame.sublist(0, 8), // chunk 1
      ];

      final firstPass = ColmiParser.extractFrames(buffer);
      expect(firstPass.length, 1);
      expect(firstPass.first, isA<ColmiStandardFrame>());

      // Feed remaining chunk
      buffer.addAll(bigDataFrame.sublist(8));
      final secondPass = ColmiParser.extractFrames(buffer);
      expect(secondPass.length, 1);
      expect(secondPass.first, isA<ColmiBigDataFrame>());
      final bigFrame = secondPass.first as ColmiBigDataFrame;
      expect(bigFrame.dataId, ColmiBigDataId.sleep);
      expect(buffer, isEmpty);
    });

    test('parseSleepBigData aggregates stages, efficiency, and SleepScore', () {
      final payload = <int>[
        1, // sleepDays = 1
        0, // daysAgo = 0 (today)
        12, // curDayBytes = 4 + 8
        0x70, 0x05, // sleepStart = 1392 (23:12)
        0xA4, 0x01, // sleepEnd = 420 (07:00)
        SleepStageType.light.code, 180,
        SleepStageType.deep.code, 120,
        SleepStageType.rem.code, 90,
        SleepStageType.awake.code, 30,
      ];

      final now = DateTime(2026, 11, 24, 9, 0);
      final sessions = ColmiParser.parseSleepBigData(payload, now: now);

      expect(sessions.length, 1);
      final s = sessions.first;
      expect(s.date, '2026-11-24');
      expect(s.lightMinutes, 180);
      expect(s.deepMinutes, 120);
      expect(s.remMinutes, 90);
      expect(s.awakeMinutes, 30);
      expect(s.totalSleepMinutes, 390);
      expect(s.timeInBedMinutes, 420);
      expect(s.efficiencyPercent, 93);
      expect(s.sleepScore, inInclusiveRange(70, 95));
    });
  });

  group('ColmiSportDetailAccumulator', () {
    test('aggregates multi-packet 0x43 sport intervals into DailyActivityRecord', () {
      final acc = ColmiSportDetailAccumulator();

      // Header packet 0xF0
      final header = ColmiPacket.build(ColmiCommandId.sportDetail, [
        0xF0,
        2, // expected count
        1, // newCal
      ]);
      expect(acc.feed(header), isEmpty);

      // Interval 1: 2026-11-24, slot 36, index 0 of 2, cal 120, steps 1450, dist 1100m
      final slot1 = ColmiPacket.build(ColmiCommandId.sportDetail, [
        0x26, 0x11, 0x24, // 2026-11-24 BCD
        36, // time index
        0, // packet index
        2, // packet count
        120 & 0xFF, (120 >> 8) & 0xFF, // cal
        1450 & 0xFF, (1450 >> 8) & 0xFF, // steps
        1100 & 0xFF, (1100 >> 8) & 0xFF, // dist
      ]);
      expect(acc.feed(slot1), isEmpty);

      // Interval 2: 2026-11-24, slot 40, index 1 of 2, cal 80, steps 950, dist 720m
      final slot2 = ColmiPacket.build(ColmiCommandId.sportDetail, [
        0x26, 0x11, 0x24,
        40,
        1,
        2,
        80 & 0xFF, (80 >> 8) & 0xFF,
        950 & 0xFF, (950 >> 8) & 0xFF,
        720 & 0xFF, (720 >> 8) & 0xFF,
      ]);
      final records = acc.feed(slot2);

      expect(records.length, 1);
      final rec = records.first;
      expect(rec.date, '2026-11-24');
      expect(rec.steps, 2400);
      expect(rec.calories, 200);
      expect(rec.distanceMeters, 1820);
      expect(rec.activeMinutes, 30); // 2 active 15-min slots
    });
  });
}
