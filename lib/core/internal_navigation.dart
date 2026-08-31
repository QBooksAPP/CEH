import 'package:flutter/material.dart';

typedef CehCanLeave = Future<bool> Function();

Future<void> goToCehHome(
  BuildContext context, {
  CehCanLeave? canLeave,
}) async {
  if (canLeave != null && !await canLeave()) return;
  if (!context.mounted) return;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

Future<bool> confirmCehDiscardChanges(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this page?'),
        content: const Text(
          'Any unsaved information on this page will be discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Go Home'),
          ),
        ],
      ),
    ) ??
    false;

List<Widget> cehHomeAction(
  BuildContext context, {
  CehCanLeave? canLeave,
}) =>
    [
      IconButton(
        key: const ValueKey('ceh-home-action'),
        tooltip: 'Home',
        onPressed: () => goToCehHome(context, canLeave: canLeave),
        icon: const Icon(Icons.home_outlined),
      ),
    ];
