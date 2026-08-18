import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/ceh_theme.dart';
import '../core/update_service.dart';
import '../core/view_mode.dart';
import '../models/session.dart';
import 'concrete_operations_screen.dart';
import 'module_placeholder_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.session,
    required this.onLogout,
  });

  final CehSession session;
  final Future<void> Function() onLogout;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _updateService = const CehUpdateService();

  CehUpdateInfo? _update;
  bool _checkingUpdate = false;
  String? _versionText;

  CehSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _checkForUpdate(silent: true);
  }

  Future<void> _checkForUpdate({bool silent = false}) async {
    if (_checkingUpdate) return;

    if (mounted) {
      setState(() => _checkingUpdate = true);
    }

    try {
      final package = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(package.buildNumber) ?? 0;

      final update = await _updateService.checkForUpdate(
        currentBuild: currentBuild,
      );

      if (!mounted) return;
      setState(() {
        _update = update;
        _versionText = '${package.version} (${package.buildNumber})';
      });

      if (!silent && update == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CEH is up to date.')),
        );
      }
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not check for updates right now.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _checkingUpdate = false);
      }
    }
  }

  Future<void> _downloadUpdate() async {
    final update = _update;
    if (update == null) return;

    final uri = Uri.parse(update.downloadUrl);
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the CEH update.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    final admin = isUiAdmin(context, session);
    final modules = <Map<String, dynamic>>[
      {
        't': 'Concrete Operations',
        's': 'Calibration, mix designs and mixer settings',
        'i': Icons.precision_manufacturing_outlined,
        'e': true,
      },
      if (admin)
        {
          't': 'Accounts',
          's': 'Expenses, income, petty cash and reports',
          'i': Icons.account_balance_wallet_outlined,
          'e': false,
        },
      if (admin)
        {
          't': 'Fleet & Equipment',
          's': 'Mixers, pumps, trucks and workshop equipment',
          'i': Icons.local_shipping_outlined,
          'e': false,
        },
      if (admin)
        {
          't': 'Administration',
          's': 'Users, history, approvals and audit trail',
          'i': Icons.admin_panel_settings_outlined,
          'e': true,
        },
    ];

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/images/ceh_logo.png',
          height: 34,
          fit: BoxFit.contain,
        ),
        actions: [
          if (user.isAdmin && admin)
            IconButton(
              tooltip: 'View as Operator',
              onPressed: CehViewModeScope.of(context).enableOperatorView,
              icon: const Icon(Icons.visibility_outlined),
            ),
          IconButton(
            tooltip: 'Check for updates',
            onPressed:
                _checkingUpdate ? null : () => _checkForUpdate(silent: false),
            icon: _checkingUpdate
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_alt),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [CehTheme.navy, CehTheme.blue],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Welcome\n${user.fullName}\n${user.role}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (_update != null) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.system_update,
                          size: 34,
                          color: CehTheme.blue,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CEH update available',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Build ${_update!.buildNumber} is ready.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _downloadUpdate,
                      icon: const Icon(Icons.download),
                      label: const Text('Update now'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'Company modules',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ...modules.map(
            (m) => Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Icon(m['i'] as IconData),
                title: Text(
                  m['t'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(m['s'] as String),
                trailing: (m['e'] as bool)
                    ? const Icon(Icons.chevron_right)
                    : const Text(
                        'COMING SOON',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                onTap: () {
                  if (m['t'] == 'Concrete Operations') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ConcreteOperationsScreen(session: session),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ModulePlaceholderScreen(
                          title: m['t'] as String,
                          message:
                              '${m['t']} will be connected as a later CEH module.',
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
          ),
          if (_versionText != null) ...[
            const SizedBox(height: 20),
            Text(
              'CEH $_versionText',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
