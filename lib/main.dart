import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'core/ceh_theme.dart';
import 'core/ceh_date_formatters.dart';
import 'core/session_store.dart';
import 'core/view_mode.dart';
import 'models/session.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  runApp(const CehApp());
}

class CehApp extends StatefulWidget {
  const CehApp({super.key});

  @override
  State<CehApp> createState() => _CehAppState();
}

class _CehAppState extends State<CehApp> {
  final SessionStore _sessionStore = SessionStore();
  final CehViewModeController _viewMode = CehViewModeController();

  CehSession? _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    CehSession? session;

    try {
      session = await _sessionStore.load();
    } catch (_) {
      session = null;
    }

    if (!mounted) return;

    setState(() {
      _session = session;
      _loading = false;
    });
    if (session != null) CehRegionalFormats.use(session.user.regionalSettings);
  }

  Future<void> _onLoggedIn(CehSession session) async {
    CehRegionalFormats.use(session.user.regionalSettings);
    _viewMode.returnToAdmin();
    if (mounted) {
      setState(() => _session = session);
    }

    try {
      await _sessionStore.save(session);
    } catch (_) {
      // Keep the user logged in for this app session.
    }
  }

  Future<void> _logout() async {
    _viewMode.returnToAdmin();
    try {
      await _sessionStore.clear();
    } catch (_) {}

    if (!mounted) return;
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CEH',
      theme: CehTheme.light(),
      builder: (context, child) => CehViewModeScope(
        controller: _viewMode,
        child: AnimatedBuilder(
          animation: _viewMode,
          builder: (context, _) => Column(
            children: [
              if (_viewMode.viewAsOperator)
                Material(
                  color: Colors.amber.shade200,
                  child: SafeArea(
                    bottom: false,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.visibility_outlined),
                      title: const Text(
                        'Viewing as Operator',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      trailing: TextButton(
                        onPressed: _viewMode.returnToAdmin,
                        child: const Text('Return to Admin'),
                      ),
                    ),
                  ),
                ),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
        ),
      ),
      home: _loading
          ? const _StartupScreen()
          : _session == null
              ? LoginScreen(onLoggedIn: _onLoggedIn)
              : DashboardScreen(
                  session: _session!,
                  onLogout: _logout,
                ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'CEH',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 18),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
