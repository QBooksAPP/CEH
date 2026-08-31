import 'package:flutter/material.dart';

import '../core/app_environment.dart';
import '../core/ceh_theme.dart';
import '../models/mixer_context.dart';

class MixerContextHeader extends StatelessWidget {
  const MixerContextHeader({
    super.key,
    required this.context,
    this.stoneSize,
    this.environment,
  });

  final MixerContext context;
  final String? stoneSize;
  final CehAppEnvironment? environment;

  @override
  Widget build(BuildContext buildContext) {
    final appEnvironment = environment ?? cehEnvironment;
    final assignment = context.assignment;
    final detail = assignment == null
        ? context.hasAssignmentConflict
            ? 'Multiple active assignments — Admin action required'
            : 'Not Assigned'
        : [assignment.clientName, assignment.projectName, stoneSize]
            .where((value) => value != null && value.trim().isNotEmpty)
            .join(' • ');
    return Container(
      key: const ValueKey('mixer-context-header-card'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: appEnvironment.isStaging
            ? Colors.white
            : Theme.of(buildContext).colorScheme.primaryContainer,
        border: appEnvironment.isStaging
            ? Border.all(color: CehTheme.border)
            : null,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('MIXER ${context.code}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        Text(detail, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
