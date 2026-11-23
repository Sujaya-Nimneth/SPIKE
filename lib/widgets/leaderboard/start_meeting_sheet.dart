import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/stress_providers.dart';
import '../../theme/app_colors.dart';
import 'coworker_picker_field.dart';

/// Bottom sheet to start a live meeting session with tagged coworkers.
class StartMeetingSheet extends ConsumerStatefulWidget {
  const StartMeetingSheet({super.key});

  @override
  ConsumerState<StartMeetingSheet> createState() => _StartMeetingSheetState();
}

class _StartMeetingSheetState extends ConsumerState<StartMeetingSheet> {
  final _titleController = TextEditingController();
  final _nameController = TextEditingController();
  final Set<String> _selectedCoworkers = {};

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

  @override
  Widget build(BuildContext context) {
    final savedNames = ref.watch(coworkerNamesProvider).valueOrNull ?? const [];
    final allChips = {...savedNames, ..._selectedCoworkers}.toList();

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
            Text(
              'Start Live Meeting Session',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Select who is in the room. Any heart rate stress spike detected '
              'while the session is active will automatically tag them.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Meeting title (optional, e.g. Sprint Review)',
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
              accentColor: AppColors.pastelTeal,
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
                  backgroundColor: AppColors.pastelTeal,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _selectedCoworkers.isEmpty
                    ? null
                    : () {
                        ref.read(activeMeetingProvider.notifier).startSession(
                              attendees: _selectedCoworkers.toList(),
                              title: _titleController.text,
                            );
                        Navigator.of(context).pop();
                      },
                child: const Text(
                  'Start Monitoring Meeting',
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
