import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'app_environment.dart';

/// A request survives navigation/process death until its authoritative outcome
/// is known. Never create another request key merely because a POST timed out.
class CreditNotePendingStore {
  const CreditNotePendingStore();
  static const _storage = FlutterSecureStorage();
  String _key(int user, int invoice) =>
      cehEnvironment.secureStorageKey('credit_note_pending_${user}_$invoice');
  Future<Map<String, dynamic>?> load(int user, int invoice) async {
    final raw = await _storage.read(key: _key(user, invoice));
    return raw == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> save(int user, int invoice, Map<String, dynamic> request) =>
      _storage.write(key: _key(user, invoice), value: jsonEncode(request));
  Future<void> clear(int user, int invoice) =>
      _storage.delete(key: _key(user, invoice));
  static String newKey() {
    final random = Random.secure();
    return List.generate(
            24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
