import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/mix_design.dart';
import '../models/calibration_record.dart';
import '../models/calibration_source.dart';
import '../models/client.dart';
import '../models/project.dart';
import '../models/production_settings.dart';
import '../models/production_session.dart';
import '../models/session.dart';

class ApiException implements Exception {
  const ApiException(this.code, {this.statusCode, this.details = const {}});

  final String code;
  final int? statusCode;
  final Map<String, dynamic> details;

  @override
  String toString() => code;
}

class ProductionReportFile {
  const ProductionReportFile({required this.bytes, required this.filename});
  final Uint8List bytes;
  final String filename;
}

class CehApiClient {
  const CehApiClient();

  static const String baseUrl = 'https://qbook.concretehireng.com';

  Future<CehSession> login({
    required String login,
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
            'login': login.trim(),
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

  Future<List<CehUser>> users(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/users_list.php'),
            headers: authHeaders(session))
        .timeout(const Duration(seconds: 20));
    final data = _decodeObject(response);
    _requireOk(response, data, 'USERS_FAILED');
    return (data['users'] as List? ?? const [])
        .map((value) =>
            CehUser.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  Future<CehUser> createOperator(
    CehSession session, {
    required String fullName,
    required String username,
    required String password,
  }) async {
    final data = await _postJson(
      session,
      'users_create.php',
      {'full_name': fullName, 'username': username, 'password': password},
      'USER_CREATE_FAILED',
    );
    return CehUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<CehUser> updateUser(
    CehSession session, {
    required int userId,
    required String fullName,
    required String username,
    required bool isActive,
  }) async {
    final data = await _postJson(
      session,
      'users_update.php',
      {
        'user_id': userId,
        'full_name': fullName,
        'username': username,
        'is_active': isActive,
      },
      'USER_UPDATE_FAILED',
    );
    return CehUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<void> resetUserPassword(
    CehSession session, {
    required int userId,
    required String password,
  }) async {
    await _postJson(
      session,
      'users_reset_password.php',
      {'user_id': userId, 'new_password': password},
      'PASSWORD_RESET_FAILED',
    );
  }

  Future<List<Map<String, dynamic>>> mixers(CehSession session,
      {int? projectId, bool includeAllocation = false}) async {
    final uri = Uri.parse('$baseUrl/mixers.php').replace(queryParameters: {
      if (projectId != null) 'project_id': '$projectId',
      if (includeAllocation) 'include_allocation': '1',
    });
    final response = await http
        .get(uri, headers: authHeaders(session))
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
    CehSession session, {
    String lifecycle = 'ACTIVE',
    bool includeAllOperators = false,
  }) async {
    final uri =
        Uri.parse('$baseUrl/calibration_records.php').replace(queryParameters: {
      'status': lifecycle,
      'scope': includeAllOperators ? 'ALL' : 'OWN',
    });
    final response = await http
        .get(
          uri,
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

  Future<Map<String, dynamic>> calibrationHistory(
      CehSession session, int calibrationId) async {
    final uri = Uri.parse('$baseUrl/calibration_history.php')
        .replace(queryParameters: {'calibration_id': '$calibrationId'});
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'CALIBRATION_HISTORY_FAILED');
    return data;
  }

  Future<List<Map<String, dynamic>>> adminCalibrations(CehSession session,
      {String status = 'ACTIVE'}) async {
    final uri = Uri.parse('$baseUrl/calibration_admin_list.php')
        .replace(queryParameters: {'status': status});
    final response = await http
        .get(
          uri,
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

  Future<List<Map<String, dynamic>>> approvedCalibrations(CehSession session,
      {bool activeOnly = false}) async {
    final uri = Uri.parse('$baseUrl/calibration_data.php')
        .replace(queryParameters: activeOnly ? {'active_only': '1'} : null);
    final response = await http
        .get(
          uri,
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
      (await approvedCalibrations(session, activeOnly: true))
          .map(CalibrationSource.fromJson)
          .toList();

  Future<List<MixDesign>> mixDesigns(CehSession session,
      {int? clientId, int? projectId, String? status}) async {
    final uri = Uri.parse('$baseUrl/mix_designs.php').replace(queryParameters: {
      if (clientId != null) 'client_id': '$clientId',
      if (projectId != null) 'project_id': '$projectId',
      if (status != null) 'status': status,
    });
    final response = await http
        .get(
          uri,
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

  Future<List<ProductionSession>> productionSessions(CehSession session,
      {String? status}) async {
    final uri = Uri.parse('$baseUrl/production_sessions.php').replace(
      queryParameters: status == null ? null : {'status': status},
    );
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'PRODUCTION_SESSIONS_FAILED');
    return (data['sessions'] as List? ?? const [])
        .map((e) =>
            ProductionSession.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<CehClient>> clients(CehSession session,
      {bool activeOnly = true, String? status}) async {
    final uri = Uri.parse('$baseUrl/clients.php').replace(
      queryParameters: {
        if (activeOnly) 'active_only': '1',
        if (status != null) 'status': status,
      },
    );
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'CLIENTS_FAILED');
    return (data['clients'] as List? ?? const [])
        .map((e) => CehClient.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<CehClient> createClient(CehSession session, String name) async {
    final data = await _postJson(
        session, 'client_create.php', {'name': name}, 'CLIENT_CREATE_FAILED');
    return CehClient.fromJson(Map<String, dynamic>.from(data['client'] as Map));
  }

  Future<CehClient> updateClient(CehSession session,
      {required int clientId,
      required String name,
      required bool isActive}) async {
    final data = await _postJson(
        session,
        'client_update.php',
        {'client_id': clientId, 'name': name, 'is_active': isActive},
        'CLIENT_UPDATE_FAILED');
    return CehClient.fromJson(Map<String, dynamic>.from(data['client'] as Map));
  }

  Future<List<CehProject>> projects(CehSession session, int clientId,
      {bool activeOnly = true, String? status}) async {
    final uri = Uri.parse('$baseUrl/projects.php').replace(queryParameters: {
      'client_id': '$clientId',
      if (activeOnly) 'active_only': '1',
      if (!activeOnly && status != null) 'status': status,
    });
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'PROJECTS_FAILED');
    return (data['projects'] as List? ?? const [])
        .map((e) => CehProject.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<CehProject> createProject(CehSession session,
      {required int clientId, required String name}) async {
    final data = await _postJson(session, 'project_create.php',
        {'client_id': clientId, 'name': name}, 'PROJECT_CREATE_FAILED');
    return CehProject.fromJson(
        Map<String, dynamic>.from(data['project'] as Map));
  }

  Future<CehProject> updateProject(CehSession session,
      {required int projectId,
      required String name,
      required bool isActive}) async {
    final data = await _postJson(
        session,
        'project_update.php',
        {'project_id': projectId, 'name': name, 'is_active': isActive},
        'PROJECT_UPDATE_FAILED');
    return CehProject.fromJson(
        Map<String, dynamic>.from(data['project'] as Map));
  }

  Future<void> updateProjectMixer(CehSession session,
      {required int projectId,
      required int mixerId,
      required bool isActive}) async {
    await _postJson(
        session,
        'project_mixer_update.php',
        {'project_id': projectId, 'mixer_id': mixerId, 'is_active': isActive},
        'PROJECT_MIXER_UPDATE_FAILED');
  }

  Future<void> updateRecordLifecycle(CehSession session,
      {required String recordType,
      required int recordId,
      required String action}) async {
    await _postJson(
        session,
        'record_lifecycle.php',
        {
          'record_type': recordType,
          'record_id': recordId,
          'action': action,
        },
        'RECORD_LIFECYCLE_FAILED');
  }

  Future<void> validateClientMixDesign(CehSession session,
      {required int mixDesignId, required String status}) async {
    await _postJson(
        session,
        'mix_design_validate.php',
        {'mix_design_id': mixDesignId, 'status': status},
        'MIX_DESIGN_VALIDATION_FAILED');
  }

  Future<ProductionSession> productionSession(
      CehSession session, int id) async {
    final uri = Uri.parse('$baseUrl/production_session_get.php')
        .replace(queryParameters: {'session_id': '$id'});
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'PRODUCTION_SESSION_FAILED');
    return ProductionSession.fromJson(
        Map<String, dynamic>.from(data['session'] as Map));
  }

  Future<ProductionSession> createProductionSession(
      CehSession session, Map<String, dynamic> payload) async {
    final data = await _postJson(session, 'production_session_create.php',
        payload, 'PRODUCTION_SESSION_CREATE_FAILED');
    return ProductionSession.fromJson(
        Map<String, dynamic>.from(data['session'] as Map));
  }

  Future<ProductionSession> saveProductionLoad(CehSession session,
      {required int sessionId, int? loadId, required double volumeM3}) async {
    final data = await _postJson(
        session,
        'production_load_save.php',
        {
          'session_id': sessionId,
          if (loadId != null) 'load_id': loadId,
          'volume_m3': volumeM3,
        },
        'PRODUCTION_LOAD_SAVE_FAILED');
    return ProductionSession.fromJson(
        Map<String, dynamic>.from(data['session'] as Map));
  }

  Future<ProductionSession> signProductionSession(CehSession session,
      {required int sessionId,
      required String representativeName,
      required String signatureBase64}) async {
    final data = await _postJson(
        session,
        'production_session_sign.php',
        {
          'session_id': sessionId,
          'representative_name': representativeName,
          'signature_mime': 'image/png',
          'signature_base64': signatureBase64,
        },
        'PRODUCTION_SIGNOFF_FAILED');
    return ProductionSession.fromJson(
        Map<String, dynamic>.from(data['session'] as Map));
  }

  Future<ProductionReportFile> productionReportPdf(
      CehSession session, int sessionId) async {
    final uri = Uri.parse('$baseUrl/production_report_pdf.php')
        .replace(queryParameters: {'session_id': '$sessionId'});
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 40));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var error = 'PRODUCTION_REPORT_FAILED';
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map && data['error'] != null) {
          error = data['error'].toString();
        }
      } catch (_) {}
      throw ApiException(error, statusCode: response.statusCode);
    }
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().startsWith('application/pdf') ||
        response.bodyBytes.length < 5 ||
        String.fromCharCodes(response.bodyBytes.take(5)) != '%PDF-') {
      throw const ApiException('INVALID_PRODUCTION_REPORT');
    }
    final disposition = response.headers['content-disposition'] ?? '';
    final match = RegExp(r'filename="?([^";]+)"?', caseSensitive: false)
        .firstMatch(disposition);
    final filename = match?.group(1) ?? 'CEH-Production-Report.pdf';
    if (!RegExp(r'^CEH-PR-[0-9]{6,}\.pdf$').hasMatch(filename)) {
      throw const ApiException('INVALID_PRODUCTION_REPORT_FILENAME');
    }
    return ProductionReportFile(bytes: response.bodyBytes, filename: filename);
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
        details: data['context'] is Map
            ? Map<String, dynamic>.from(data['context'] as Map)
            : const {},
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
