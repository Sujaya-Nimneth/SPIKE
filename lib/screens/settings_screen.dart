import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_release_info.dart';
import '../providers/ble_providers.dart';
import '../providers/stress_providers.dart';
import '../providers/update_providers.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../utils/app_logger.dart';
import '../widgets/update_dialog.dart';

const String kAppVersion = '1.0.0';

/// Full-screen settings page with BLE device connection management,
/// ring utilities, privacy controls, and app metadata.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmClearData(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
        title: Text(
          'Clear All Stress Data?',
          style: Theme.of(ctx).textTheme.headlineSmall,
        ),
        content: Text(
          'This will permanently delete all recorded stress spikes, coworker leaderboard entries, and active meeting sessions.',
          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Clear Data',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: AppColors.pastelCoral,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(activeMeetingProvider.notifier).endSession();
      await ref.read(databaseServiceProvider).clearAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Stress events and leaderboard data cleared.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.surfaceLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  void _showHiddenCoworkersSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _HiddenCoworkersSheet(),
    );
  }

  void _showAboutDialog(BuildContext context, String version) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
        title: Text(
          'Spike · v$version',
          style: Theme.of(ctx).textTheme.headlineSmall,
        ),
        content: Text(
          'Smart ring companion app for the Colmi R02 over BLE UART. '
          'Features real-time PPG heart rate streaming, WHOOP-style readiness scoring, '
          'sleep & activity sync, spike-frozen baseline stress detection, and a coworker stress leaderboard.',
          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Close',
              style: TextStyle(
                color: AppColors.pastelTeal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appVersion =
        ref.watch(installedAppVersionProvider).valueOrNull ?? kAppVersion;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader(label: 'DEVICE'),
                    const SizedBox(height: 12),
                    const _BluetoothOffBanner(),
                    const _ConnectionStatusCard(),
                    const SizedBox(height: 12),
                    const _ConnectedDeviceCard(),
                    const SizedBox(height: 12),
                    const _ScanButton(),
                    const SizedBox(height: 12),
                    const _DiscoveredDevicesList(),

                    const SizedBox(height: 32),

                    const _SectionHeader(label: 'DATA & PRIVACY'),
                    const SizedBox(height: 12),
                    _SettingsTile(
                      icon: Icons.visibility_outlined,
                      title: 'Hidden Coworkers',
                      subtitle: 'Restore coworkers hidden from the leaderboard',
                      accentColor: AppColors.pastelLavender,
                      onTap: () => _showHiddenCoworkersSheet(context),
                    ),
                    const SizedBox(height: 8),
                    _SettingsTile(
                      icon: Icons.restart_alt_rounded,
                      title: 'Reset Stress Baseline',
                      subtitle: 'Recalibrate 10-minute rolling HR baseline',
                      accentColor: AppColors.pastelAmber,
                      onTap: () {
                        ref.read(stressAnalyzerProvider).resetDetector();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'Stress baseline reset — recalibrating from incoming HR.',
                            ),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: AppColors.surfaceLight,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _SettingsTile(
                      icon: Icons.delete_outline_rounded,
                      title: 'Clear Stress & Leaderboard Data',
                      subtitle: 'Reset all recorded spikes and coworker rankings',
                      accentColor: AppColors.pastelCoral,
                      onTap: () => _confirmClearData(context, ref),
                    ),

                    const SizedBox(height: 32),

                    const _SectionHeader(label: 'GENERAL'),
                    const SizedBox(height: 12),
                    _CheckForUpdatesTile(currentVersion: appVersion),
                    const SizedBox(height: 8),
                    _SettingsTile(
                      icon: Icons.info_outline_rounded,
                      title: 'About Spike',
                      subtitle: 'Version $appVersion',
                      onTap: () => _showAboutDialog(context, appVersion),
                    ),
                    const SizedBox(height: 8),
                    _SettingsTile(
                      icon: Icons.description_outlined,
                      title: 'Licenses',
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'Spike',
                        applicationVersion: appVersion,
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
          Semantics(
            button: true,
            label: 'Back',
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(12),
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

class _HiddenCoworkersSheet extends ConsumerWidget {
  const _HiddenCoworkersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hiddenAsync = ref.watch(hiddenCoworkersProvider);
    final hidden = hiddenAsync.valueOrNull ?? const <String>[];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hidden Coworkers',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Restore any coworker to show them on the leaderboard again.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            if (hidden.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'No hidden coworkers.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: hidden.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final name = hidden[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(color: AppColors.textPrimary),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await ref
                                  .read(databaseServiceProvider)
                                  .setCoworkerHidden(name, hidden: false);
                            },
                            child: const Text(
                              'Restore',
                              style: TextStyle(
                                color: AppColors.pastelTeal,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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

class _BluetoothOffBanner extends ConsumerWidget {
  const _BluetoothOffBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapterAsync = ref.watch(bleAdapterStateProvider);
    final adapterState = adapterAsync.valueOrNull;

    if (adapterState == null ||
        adapterState == BluetoothAdapterState.on ||
        adapterState == BluetoothAdapterState.unknown) {
      return const SizedBox.shrink();
    }

    final (title, subtitle, canTurnOn) = switch (adapterState) {
      BluetoothAdapterState.unauthorized => (
          'Bluetooth Permission Required',
          'Grant Nearby Devices / Bluetooth access in system settings',
          false,
        ),
      BluetoothAdapterState.unavailable => (
          'Bluetooth Unsupported',
          'This device does not support Bluetooth Low Energy',
          false,
        ),
      _ => (
          'Bluetooth is Off',
          (!kIsWeb && Platform.isAndroid)
              ? 'Turn on Bluetooth to connect to your ring'
              : 'Enable Bluetooth in Control Center or System Settings',
          !kIsWeb && Platform.isAndroid,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.pastelCoral.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.pastelCoral.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.pastelCoral.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.bluetooth_disabled_rounded,
                color: AppColors.pastelCoral,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.pastelCoral,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
            if (canTurnOn)
              InkWell(
                onTap: () async {
                  try {
                    await FlutterBluePlus.turnOn();
                  } catch (_) {}
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.pastelCoral.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Turn On',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.pastelCoral,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          fontSize: 11,
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
          _PulsingBluetoothIcon(
            color: statusColor,
            isAnimating: state == BleConnectionState.connected,
          ),
          const SizedBox(width: 16),
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
    return switch (state) {
      BleConnectionState.connected => (
          'Connected',
          AppColors.pastelTeal,
          Icons.check_circle_outline_rounded,
        ),
      BleConnectionState.scanning => (
          'Scanning...',
          AppColors.pastelAmber,
          Icons.radar_rounded,
        ),
      BleConnectionState.connecting => (
          'Connecting...',
          AppColors.pastelAmber,
          Icons.sync_rounded,
        ),
      BleConnectionState.error => (
          'Error',
          AppColors.pastelCoral,
          Icons.error_outline_rounded,
        ),
      BleConnectionState.disconnected => (
          'Disconnected',
          AppColors.textTertiary,
          Icons.bluetooth_disabled_rounded,
        ),
    };
  }
}

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

class _ConnectedDeviceCard extends ConsumerWidget {
  const _ConnectedDeviceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionAsync = ref.watch(bleConnectionStateProvider);
    final state = connectionAsync.valueOrNull ?? BleConnectionState.disconnected;

    if (state != BleConnectionState.connected) {
      return const SizedBox.shrink();
    }

    final deviceName = ref.watch(connectedDeviceNameProvider) ?? 'Colmi R02';
    final batteryAsync = ref.watch(batteryStatusProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
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
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    await ref.read(bleServiceProvider).findDevice();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Blinking ring LED…'),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: AppColors.surfaceLight,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.pastelTeal.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.pastelTeal.withValues(alpha: 0.2),
                        width: 0.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Find My Ring',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppColors.pastelTeal,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () {
                    unawaited(ref.read(bleServiceProvider).syncAllTelemetry());
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Syncing ring activity & sleep…'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.surfaceLight,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.cardBorder,
                        width: 0.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Sync Now',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: InkWell(
              onTap: () async {
                await ref.read(bleServiceProvider).disconnect();
              },
              borderRadius: BorderRadius.circular(12),
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

class _ScanButton extends ConsumerWidget {
  const _ScanButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionAsync = ref.watch(bleConnectionStateProvider);
    final state = connectionAsync.valueOrNull ?? BleConnectionState.disconnected;

    final isScanning = state == BleConnectionState.scanning;
    final isConnecting = state == BleConnectionState.connecting;
    final isConnected = state == BleConnectionState.connected;
    final isDisabled = isConnected || isConnecting;

    final accentColor = isScanning ? AppColors.pastelAmber : AppColors.pastelTeal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: TextButton(
          onPressed: isDisabled
              ? null
              : () {
                  final service = ref.read(bleServiceProvider);
                  if (isScanning) {
                    AppLogger.info('Settings', 'Stopping scan...');
                    unawaited(service.stopScan());
                  } else {
                    AppLogger.info('Settings', 'Starting scan...');
                    unawaited(service.forceStartScan());
                  }
                },
          style: TextButton.styleFrom(
            backgroundColor: accentColor.withValues(alpha: 0.08),
            foregroundColor: accentColor,
            disabledForegroundColor: AppColors.textTertiary,
            disabledBackgroundColor: AppColors.surfaceVariant,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDisabled
                    ? AppColors.cardBorder
                    : accentColor.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isScanning || isConnecting) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.pastelAmber,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  isConnecting ? 'Connecting…' : 'Stop Scanning',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.pastelAmber,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ] else ...[
                Icon(
                  isConnected
                      ? Icons.bluetooth_connected_rounded
                      : Icons.search_rounded,
                  color:
                      isConnected ? AppColors.textTertiary : AppColors.pastelTeal,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isConnected ? 'Already Connected' : 'Scan for Ring',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: isConnected
                            ? AppColors.textTertiary
                            : AppColors.pastelTeal,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoveredDevicesList extends ConsumerWidget {
  const _DiscoveredDevicesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionAsync = ref.watch(bleConnectionStateProvider);
    final state = connectionAsync.valueOrNull ?? BleConnectionState.disconnected;
    final resultsAsync = ref.watch(scanResultsProvider);
    final hasResults = resultsAsync.valueOrNull?.isNotEmpty ?? false;

    if (state != BleConnectionState.scanning &&
        state != BleConnectionState.connecting &&
        !hasResults) {
      return const SizedBox.shrink();
    }

    return resultsAsync.when(
      data: (results) {
        final namedDevices = results.where((r) {
          final name = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : r.advertisementData.advName;
          return name.isNotEmpty;
        }).toList();

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
                'Nearby Devices (tap to connect)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ),
            ...namedDevices.map((r) {
              final resolvedName = r.device.platformName.isNotEmpty
                  ? r.device.platformName
                  : r.advertisementData.advName;
              final isR02 = resolvedName.toLowerCase().contains('r02');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () {
                    unawaited(
                      ref.read(bleServiceProvider).connectToDevice(r.device),
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: _cardDecoration(),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bluetooth_rounded,
                          color: isR02
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
                                resolvedName,
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
                        if (isR02)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
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
                ),
              );
            }),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _CheckForUpdatesTile extends ConsumerStatefulWidget {
  final String currentVersion;

  const _CheckForUpdatesTile({required this.currentVersion});

  @override
  ConsumerState<_CheckForUpdatesTile> createState() =>
      _CheckForUpdatesTileState();
}

class _CheckForUpdatesTileState extends ConsumerState<_CheckForUpdatesTile> {
  bool _checking = false;

  Future<void> _handleCheck() async {
    if (_checking) return;
    setState(() => _checking = true);

    final result = await ref.read(appUpdateServiceProvider).checkForUpdate();
    if (!mounted) return;
    setState(() => _checking = false);

    switch (result.status) {
      case UpdateCheckStatus.updateAvailable:
        if (result.release != null) {
          await AppUpdateDialog.show(context, result);
        }
      case UpdateCheckStatus.upToDate:
        _showSnack(
          'Spike v${result.currentVersion} is up to date.',
        );
      case UpdateCheckStatus.noReleaseFound:
        _showSnack('No APK release published on GitHub yet.');
      case UpdateCheckStatus.error:
        _showSnack(
          'Update check failed: ${result.errorMessage ?? 'Unknown error'}',
        );
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: Icons.system_update_rounded,
      title: 'Check for Updates',
      subtitle: _checking
          ? 'Checking GitHub Releases…'
          : 'v${widget.currentVersion} · Auto-updates via GitHub',
      accentColor: AppColors.pastelTeal,
      trailing: _checking
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.pastelTeal,
              ),
            )
          : null,
      onTap: _handleCheck,
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accentColor;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.accentColor = AppColors.pastelBlue,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 18),
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
              trailing ??
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

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
