import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/session.dart';

class SessionStore {
  SessionStore()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(),
        );

  static const _sessionKey = 'ceh_session_v1';

  final FlutterSecureStorage _storage;

  Future<void> save(CehSession session) async {
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode(session.toJson()),
    );
  }

  Future<CehSession?> load() async {
    final raw = await _storage.read(key: _sessionKey);
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
    await _storage.delete(key: _sessionKey);
  }
}
