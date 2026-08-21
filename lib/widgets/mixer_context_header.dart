import 'package:flutter/material.dart';

import '../models/mixer_context.dart';

class MixerContextHeader extends StatelessWidget {
  const MixerContextHeader({super.key, required this.context, this.stoneSize});

  final MixerContext context;
  final String? stoneSize;

  @override
  Widget build(BuildContext buildContext) {
    final assignment = context.assignment;
    final detail = assignment == null
        ? context.hasAssignmentConflict
            ? 'Multiple active assignments — Admin action required'
            : 'Not Assigned'
        : [assignment.clientName, assignment.projectName, stoneSize]
            .where((value) => value != null && value.trim().isNotEmpty)
            .join(' • ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(buildContext).colorScheme.primaryContainer,
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
