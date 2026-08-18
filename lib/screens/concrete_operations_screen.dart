import 'package:flutter/material.dart';

import '../core/internal_navigation.dart';
import '../core/view_mode.dart';
import '../models/session.dart';
import 'calibration_data_screen.dart';
import 'calibration_field_sheet_screen.dart';
import 'calibration_review_screen.dart';
import 'calibration_records_screen.dart';
import 'client_management_screen.dart';
import 'mix_designs_screen.dart';
import 'mix_design_settings_screen.dart';
import 'production_log_screen.dart';
import 'settings_history_screen.dart';

class ConcreteOperationsScreen extends StatelessWidget {
  const ConcreteOperationsScreen({super.key, required this.session});
  final CehSession session;

  @override
  Widget build(BuildContext context) {
    final admin = isUiAdmin(context, session);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Concrete Operations',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: cehHomeAction(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(
              title: 'CALIBRATION', icon: Icons.fact_check_outlined),
          _tile(
            context,
            'New Calibration',
            'Enter mixer calibration trials',
            Icons.fact_check_outlined,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CalibrationFieldSheetScreen(session: session),
                ),
              );
            },
          ),
          _tile(
            context,
            'My Calibrations',
            'View, correct and resubmit your calibration records',
            Icons.history_outlined,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        CalibrationRecordsScreen(session: session))),
          ),
          if (admin)
            _tile(
              context,
              'Calibration Data',
              'View approved calibration values by mixer',
              Icons.analytics_outlined,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CalibrationDataScreen(session: session),
                  ),
                );
              },
            ),
          if (admin)
            _tile(
              context,
              'Calibration Review',
              'Approve, reject or reopen calibrations',
              Icons.verified_outlined,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CalibrationReviewScreen(session: session),
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          const _SectionHeader(
              title: 'PRODUCTION',
              icon: Icons.precision_manufacturing_outlined),
          _tile(
            context,
            admin ? 'Mix Design Settings' : 'Mixer Settings',
            admin
                ? 'Detailed production calculations and calibration source'
                : 'Get operational machine settings',
            Icons.tune_outlined,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => MixDesignSettingsScreen(session: session))),
          ),
          _tile(
              context,
              'Production Log',
              'Daily loads and client sign-off',
              Icons.receipt_long_outlined,
              () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ProductionLogScreen(session: session)))),
          if (admin) ...[
            _tile(
                context,
                'Clients',
                'Add, edit and activate production clients',
                Icons.business_outlined,
                () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            ClientManagementScreen(session: session)))),
            _tile(
                context,
                'Mix Designs',
                'Create and manage mix designs',
                Icons.science_outlined,
                () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => MixDesignsScreen(session: session)))),
            _tile(
                context,
                'Settings History',
                'Review applied production settings',
                Icons.history_outlined,
                () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            SettingsHistoryScreen(session: session)))),
          ],
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Row(children: [
          Icon(icon),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2))
        ]),
      );
}
