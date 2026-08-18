import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/mix_design.dart';
import '../models/calibration_record.dart';
import '../models/calibration_source.dart';
import '../models/production_settings.dart';
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

    final data = _decodeObject(response);

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

  Future<List<Map<String, dynamic>>> mixers(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/mixers.php'), headers: authHeaders(session))
        .timeout(const Duration(seconds: 20));

    final data = _decodeObject(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['ok'] != true) {
      throw ApiException(
        (data['error'] ?? 'MIXERS_FAILED').toString(),
        statusCode: response.statusCode,
      );
    }

    return (data['mixers'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> saveCalibrationDraft(
    CehSession session,
    Map<String, dynamic> payload,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/calibration_save.php'),
          headers: {
            ...authHeaders(session),
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 25));

    final data = _decodeObject(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['ok'] != true) {
      throw ApiException(
        (data['error'] ?? 'CALIBRATION_SAVE_FAILED').toString(),
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> submitCalibration(
    CehSession session,
    int calibrationId,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/calibration_submit.php'),
          headers: {
            ...authHeaders(session),
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode({'calibration_id': calibrationId}),
        )
        .timeout(const Duration(seconds: 25));

    final data = _decodeObject(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['ok'] != true) {
      final missing =
          (data['missing'] as List?)?.map((e) => e.toString()).join(', ');
      throw ApiException(
        missing == null || missing.isEmpty
            ? (data['error'] ?? 'CALIBRATION_SUBMIT_FAILED').toString()
            : '${data['error']}: $missing',
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  Future<List<CalibrationRecord>> calibrationRecords(
    CehSession session,
  ) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/calibration_records.php'),
          headers: authHeaders(session),
        )
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'CALIBRATION_RECORDS_FAILED');
    return (data['calibrations'] as List? ?? const [])
        .map((e) =>
            CalibrationRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> adminCalibrations(
    CehSession session,
  ) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/calibration_admin_list.php'),
          headers: authHeaders(session),
        )
        .timeout(const Duration(seconds: 25));

    final data = _decodeObject(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['ok'] != true) {
      throw ApiException(
        (data['error'] ?? 'CALIBRATION_ADMIN_LIST_FAILED').toString(),
        statusCode: response.statusCode,
      );
    }
    return (data['calibrations'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> reviewCalibration(
    CehSession session, {
    required int calibrationId,
    required String action,
    String reason = '',
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/calibration_review.php'),
          headers: {
            ...authHeaders(session),
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode({
            'calibration_id': calibrationId,
            'action': action,
            'reason': reason,
          }),
        )
        .timeout(const Duration(seconds: 25));

    final data = _decodeObject(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['ok'] != true) {
      throw ApiException(
        (data['error'] ?? 'CALIBRATION_REVIEW_FAILED').toString(),
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> reopenCalibration(
    CehSession session, {
    required int calibrationId,
    String reason = 'Reopened by Admin',
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/calibration_reopen.php'),
          headers: {
            ...authHeaders(session),
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode({'calibration_id': calibrationId, 'reason': reason}),
        )
        .timeout(const Duration(seconds: 25));

    final data = _decodeObject(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['ok'] != true) {
      throw ApiException(
        (data['error'] ?? 'CALIBRATION_REOPEN_FAILED').toString(),
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> approvedCalibrations(
    CehSession session,
  ) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/calibration_data.php'),
          headers: authHeaders(session),
        )
        .timeout(const Duration(seconds: 25));

    final data = _decodeObject(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['ok'] != true) {
      throw ApiException(
        (data['error'] ?? 'CALIBRATION_DATA_FAILED').toString(),
        statusCode: response.statusCode,
      );
    }

    return (data['calibrations'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<CalibrationSource>> approvedCalibrationSources(
    CehSession session,
  ) async =>
      (await approvedCalibrations(session))
          .map(CalibrationSource.fromJson)
          .toList();

  Future<List<MixDesign>> mixDesigns(CehSession session) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/mix_designs.php'),
          headers: authHeaders(session),
        )
        .timeout(const Duration(seconds: 25));

    final data = _decodeObject(response);
    _requireOk(response, data, 'MIX_DESIGNS_FAILED');

    return (data['mix_designs'] as List? ?? const [])
        .map(
          (item) => MixDesign.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<MixDesign> mixDesign(CehSession session, int mixDesignId) async {
    final uri = Uri.parse('$baseUrl/mix_design_get.php')
        .replace(queryParameters: {'mix_design_id': mixDesignId.toString()});
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));

    final data = _decodeObject(response);
    _requireOk(response, data, 'MIX_DESIGN_GET_FAILED');
    return MixDesign.fromJson(
      Map<String, dynamic>.from(data['mix_design'] as Map),
    );
  }

  Future<MixDesign> createMixDesign(
    CehSession session,
    Map<String, dynamic> payload,
  ) async {
    final data = await _postJson(
      session,
      'mix_design_create.php',
      payload,
      'MIX_DESIGN_CREATE_FAILED',
    );
    return MixDesign.fromJson(
      Map<String, dynamic>.from(data['mix_design'] as Map),
    );
  }

  Future<MixDesign> updateMixDesign(
    CehSession session,
    Map<String, dynamic> payload,
  ) async {
    final data = await _postJson(
      session,
      'mix_design_update.php',
      payload,
      'MIX_DESIGN_UPDATE_FAILED',
    );
    return MixDesign.fromJson(
      Map<String, dynamic>.from(data['mix_design'] as Map),
    );
  }

  Future<MixAdmixture> createMixAdmixture(
    CehSession session,
    Map<String, dynamic> payload,
  ) async {
    final data = await _postJson(
      session,
      'mix_admixture_create.php',
      payload,
      'MIX_ADMIXTURE_CREATE_FAILED',
    );
    return MixAdmixture.fromJson(
      Map<String, dynamic>.from(data['admixture'] as Map),
    );
  }

  Future<MixAdmixture> updateMixAdmixture(
    CehSession session,
    Map<String, dynamic> payload,
  ) async {
    final data = await _postJson(
      session,
      'mix_admixture_update.php',
      payload,
      'MIX_ADMIXTURE_UPDATE_FAILED',
    );
    return MixAdmixture.fromJson(
      Map<String, dynamic>.from(data['admixture'] as Map),
    );
  }

  Future<ProductionSettingsResult> previewSettings(CehSession session,
      {required int mixerId,
      required int mixDesignId,
      required double conveyorSpeed,
      int? calibrationId}) async {
    calibrationId = validateCalibrationOverride(session, calibrationId);
    final data = await _postJson(
        session,
        'settings_preview.php',
        {
          'mixer_id': mixerId,
          'mix_design_id': mixDesignId,
          'conveyor_speed': conveyorSpeed,
          if (calibrationId != null) 'calibration_id': calibrationId
        },
        'SETTINGS_PREVIEW_FAILED');
    return ProductionSettingsResult(data: data);
  }

  Future<ProductionSettingsResult> applySettings(CehSession session,
      {required int mixerId,
      required int mixDesignId,
      required double conveyorSpeed,
      int? calibrationId}) async {
    calibrationId = validateCalibrationOverride(session, calibrationId);
    final data = await _postJson(
        session,
        'settings_apply.php',
        {
          'mixer_id': mixerId,
          'mix_design_id': mixDesignId,
          'conveyor_speed': conveyorSpeed,
          if (calibrationId != null) 'calibration_id': calibrationId
        },
        'SETTINGS_APPLY_FAILED');
    return ProductionSettingsResult(data: data);
  }

  Future<List<Map<String, dynamic>>> productionSettingsHistory(
      CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/production_settings_history.php'),
            headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'SETTINGS_HISTORY_FAILED');
    return (data['history'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> _postJson(
    CehSession session,
    String endpoint,
    Map<String, dynamic> payload,
    String fallbackError,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/$endpoint'),
          headers: {
            ...authHeaders(session),
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 25));

    final data = _decodeObject(response);
    _requireOk(response, data, fallbackError);
    return data;
  }

  void _requireOk(
    http.Response response,
    Map<String, dynamic> data,
    String fallbackError,
  ) {
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['ok'] != true) {
      throw ApiException(
        (data['error'] ?? fallbackError).toString(),
        statusCode: response.statusCode,
      );
    }
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw ApiException(
        'INVALID_SERVER_RESPONSE',
        statusCode: response.statusCode,
      );
    }
  }

  Map<String, String> authHeaders(CehSession session) {
    return {
      'Authorization': '${session.tokenType} ${session.token}',
      'Accept': 'application/json',
    };
  }
}

int? validateCalibrationOverride(CehSession session, int? calibrationId) {
  if (calibrationId == null || calibrationId <= 0) return null;
  if (!session.user.isAdmin) {
    throw const ApiException('CALIBRATION_OVERRIDE_FORBIDDEN');
  }
  return calibrationId;
}
