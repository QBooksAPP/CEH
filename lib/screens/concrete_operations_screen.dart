import 'package:flutter/material.dart';

import '../models/session.dart';
import 'calibration_data_screen.dart';
import 'calibration_field_sheet_screen.dart';
import 'calibration_review_screen.dart';
import 'module_placeholder_screen.dart';

class ConcreteOperationsScreen extends StatelessWidget {
  const ConcreteOperationsScreen({super.key, required this.session});
  final CehSession session;

  @override
  Widget build(BuildContext context) {
    final admin = session.user.isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Concrete Operations',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tile(context, 'Calibration Field Sheet',
              'Enter mixer calibration trials', Icons.fact_check_outlined, () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CalibrationFieldSheetScreen(session: session),
              ),
            );
          }),
          _tile(context, 'Calibration Data',
              'View approved calibration values by mixer',
              Icons.analytics_outlined, () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CalibrationDataScreen(session: session),
              ),
            );
          }),
          if (admin)
            _tile(context, 'Calibration Review',
                'Approve, reject or reopen calibrations',
                Icons.verified_outlined, () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CalibrationReviewScreen(session: session),
                ),
              );
            }),
          _tile(context, 'Mix Designs',
              admin ? 'Create and manage mix designs' : 'View active mix designs',
              Icons.science_outlined,
              () => _placeholder(context, 'Mix Designs')),
          _tile(context, 'Mix Design Settings', 'Approved production settings',
              Icons.tune_outlined,
              () => _placeholder(context, 'Mix Design Settings')),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String title, String subtitle,
      IconData icon, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, size: 32),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  void _placeholder(BuildContext context, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ModulePlaceholderScreen(
          title: title,
          message:
              '$title will be connected after Calibration Data is confirmed.',
        ),
      ),
    );
  }
}
