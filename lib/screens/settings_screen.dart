import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../providers/ble_providers.dart';
import '../services/ble_service.dart';

/// Full-screen settings page with BLE device connection management.
///
/// Opened by tapping the ⚙️ icon on the home screen top bar.
/// Displays connection status, scan controls, connected device info,
/// and general app settings.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Bar ──────────────────────────────────────────
            _buildAppBar(context),

            // ── Content ──────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Device connection section
                    _SectionHeader(label: 'DEVICE'),
                    const SizedBox(height: 12),
                    const _ConnectionStatusCard(),
                    const SizedBox(height: 12),
                    const _ConnectedDeviceCard(),
                    const SizedBox(height: 12),
                    const _ScanButton(),
                    const SizedBox(height: 12),
                    const _DiscoveredDevicesList(),

                    const SizedBox(height: 32),

                    // General section
                    _SectionHeader(label: 'GENERAL'),
                    const SizedBox(height: 12),
                    _SettingsTile(
                      icon: Icons.info_outline_rounded,
                      title: 'About Spike',
                      subtitle: 'Version 1.0.0',
                      onTap: () {},
                    ),
                    const SizedBox(height: 8),
                    _SettingsTile(
                      icon: Icons.description_outlined,
                      title: 'Licenses',
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'Spike',
                        applicationVersion: '1.0.0',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.cardBorder,
                  width: 0.5,
                ),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Settings',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 4,
              fontSize: 11,
            ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Connection Status Card
// ─────────────────────────────────────────────────────────────────

class _ConnectionStatusCard extends ConsumerWidget {
  const _ConnectionStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionAsync = ref.watch(bleConnectionStateProvider);

    final state = connectionAsync.valueOrNull ?? BleConnectionState.disconnected;
    final (statusLabel, statusColor, iconData) = _statusInfo(state);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          // Animated Bluetooth icon
          _PulsingBluetoothIcon(
            color: statusColor,
            isAnimating: state == BleConnectionState.connected,
          ),
          const SizedBox(width: 16),
          // Status text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bluetooth',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.4),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(iconData, color: AppColors.textTertiary, size: 20),
        ],
      ),
    );
  }

  (String, Color, IconData) _statusInfo(BleConnectionState state) {
    switch (state) {
      case BleConnectionState.connected:
        return ('Connected', AppColors.pastelTeal, Icons.check_circle_outline_rounded);
      case BleConnectionState.scanning:
        return ('Scanning...', AppColors.pastelAmber, Icons.radar_rounded);
      case BleConnectionState.connecting:
        return ('Connecting...', AppColors.pastelAmber, Icons.sync_rounded);
      case BleConnectionState.error:
        return ('Error', AppColors.pastelCoral, Icons.error_outline_rounded);
      case BleConnectionState.disconnected:
        return ('Disconnected', AppColors.textTertiary, Icons.bluetooth_disabled_rounded);
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Pulsing Bluetooth Icon
// ─────────────────────────────────────────────────────────────────

class _PulsingBluetoothIcon extends StatefulWidget {
  final Color color;
  final bool isAnimating;

  const _PulsingBluetoothIcon({
    required this.color,
    required this.isAnimating,
  });

  @override
  State<_PulsingBluetoothIcon> createState() => _PulsingBluetoothIconState();
}

class _PulsingBluetoothIconState extends State<_PulsingBluetoothIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.3, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.isAnimating) _controller.repeat();
  }

  @override
  void didUpdateWidget(_PulsingBluetoothIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimating && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isAnimating && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulse ring
          if (widget.isAnimating)
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withValues(
                        alpha: _opacityAnimation.value,
                      ),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          // Icon background
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bluetooth_rounded,
              color: widget.color,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Connected Device Card
// ─────────────────────────────────────────────────────────────────

class _ConnectedDeviceCard extends ConsumerWidget {
  const _ConnectedDeviceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionAsync = ref.watch(bleConnectionStateProvider);
    final state = connectionAsync.valueOrNull ?? BleConnectionState.disconnected;

    if (state != BleConnectionState.connected) {
      return const SizedBox.shrink();
    }

    final deviceName = ref.watch(connectedDeviceNameProvider) ?? 'Unknown';
    final batteryAsync = ref.watch(batteryStatusProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              // Ring icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.pastelTeal.withValues(alpha: 0.2),
                      AppColors.pastelBlue.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.watch_rounded,
                  color: AppColors.pastelTeal,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              // Device info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Smart Ring',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
              // Battery indicator
              batteryAsync.when(
                data: (battery) => _BatteryBadge(
                  percent: battery.percent,
                  isCharging: battery.isCharging,
                ),
                loading: () => const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.textTertiary,
                  ),
                ),
                error: (_, __) => const Icon(
                  Icons.battery_unknown_rounded,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Disconnect button
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () async {
                final service = ref.read(bleServiceProvider);
                await service.disconnect();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.pastelCoral.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.pastelCoral.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    'Disconnect',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.pastelCoral,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Battery Badge
// ─────────────────────────────────────────────────────────────────

class _BatteryBadge extends StatelessWidget {
  final int percent;
  final bool isCharging;
  const _BatteryBadge({required this.percent, required this.isCharging});

  @override
  Widget build(BuildContext context) {
    final color = percent > 20 ? AppColors.pastelTeal : AppColors.pastelCoral;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCharging
                ? Icons.battery_charging_full_rounded
                : _batteryIcon(percent),
            color: color,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            '$percent%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
          ),
        ],
      ),
    );
  }

  IconData _batteryIcon(int percent) {
    if (percent >= 90) return Icons.battery_full_rounded;
    if (percent >= 60) return Icons.battery_5_bar_rounded;
    if (percent >= 40) return Icons.battery_3_bar_rounded;
    if (percent >= 20) return Icons.battery_2_bar_rounded;
    return Icons.battery_1_bar_rounded;
  }
}

