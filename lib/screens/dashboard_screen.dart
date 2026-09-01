import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_environment.dart';
import '../core/ceh_theme.dart';
import '../core/api_client.dart';
import '../core/ceh_date_formatters.dart';
import '../core/update_service.dart';
import '../core/staging_update_installer.dart';
import '../core/view_mode.dart';
import '../models/session.dart';
import 'accounts/accounts_home_screen.dart';
import 'accounts/accounts_live_screens.dart';
import 'concrete_operations_screen.dart';
import 'company_regional_settings_screen.dart';
import 'module_placeholder_screen.dart';
import 'user_management_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.session,
    required this.onLogout,
    this.checkForUpdates = true,
    this.environment,
    this.updateService,
    this.stagingUpdateInstaller,
  });

  final CehSession session;
  final Future<void> Function() onLogout;
  final bool checkForUpdates;
  final CehAppEnvironment? environment;
  final CehUpdateService? updateService;
  final CehStagingUpdateInstaller? stagingUpdateInstaller;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  CehUpdateInfo? _update;
  bool _checkingUpdate = false;
  bool _downloadingUpdate = false;
  double _downloadProgress = 0;
  String? _versionText;

  CehSession get session => widget.session;
  CehAppEnvironment get environment => widget.environment ?? cehEnvironment;

  @override
  void initState() {
    super.initState();
    _refreshRegionalSettings();
    if (widget.checkForUpdates && environment.updateChecksEnabled) {
      _checkForUpdate(silent: true);
    }
  }

  Future<void> _refreshRegionalSettings() async {
    try {
      CehRegionalFormats.use(
          await const CehApiClient().companyRegionalSettings(session));
    } catch (_) {
      // The authenticated session's CEH-compatible settings remain usable.
    }
  }

  Future<void> _checkForUpdate({bool silent = false}) async {
    if (_checkingUpdate) return;

    if (mounted) {
      setState(() => _checkingUpdate = true);
    }

    try {
      final package = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(package.buildNumber) ?? 0;

      final updateService =
          widget.updateService ?? CehUpdateService(environment: environment);
      final update = await updateService.checkForUpdate(
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

    if (environment.isStaging) {
      await _downloadStagingUpdate(update);
      return;
    }

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

  Future<void> _downloadStagingUpdate(CehUpdateInfo update) async {
    if (_downloadingUpdate) return;
    final installer =
        widget.stagingUpdateInstaller ?? const CehStagingUpdateInstaller();
    CehVerifiedStagingUpdate verified;

    if (mounted) {
      setState(() {
        _downloadingUpdate = true;
        _downloadProgress = 0;
      });
    }

    try {
      verified = await installer.downloadAndVerify(
        update,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _downloadProgress = progress.clamp(0, 1));
          }
        },
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is CehUpdateException
                  ? error.message
                  : 'The CEH STAGING update could not be downloaded.',
            ),
          ),
        );
      }
      return;
    } finally {
      if (mounted) {
        setState(() => _downloadingUpdate = false);
      }
    }

    // The external Android installer is not CEH-controlled work. Clear the
    // modal/busy state before handing off so cancellation or an emulator that
    // never returns from the intent cannot leave CEH disabled.
    try {
      final result = await installer.launchInstaller(verified);
      if (result == CehInstallerLaunchResult.permissionRequested && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Allow CEH STAGING to install updates, then tap Download & Install again.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is CehUpdateException
                  ? error.message
                  : 'Android could not open the staging installer.',
            ),
          ),
        );
      }
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
          'e': true,
        },
      if (!admin && (user.isOperator || user.isSupervisor))
        {
          't': 'Petty Cash',
          's': 'My balance, expenses and approval status',
          'i': Icons.account_balance_wallet_outlined,
          'e': true,
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
      if (admin)
        {
          't': 'Company Settings',
          's': 'Regional formats, time zone and base currency',
          'i': Icons.public_outlined,
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
          if (environment.updateChecksEnabled)
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
            key: const ValueKey('dashboard-welcome-card'),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: environment.isStaging ? Colors.white : null,
              gradient: environment.isStaging
                  ? null
                  : const LinearGradient(
                      colors: [CehTheme.ink, CehTheme.secondaryText],
                    ),
              border: environment.isStaging
                  ? Border.all(color: CehTheme.border)
                  : null,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Welcome\n${user.fullName}\n${user.role}',
              style: TextStyle(
                color: environment.isStaging ? CehTheme.text : Colors.white,
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
                          color: CehTheme.ink,
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
                                environment.isStaging
                                    ? '${_update!.versionName} '
                                        '(build ${_update!.buildNumber}) is ready.'
                                    : 'Build ${_update!.buildNumber} is ready.',
                              ),
                              if (environment.isStaging &&
                                  (_update!.releaseNotes?.trim().isNotEmpty ??
                                      false)) ...[
                                const SizedBox(height: 6),
                                Text(_update!.releaseNotes!.trim()),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_downloadingUpdate) ...[
                      LinearProgressIndicator(
                        value: _downloadProgress > 0 ? _downloadProgress : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _downloadProgress > 0
                            ? 'Downloading ${(_downloadProgress * 100).round()}%'
                            : 'Preparing secure download…',
                        textAlign: TextAlign.center,
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: _downloadUpdate,
                        icon: const Icon(Icons.download),
                        label: Text(
                          environment.isStaging
                              ? 'Download & Install'
                              : 'Update now',
                        ),
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
                  } else if (m['t'] == 'Administration') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserManagementScreen(session: session),
                      ),
                    );
                  } else if (m['t'] == 'Accounts') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AccountsHomeScreen(session: session),
                      ),
                    );
                  } else if (m['t'] == 'Company Settings') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CompanyRegionalSettingsScreen(session: session),
                      ),
                    );
                  } else if (m['t'] == 'Petty Cash') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AccountsPettyCashScreen(session: session),
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
