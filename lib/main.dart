\
import 'package:flutter/material.dart';

import 'core/ceh_theme.dart';
import 'core/session_store.dart';
import 'models/session.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CehApp());
}

class CehApp extends StatefulWidget {
  const CehApp({super.key});

  @override
  State<CehApp> createState() => _CehAppState();
}

class _CehAppState extends State<CehApp> {
  final SessionStore _sessionStore = SessionStore();

  CehSession? _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final session = await _sessionStore.load();

    if (!mounted) return;
    setState(() {
      _session = session;
      _loading = false;
    });
  }

  Future<void> _onLoggedIn(CehSession session) async {
    await _sessionStore.save(session);

    if (!mounted) return;
    setState(() => _session = session);
  }

  Future<void> _logout() async {
    await _sessionStore.clear();

    if (!mounted) return;
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CEH',
      theme: CehTheme.light(),
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