// ─────────────────────────────────────────────────────────────────
// Scan Button
// ─────────────────────────────────────────────────────────────────

class _ScanButton extends ConsumerWidget {
  const _ScanButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionAsync = ref.watch(bleConnectionStateProvider);
    final state = connectionAsync.valueOrNull ?? BleConnectionState.disconnected;

    final isScanning = state == BleConnectionState.scanning;
    final isConnected = state == BleConnectionState.connected;
    final isDisabled = isConnected;

    return GestureDetector(
      onTap: isDisabled
          ? null
          : () async {
              final service = ref.read(bleServiceProvider);
              if (isScanning) {
                await service.stopScan();
              } else {
                await service.startScan();
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: isDisabled
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isScanning
                      ? [
                          AppColors.pastelAmber.withValues(alpha: 0.15),
                          AppColors.pastelAmber.withValues(alpha: 0.05),
                        ]
                      : [
                          AppColors.pastelTeal.withValues(alpha: 0.15),
                          AppColors.pastelTeal.withValues(alpha: 0.05),
                        ],
                ),
          color: isDisabled ? AppColors.surfaceVariant : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDisabled
                ? AppColors.cardBorder
                : isScanning
                    ? AppColors.pastelAmber.withValues(alpha: 0.3)
                    : AppColors.pastelTeal.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isScanning) ...[
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.pastelAmber,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Stop Scanning',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.pastelAmber,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ] else ...[
              Icon(
                isDisabled
                    ? Icons.bluetooth_connected_rounded
                    : Icons.search_rounded,
                color: isDisabled
                    ? AppColors.textTertiary
                    : AppColors.pastelTeal,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isDisabled ? 'Already Connected' : 'Scan for Ring',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: isDisabled
                          ? AppColors.textTertiary
                          : AppColors.pastelTeal,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Discovered Devices List
// ─────────────────────────────────────────────────────────────────

class _DiscoveredDevicesList extends ConsumerWidget {
  const _DiscoveredDevicesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionAsync = ref.watch(bleConnectionStateProvider);
    final state = connectionAsync.valueOrNull ?? BleConnectionState.disconnected;

    // Only show during scanning
    if (state != BleConnectionState.scanning) return const SizedBox.shrink();

    final resultsAsync = ref.watch(scanResultsProvider);

    return resultsAsync.when(
      data: (results) {
        // Filter to only named devices
        final namedDevices = results
            .where((r) => r.device.platformName.isNotEmpty)
            .toList();

        if (namedDevices.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'Searching for nearby devices…',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
              child: Text(
                'Nearby Devices',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ),
            ...namedDevices.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: _cardDecoration(),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bluetooth_rounded,
                          color: r.device.platformName
                                  .toLowerCase()
                                  .contains('r02')
                              ? AppColors.pastelTeal
                              : AppColors.textTertiary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.device.platformName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                              Text(
                                'RSSI: ${r.rssi} dBm',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.textTertiary,
                                      fontSize: 11,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (r.device.platformName
                            .toLowerCase()
                            .contains('r02'))
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.pastelTeal.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'SPIKE',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: AppColors.pastelTeal,
                                    letterSpacing: 1.5,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                )),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// General Settings Tile
// ─────────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.pastelBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.pastelBlue, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Shared card decoration
// ─────────────────────────────────────────────────────────────────

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color: AppColors.cardBorder,
      width: 0.5,
    ),
  );
}
