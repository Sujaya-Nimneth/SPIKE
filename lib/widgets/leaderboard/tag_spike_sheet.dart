import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/stress_event.dart';
import '../../providers/ble_providers.dart';
import '../../providers/stress_providers.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_formatter.dart';
import 'coworker_picker_field.dart';

/// Bottom sheet to tag coworkers on an existing untagged stress spike or log a
/// manual spike.
class TagSpikeSheet extends ConsumerStatefulWidget {
  final StressEvent? existingEvent;

  const TagSpikeSheet({super.key, this.existingEvent});

  @override
  ConsumerState<TagSpikeSheet> createState() => _TagSpikeSheetState();
}

class _TagSpikeSheetState extends ConsumerState<TagSpikeSheet> {
  late final TextEditingController _titleController;
  final _nameController = TextEditingController();
  late final Set<String> _selectedCoworkers;
  double _peakHr = 110;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingEvent;
    _titleController =
        TextEditingController(text: existing?.meetingTitle ?? '');
    _selectedCoworkers = {...?existing?.attendees};
    if (existing != null) {
      _peakHr = existing.peakHr.toDouble().clamp(85, 190);
    } else {
      final liveHr = ref.read(latestHeartRateProvider);
      if (liveHr != null && liveHr >= 85) {
        _peakHr = liveHr.toDouble().clamp(85, 190);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _addTypedName() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _selectedCoworkers.add(trimmed);
      _nameController.clear();
    });
    unawaited(ref.read(databaseServiceProvider).addCoworker(trimmed));
  }

  Future<void> _save() async {
    if (_selectedCoworkers.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseServiceProvider);
      final existing = widget.existingEvent;

      if (existing != null && existing.id != null) {
        await db.updateEventAttendees(
          existing.id!,
          _selectedCoworkers.toList(),
          meetingTitle: _titleController.text,
        );
      } else {
        final baseline =
            ref.read(stressAnalyzerProvider).currentBaseline?.round() ?? 72;
        final event = StressEvent(
          timestamp: DateTime.now(),
          peakHr: _peakHr.round(),
          baselineHr: baseline,
          meetingTitle: _titleController.text.trim().isEmpty
              ? 'Tagged Meeting'
              : _titleController.text.trim(),
          attendees: _selectedCoworkers.toList(),
          durationSeconds: 180,
          label: StressEventLabel.confirmed,
        );
        await db.insertStressEvent(event);
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _dismissFalsePositive() async {
    if (_isSaving) return;
    final existing = widget.existingEvent;
    if (existing?.id == null) return;
    setState(() => _isSaving = true);
    try {
      await ref
          .read(databaseServiceProvider)
          .updateEventLabel(existing!.id!, StressEventLabel.dismissed);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedNames = ref.watch(coworkerNamesProvider).valueOrNull ?? const [];
    final allChips = {...savedNames, ..._selectedCoworkers}.toList();
    final existing = widget.existingEvent;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    existing != null
                        ? 'Tag Stress Spike (${existing.peakHr} bpm)'
                        : 'Tag Coworker Stress Spike',
                    style: Theme.of(context).textTheme.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (existing?.id != null)
                  TextButton(
                    onPressed: _isSaving ? null : _dismissFalsePositive,
                    child: const Text(
                      'Not Stress',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              existing != null
                  ? 'Recorded ${DateFormatter.formatShortDateTime(existing.timestamp)} · Baseline ${existing.baselineHr} bpm'
                  : 'Tag the coworker(s) who triggered this heart rate spike.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            if (existing == null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Peak Heart Rate',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '${_peakHr.round()} bpm',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.pastelCoral,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              Slider(
                value: _peakHr,
                min: 85,
                max: 190,
                divisions: 105,
                activeColor: AppColors.pastelCoral,
                onChanged: (v) => setState(() => _peakHr = v),
              ),
            ],
            TextField(
              controller: _titleController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Meeting context (e.g. Architecture Review)',
                hintStyle: const TextStyle(color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            CoworkerPickerField(
              controller: _nameController,
              allChips: allChips,
              selectedCoworkers: _selectedCoworkers,
              accentColor: AppColors.pastelCoral,
              onAddTypedName: _addTypedName,
              onToggleCoworker: (name, val) {
                setState(() {
                  if (val) {
                    _selectedCoworkers.add(name);
                  } else {
                    _selectedCoworkers.remove(name);
                  }
                });
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.pastelCoral,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed:
                    (_selectedCoworkers.isEmpty || _isSaving) ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : const Text(
                        'Save Coworker Tag',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
