import 'package:flutter/material.dart';
import '../../config/theme.dart';

class StepNavigation extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const StepNavigation({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final canGoPrevious = currentStep > 0;
    final canGoNext = currentStep < totalSteps - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.bgTertiary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Previous Button
          _buildNavButton(
            context,
            icon: Icons.chevron_left,
            onPressed: canGoPrevious ? onPrevious : null,
            enabled: canGoPrevious,
          ),

          // Step Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'Adim ${currentStep + 1} / $totalSteps',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.textSecondary,
              ),
            ),
          ),

          // Next Button
          _buildNavButton(
            context,
            icon: Icons.chevron_right,
            onPressed: canGoNext ? onNext : null,
            enabled: canGoNext,
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(
    BuildContext context, {
    required IconData icon,
    VoidCallback? onPressed,
    required bool enabled,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 20,
            color: enabled ? AppTheme.primary : context.textMuted,
          ),
        ),
      ),
    );
  }
}
