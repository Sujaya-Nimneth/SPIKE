import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Shared coworker name input + saved chip multi-selector used in both
/// [StartMeetingSheet] and [TagSpikeSheet].
class CoworkerPickerField extends StatelessWidget {
  final TextEditingController controller;
  final List<String> allChips;
  final Set<String> selectedCoworkers;
  final Color accentColor;
  final VoidCallback onAddTypedName;
  final void Function(String name, bool selected) onToggleCoworker;

  const CoworkerPickerField({
    super.key,
    required this.controller,
    required this.allChips,
    required this.selectedCoworkers,
    required this.accentColor,
    required this.onAddTypedName,
    required this.onToggleCoworker,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onSubmitted: (_) => onAddTypedName(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Add coworker name…',
                  hintStyle: const TextStyle(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onAddTypedName,
              style: IconButton.styleFrom(
                backgroundColor: accentColor.withValues(alpha: 0.15),
              ),
              icon: Icon(Icons.add_rounded, color: accentColor),
            ),
          ],
        ),
        if (allChips.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allChips.map((name) {
              final selected = selectedCoworkers.contains(name);
              return FilterChip(
                label: Text(name),
                selected: selected,
                selectedColor: accentColor.withValues(alpha: 0.2),
                checkmarkColor: accentColor,
                backgroundColor: AppColors.surfaceVariant,
                labelStyle: TextStyle(
                  color: selected ? accentColor : AppColors.textSecondary,
                  fontSize: 12,
                ),
                onSelected: (val) => onToggleCoworker(name, val),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
