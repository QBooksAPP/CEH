import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_environment.dart';
import '../models/session.dart';

class SessionStore {
  SessionStore({CehAppEnvironment? environment})
      : environment = environment ?? cehEnvironment,
        _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(),
        );

  final CehAppEnvironment environment;

  final FlutterSecureStorage _storage;

  String get sessionKey => environment.secureStorageKey('session_v1');

  Future<void> save(CehSession session) async {
    await _storage.write(
      key: sessionKey,
      value: jsonEncode(session.toJson()),
    );
  }

  Future<CehSession?> load() async {
    final raw = await _storage.read(key: sessionKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final session = CehSession.fromJson(
        Map<String, dynamic>.from(decoded),
      );

      if (session.token.isEmpty || !session.user.isActive) {
        return null;
      }

      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: sessionKey);
  }
}
