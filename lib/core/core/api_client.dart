\
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/session.dart';

class ApiException implements Exception {
  const ApiException(this.code, {this.statusCode});

  final String code;
  final int? statusCode;

  @override
  String toString() => code;
}

class CehApiClient {
  const CehApiClient();

  static const String baseUrl = 'https://qbook.concretehireng.com';

  Future<CehSession> login({
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/login.php'),
          headers: const {
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'email': email.trim().toLowerCase(),
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 20));

    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(
        jsonDecode(response.body) as Map,
      );
    } catch (_) {
      throw ApiException(
        'INVALID_SERVER_RESPONSE',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['ok'] != true) {
      throw ApiException(
        (data['error'] ?? 'LOGIN_FAILED').toString(),
        statusCode: response.statusCode,
      );
    }

    final session = CehSession.fromJson(data);

    if (session.token.isEmpty ||
        session.user.id <= 0 ||
        session.user.role.isEmpty) {
      throw const ApiException('INVALID_LOGIN_RESPONSE');
    }

    return session;
  }

  Map<String, String> authHeaders(CehSession session) {
    return {
      'Authorization': '${session.tokenType} ${session.token}',
      'Accept': 'application/json',
    };
  }
}
