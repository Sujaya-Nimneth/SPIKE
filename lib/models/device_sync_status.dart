/// Persisted metadata about the most recent smart ring connection and syncs.
class DeviceSyncStatus {
  final DateTime? lastConnectedAt;
  final String? lastDeviceName;
  final int? lastBatteryPercent;
  final bool? lastBatteryCharging;
  final DateTime? lastActivitySyncAt;
  final DateTime? lastSleepSyncAt;

  const DeviceSyncStatus({
    this.lastConnectedAt,
    this.lastDeviceName,
    this.lastBatteryPercent,
    this.lastBatteryCharging,
    this.lastActivitySyncAt,
    this.lastSleepSyncAt,
  });

  static const empty = DeviceSyncStatus();

  bool get hasConnectedBefore => lastConnectedAt != null;
}
