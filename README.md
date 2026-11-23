<div align="center">

# ⚡ Spike

### A premium Flutter companion app for the Colmi R02 BLE smart ring

**Real-time heart rate · WHOOP-style Ready Score · Sleep & Activity sync · Stress detection v2 · Coworker stress leaderboard**

![Flutter](https://img.shields.io/badge/Flutter-3.7+-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.7+-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![BLE](https://img.shields.io/badge/Bluetooth-Low_Energy-0082FC?style=for-the-badge&logo=bluetooth&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-8FBF9F?style=for-the-badge)

---

*A sleek dark-mode interface that connects to your Colmi R02 smart ring,*
*streams live biometric data, syncs nightly sleep and daily steps, computes your daily Ready Score,*
*detects stress spikes during meetings, and ranks your coworkers by how much they raise your heart rate.* 😅

</div>

---

## ✨ Features

### 🫀 Real-Time Heart Rate & Offline Persistence
- Connects to the Colmi R02 via **Bluetooth Low Energy** using the reverse-engineered Colmi UART protocol
- All-day continuous HR streaming with 12-second keep-alive packets (`Cmd 0x69`, `Action=0x03`) and a 30-second HR watchdog
- Sliding-window CRC-8 and CRC-16 BigData resynchronization with exponential backoff auto-reconnect
- Native Android `connectedDevice` foreground service (`BleForegroundService`) keeps background BLE monitoring alive
- Persists daily HR summaries, sleep, and activity locally in SQLite: displays **live streaming telemetry** when connected, and **last saved reading + last-connected timestamp + 7-day daily averages** when offline

### ⚡ WHOOP-Style Ready Score & Biometrics
- **Ready Score (`ReadinessCalculator`)**: Combines **Sleep Performance (45%)**, **Resting HR vs 7-day average (30%)**, and **Autonomic Calm / daily stress load (25%)** into Green (`Peak Recovery`), Yellow (`Adequate`), and Red (`Rest & Recover`) readiness zones
- **Sleep Sync (`0xBC` / `0x27`)**: Parses Colmi BigData nightly sleep stages (Awake, Light, Deep, REM), efficiency, bedtime, and 7-day sleep averages
- **Activity Sync (`0x43`)**: Aggregates multi-packet 15-minute sport detail intervals into daily steps, calories, distance, active minutes, and 7-day averages

### 🔥 Stress Detection Algorithm v2
- **Signal conditioning (`HrSignalFilter`)**: Rejects physiological outliers (< 35 or > 210 BPM), enforces a 15 BPM/s slew-rate gate, and applies a 5-sample median filter
- **Spike-frozen baseline (`BaselineEstimator`)**: Tracks a 10-minute rolling **Median** and **Median Absolute Deviation (MAD)**, freezes updates while elevated (with a 30-minute prolonged-elevation safety re-anchor), and recovers cleanly across brief drops
- **Z-score & ratio scoring (`StressScorer`)**: Evaluates individualized robust z-score ($z \ge 2.5$) or relative ratio ($\ge 1.25\times$ baseline) with hysteresis exit ($z \ge 1.5$ or $\ge 1.15\times$) into a smoothed 0–100 Calm Score
- **Hysteresis & lifecycle (`StressDetector`)**: Requires $\ge 2$ minutes with an **80% elevated duty cycle**, enforces a 5-minute cooldown, and updates the persisted SQLite episode with finalized peak HR, mean HR, duration, and `dt`-integrated stress load upon recovery

### 🏆 Coworker Stress Leaderboard
- **Live Meeting Session Tracker**: Start an active meeting session (with automatic expiry sync) so detected stress spikes are auto-tagged
- **Manual & Retroactive Spike Tagging**: Review all untagged spikes, dismiss false positives, or log manual coworker spikes
- **Time Window Filters**: Switch between **7 Days**, **30 Days**, and **All Time** rankings
- **Office-Safe Privacy Mode**: Masks coworker names to initials across the podium, list, active meeting banner, and detail sheet
- **Coworker Management**: Rename/merge coworkers, delete individual spikes, and hide/restore coworkers via Settings

---

## 🎨 Design

Spike follows a **dark-mode design language** (`#0A0A0F` background & native dark launch screens) with pastel accents:

| Role | Color | Hex |
|---|---|---|
| 🟦 Background | Deep Black | `#0A0A0F` |
| 🟩 Primary Accent | Pastel Teal | `#5ECFCA` |
| 🟥 Heart Rate | Pastel Coral | `#E8857A` |
| 🟨 Warning / Activity | Pastel Amber | `#F0C75E` |
| 🟪 Sleep / Accents | Pastel Lavender | `#B4A7D6` |
| 🌿 Recovery / Connected | Pastel Sage | `#8FBF9F` |

---

## 📁 Project Structure

```
lib/
├── main.dart                                # App entry, ProviderScope, lazy-mounted MainShell & spike snackbar
├── models/
│   ├── daily_activity.dart                  # Synced daily steps/calories/distance + averages
│   ├── daily_hr_summary.dart                # Persisted daily HR min/max/avg/last + resting HR
│   ├── device_sync_status.dart              # Last connected timestamp, battery & sync metadata
│   ├── leaderboard_entry.dart               # Aggregated coworker ranking entry + period filter
│   ├── readiness_snapshot.dart              # WHOOP-style Ready Score zones & factor breakdown
│   ├── sleep_session.dart                   # Synced sleep stages, efficiency, score & averages
│   └── stress_event.dart                    # StressEvent model + UTC/local SQLite serialization
├── providers/
│   ├── ble_providers.dart                   # BLE connection, HR stream, auto-scan, battery
│   ├── health_sync_providers.dart           # HealthSyncCoordinator, Ready Score & telemetry providers
│   ├── stress_providers.dart                # Stress analyzer, baseline, DB queries, active meeting
│   └── vitals_provider.dart                 # Raw HR stream tracking, live stats & DB sample persistence
├── screens/
│   ├── home_screen.dart                     # WHOOP Ready Score dashboard, factor tiles & metrics row
│   ├── vitals_screen.dart                   # Live/offline HR, stress telemetry & daily averages
│   ├── vital_details_screen.dart            # Real-time HR curve & 7-day daily average bar chart
│   ├── sleep_screen.dart                    # Colmi BigData sleep stages, details & averages
│   ├── activity_screen.dart                 # Colmi 0x43 step goal rings, burn & averages
│   ├── leaderboard_screen.dart              # Coworker stress leaderboard & period filters
│   └── settings_screen.dart                 # BLE device manager, Find My Ring, Hidden Coworkers & reset
├── services/
│   ├── ble_service.dart                     # BLE scan, connect, keep-alive, backoff reconnect & sync
│   ├── calendar_service.dart                # Auto-expiring manual meeting session holder
│   ├── colmi_protocol.dart                  # Colmi 16-byte + 0xBC BigData encoder/decoder & CRC
│   ├── database_service.dart                # SQLite v3 schema, migrations & telemetry persistence
│   ├── foreground_service_bridge.dart       # Android MethodChannel bridge for BleForegroundService
│   ├── stress_analyzer_service.dart         # Coordinates v2 detector, recovery updates & DB
│   ├── readiness/
│   │   └── readiness_calculator.dart        # Pure-Dart WHOOP-style Ready Score engine
│   └── stress/
│       ├── hr_signal_filter.dart            # Range gate, 15 BPM/s slew cap, 5-sample median
│       ├── baseline_estimator.dart          # Rolling 10-min Median + MAD (30m freeze cap)
│       ├── stress_scorer.dart               # Z-score + ratio scoring & EMA Calm Score
│       └── stress_detector.dart             # Hysteresis state machine & recovery lifecycle
├── theme/
│   ├── app_colors.dart
│   └── app_theme.dart
├── utils/
│   ├── app_logger.dart
│   ├── app_routes.dart
│   └── date_formatter.dart
└── widgets/
    ├── bottom_nav_bar.dart
    ├── heart_rate_card.dart
    ├── metric_card.dart
    ├── readiness_ring.dart
    └── leaderboard/                         # Modular podium, cards, banners & tagging sheets
```

---

## 🔌 Colmi R02 BLE Protocol

| Item | Value |
|---|---|
| Service UUID | `6e40fff0-b5a3-f393-e0a9-e50e24dcca9e` |
| Write Characteristic | `6e400002-b5a3-f393-e0a9-e50e24dcca9e` |
| Notify Characteristic | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` |
| Standard Packet Size | Fixed 16 bytes (`CRC = sum(bytes[0..14]) & 0xFF`) |
| BigData Framing | `0xBC` header + `dataId` + `lenLE16` + `crc16Modbus` + payload |

Implemented commands:
- `0x01`: SetTime (BCD clock synchronization on connect)
- `0x03`: Battery level & charging state
- `0x43`: Sports Detail (15-minute step / calorie / distance intervals)
- `0x50`: Find Device (blink ring LED)
- `0x69` / `0x6A`: Real-time HR start (`action=1`), resume keep-alive (`action=3` every 12s), stop (`0x6A`)
- `0xBC` / `0x27`: BigData Sleep history (Awake, Light, Deep, REM)

---

## 🗄️ Database Schema (v3)

SQLite v3 with `PRAGMA foreign_keys = ON` and UTC ISO-8601 timestamps:
- `stress_events`: stress episodes with peak/mean/baseline HR, duration, `stress_load`, and confirmation label
- `coworkers`: case-insensitive (`COLLATE NOCASE`) coworker directory with `hidden` flag
- `event_attendees`: normalized junction table with `ON DELETE CASCADE` / `ON UPDATE CASCADE` foreign keys
- `daily_hr_summaries`: per-day HR last/min/max/sum/count and resting HR
- `daily_activity`: synced daily steps, calories, distance, active minutes, and step goal
- `sleep_sessions`: nightly sleep stages, bedtime/wake time, efficiency, and sleep score
- `device_sync_state`: last connected timestamp, device name, battery, and sync timestamps

---

## 🚀 Getting Started

```bash
git clone https://github.com/Sujaya-Nimneth/SPIKE.git
cd SPIKE
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter run
```

> **Note**: BLE scanning requires a physical iOS or Android device with Bluetooth Low Energy hardware.

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
