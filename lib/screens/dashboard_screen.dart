\
import 'package:flutter/material.dart';

import '../core/ceh_theme.dart';
import '../models/session.dart';
import 'module_placeholder_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.session,
    required this.onLogout,
  });

  final CehSession session;
  final Future<void> Function() onLogout;

  List<_ModuleItem> _modules() {
    final user = session.user;

    final items = <_ModuleItem>[
      _ModuleItem(
        title: 'Concrete Operations',
        subtitle: 'Calibration, mix designs and mixer settings',
        icon: Icons.precision_manufacturing_outlined,
        enabled: true,
      ),
    ];

    if (user.isAdmin) {
      items.addAll(const [
        _ModuleItem(
          title: 'Accounts',
          subtitle: 'Expenses, income, petty cash and reports',
          icon: Icons.account_balance_wallet_outlined,
          enabled: false,
        ),
        _ModuleItem(
          title: 'Fleet & Equipment',
          subtitle: 'Mixers, pumps, trucks and workshop equipment',
          icon: Icons.local_shipping_outlined,
          enabled: false,
        ),
        _ModuleItem(
          title: 'Administration',
          subtitle: 'Users, history, approvals and audit trail',
          icon: Icons.admin_panel_settings_outlined,
          enabled: true,
        ),
      ]);
    }

    return items;
  }

  void _open(BuildContext context, _ModuleItem item) {
    final role = session.user.role;

    String message;
    if (item.title == 'Concrete Operations') {
      if (role == 'ADMIN') {
        message =
            'Next we will connect Calibration Review, Mix Designs, Mixer Management, Operator Settings, Calibration History and Production History.';
      } else {
        message =
            'Next we will connect Calibration Entry and Operator Settings for your role.';
      }
    } else if (item.title == 'Administration') {
      message =
          'Next we will connect Users, Calibration History, Production History and Audit Trail.';
    } else {
      message =
          '${item.title} is reserved in the CEH app structure and will be added as a later module.';
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModulePlaceholderScreen(
          title: item.title,
          message: message,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    final modules = _modules();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CEH',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [CehTheme.navy, CehTheme.blue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    child: Text(
                      _initials(user.fullName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.fullName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.role,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Company modules',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            ...modules.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _open(context, item),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: CehTheme.paleBlue,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              item.icon,
                              color: CehTheme.blue,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.subtitle,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          if (!item.enabled)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'COMING SOON',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10,
                                ),
                              ),
                            )
                          else
                            const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'CEH';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _ModuleItem {
  const _ModuleItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
}
