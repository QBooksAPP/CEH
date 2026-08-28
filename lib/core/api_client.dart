import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/mix_design.dart';
import '../models/accounts.dart';
import '../models/calibration_record.dart';
import '../models/calibration_source.dart';
import '../models/client.dart';
import '../models/project.dart';
import '../models/mixer_context.dart';
import '../models/production_settings.dart';
import '../models/production_session.dart';
import '../models/session.dart';
import '../models/company_regional_settings.dart';

class ApiException implements Exception {
  const ApiException(this.code, {this.statusCode, this.details = const {}});

  final String code;
  final int? statusCode;
  final Map<String, dynamic> details;

  @override
  String toString() => code;
}

Map<String, dynamic> decodeApiObjectResponse(http.Response response) {
  try {
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  } catch (_) {
    if (response.statusCode == 404) {
      throw ApiException(
        'BACKEND_UPDATE_REQUIRED',
        statusCode: response.statusCode,
      );
    }
    throw ApiException(
      'INVALID_SERVER_RESPONSE',
      statusCode: response.statusCode,
    );
  }
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

  Future<List<MixerContext>> mixerContexts(CehSession session,
      {bool includeHistory = false}) async {
    final uri = Uri.parse('$baseUrl/mixer_contexts.php').replace(
        queryParameters: includeHistory ? {'include_history': '1'} : null);
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 20));
    final data = _decodeObject(response);
    _requireOk(response, data, 'MIXER_CONTEXTS_FAILED');
    return (data['mixers'] as List? ?? const [])
        .map((item) =>
            MixerContext.fromJson(Map<String, dynamic>.from(item as Map)))
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
    int? mixerId,
    int? clientId,
    int? projectId,
  }) async {
    final uri =
        Uri.parse('$baseUrl/calibration_records.php').replace(queryParameters: {
      'status': lifecycle,
      'scope': includeAllOperators ? 'ALL' : 'OWN',
      if (mixerId != null) 'mixer_id': '$mixerId',
      if (clientId != null) 'client_id': '$clientId',
      if (projectId != null) 'project_id': '$projectId',
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
      {String status = 'ACTIVE',
      int? mixerId,
      int? clientId,
      int? projectId}) async {
    final query = <String, String>{'status': status};
    if (mixerId != null) query['mixer_id'] = '$mixerId';
    if (clientId != null) query['client_id'] = '$clientId';
    if (projectId != null) query['project_id'] = '$projectId';
    final uri = Uri.parse('$baseUrl/calibration_admin_list.php')
        .replace(queryParameters: query);
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
      {String? status, int? mixerId}) async {
    final uri = Uri.parse('$baseUrl/production_sessions.php').replace(
      queryParameters: {
        if (status != null) 'status': status,
        if (mixerId != null) 'mixer_id': '$mixerId',
      },
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

  Future<List<FinancialAccount>> financialAccounts(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/accounts_chart.php'),
            headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'ACCOUNTS_CHART_FAILED');
    return (data['accounts'] as List? ?? const [])
        .map((item) =>
            FinancialAccount.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<BillingInvoice>> invoices(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/invoices.php'), headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'INVOICES_FAILED');
    return (data['invoices'] as List? ?? const [])
        .map((value) =>
            BillingInvoice.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  Future<List<BillingInvoice>> outstandingInvoices(
      CehSession session, int clientId) async {
    final uri = Uri.parse('$baseUrl/invoices.php').replace(
        queryParameters: {'client_id': '$clientId', 'outstanding_only': '1'});
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'OUTSTANDING_INVOICES_FAILED');
    return (data['invoices'] as List? ?? const [])
        .map((value) =>
            BillingInvoice.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  Future<BillingInvoiceDetail> invoiceDetails(
      CehSession session, int invoiceId) async {
    final uri = Uri.parse('$baseUrl/invoices.php')
        .replace(queryParameters: {'id': '$invoiceId'});
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'INVOICE_DETAILS_FAILED');
    return BillingInvoiceDetail.fromJson(data);
  }

  Future<ProductionReportFile> invoicePdf(
      CehSession session, int invoiceId) async {
    final uri = Uri.parse('$baseUrl/invoice_pdf.php')
        .replace(queryParameters: {'invoice_id': '$invoiceId'});
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 40));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var error = 'INVOICE_PDF_FAILED';
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map && data['error'] != null) error = '${data['error']}';
      } catch (_) {}
      throw ApiException(error, statusCode: response.statusCode);
    }
    if (!(response.headers['content-type'] ?? '')
            .toLowerCase()
            .startsWith('application/pdf') ||
        response.bodyBytes.length < 5 ||
        String.fromCharCodes(response.bodyBytes.take(5)) != '%PDF-') {
      throw const ApiException('INVALID_INVOICE_PDF');
    }
    final disposition = response.headers['content-disposition'] ?? '';
    final match = RegExp(r'filename="?([^";]+)"?', caseSensitive: false)
        .firstMatch(disposition);
    final filename = match?.group(1) ?? 'CEH-Invoice.pdf';
    return ProductionReportFile(bytes: response.bodyBytes, filename: filename);
  }

  Future<List<ClientPayment>> clientPayments(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/client_payments.php'),
            headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'CLIENT_PAYMENTS_FAILED');
    return (data['payments'] as List? ?? const [])
        .map((e) => ClientPayment.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> clientPaymentDetails(
      CehSession session, int id) async {
    final uri = Uri.parse('$baseUrl/client_payments.php')
        .replace(queryParameters: {'id': '$id'});
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'CLIENT_PAYMENT_DETAILS_FAILED');
    return data;
  }

  Future<ProductionReportFile> clientPaymentPdf(
          CehSession session, int id) async =>
      _billingPdf(session, 'client_payment_pdf.php', {'payment_id': '$id'},
          'CLIENT_PAYMENT_PDF_FAILED', 'CEH-Client-Payment.pdf');
  Future<List<EstimateSummary>> estimates(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/estimates.php'), headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'ESTIMATES_FAILED');
    return (data['estimates'] as List? ?? const [])
        .map((e) =>
            EstimateSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> estimateDetails(
      CehSession session, int id) async {
    final uri = Uri.parse('$baseUrl/estimates.php')
        .replace(queryParameters: {'id': '$id'});
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'ESTIMATE_DETAILS_FAILED');
    return data;
  }

  Future<Map<String, dynamic>> saveEstimate(
          CehSession session, Map<String, dynamic> payload) =>
      _postJson(session, 'estimate_save.php', payload, 'ESTIMATE_SAVE_FAILED');
  Future<void> estimateAction(
          CehSession session, String endpoint, Map<String, dynamic> payload) =>
      _postJson(session, endpoint, payload, 'ESTIMATE_ACTION_FAILED')
          .then((_) {});
  Future<Map<String, dynamic>> convertEstimate(
          CehSession session, Map<String, dynamic> payload) =>
      _postJson(
          session, 'estimate_convert.php', payload, 'ESTIMATE_CONVERT_FAILED');
  Future<int> uploadEstimateAcceptanceEvidence(CehSession session,
      int estimateId, String filename, String mimeType, Uint8List bytes) async {
    final data = await _postJson(
        session,
        'estimate_acceptance_evidence_upload.php',
        {
          'estimate_id': estimateId,
          'filename': filename,
          'mime_type': mimeType,
          'data_base64': base64Encode(bytes)
        },
        'ESTIMATE_ACCEPTANCE_EVIDENCE_UPLOAD_FAILED');
    return ((data['evidence'] as Map)['id'] as num).toInt();
  }

  Future<ProductionReportFile> estimatePdf(CehSession session, int id) async =>
      _billingPdf(session, 'estimate_pdf.php', {'estimate_id': '$id'},
          'ESTIMATE_PDF_FAILED', 'CEH-Estimate.pdf');
  Future<ProductionReportFile> _billingPdf(CehSession session, String endpoint,
      Map<String, String> query, String fallback, String filename) async {
    final uri = Uri.parse('$baseUrl/$endpoint').replace(queryParameters: query);
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 40));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var error = fallback;
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map && data['error'] != null) error = '${data['error']}';
      } catch (_) {}
      throw ApiException(error, statusCode: response.statusCode);
    }
    if (!(response.headers['content-type'] ?? '')
            .toLowerCase()
            .startsWith('application/pdf') ||
        response.bodyBytes.length < 5 ||
        String.fromCharCodes(response.bodyBytes.take(5)) != '%PDF-') {
      throw ApiException(fallback);
    }
    final disposition = response.headers['content-disposition'] ?? '';
    final match = RegExp(r'filename="?([^";]+)"?', caseSensitive: false)
        .firstMatch(disposition);
    return ProductionReportFile(
        bytes: response.bodyBytes, filename: match?.group(1) ?? filename);
  }

  Future<List<BillableProductionReport>> billableProductionReports(
      CehSession session, int clientId) async {
    final uri = Uri.parse('$baseUrl/billable_production_reports.php')
        .replace(queryParameters: {'client_id': '$clientId'});
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'BILLABLE_REPORTS_FAILED');
    return (data['reports'] as List? ?? const [])
        .map((value) => BillableProductionReport.fromJson(
            Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> saveInvoice(
      CehSession session, Map<String, dynamic> payload) async {
    final data = await _postJson(
        session, 'invoice_save.php', payload, 'INVOICE_SAVE_FAILED');
    return Map<String, dynamic>.from(data['invoice'] as Map);
  }

  Future<void> issueInvoice(CehSession session, int invoiceId) => _postJson(
          session,
          'invoice_issue.php',
          {'invoice_id': invoiceId},
          'INVOICE_ISSUE_FAILED')
      .then((_) {});

  Future<Map<String, dynamic>> saveCustomerReceipt(
      CehSession session, Map<String, dynamic> payload) async {
    final data = await _postJson(session, 'customer_receipt_save.php', payload,
        'CUSTOMER_RECEIPT_SAVE_FAILED');
    return Map<String, dynamic>.from(data['receipt'] as Map);
  }

  Future<Map<String, dynamic>> postCustomerPayment(
      CehSession session, Map<String, dynamic> payload) async {
    final data = await _postJson(session, 'customer_receipt_post.php', payload,
        'CUSTOMER_PAYMENT_POST_FAILED');
    return Map<String, dynamic>.from(data['receipt'] as Map);
  }

  Future<double> availableCustomerCredit(
      CehSession session, int clientId) async {
    final uri = Uri.parse('$baseUrl/customer_advance_apply.php')
        .replace(queryParameters: {'client_id': '$clientId'});
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'CUSTOMER_CREDIT_LOAD_FAILED');
    return double.tryParse('${data['available_customer_credit']}') ?? 0;
  }

  Future<Map<String, dynamic>> applyCustomerCredit(
      CehSession session, Map<String, dynamic> payload) async {
    return _postJson(session, 'customer_advance_apply.php', payload,
        'CUSTOMER_CREDIT_APPLY_FAILED');
  }

  Future<Map<String, dynamic>> taxConfiguration(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/tax_configuration.php'),
            headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'TAX_CONFIGURATION_FAILED');
    return data;
  }

  Future<void> createTaxCode(
          CehSession session, Map<String, dynamic> payload) =>
      _postJson(session, 'tax_configuration.php',
              {'action': 'CREATE', ...payload}, 'TAX_CODE_CREATE_FAILED')
          .then((_) {});

  Future<void> setTaxCodeActive(
          CehSession session, int taxCodeId, bool isActive) =>
      _postJson(
              session,
              'tax_configuration.php',
              {
                'action': 'SET_ACTIVE',
                'tax_code_id': taxCodeId,
                'is_active': isActive
              },
              'TAX_CODE_STATUS_FAILED')
          .then((_) {});

  Future<void> updateInvoiceSettings(
          CehSession session, Map<String, dynamic> payload) =>
      _postJson(session, 'invoice_settings_update.php', payload,
              'INVOICE_SETTINGS_UPDATE_FAILED')
          .then((_) {});

  Future<Map<String, dynamic>> receivablesAgeing(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/receivables_ageing.php'),
            headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'RECEIVABLES_AGEING_FAILED');
    return data;
  }

  Future<Map<String, dynamic>> accountsOverview(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/accounts_overview.php'),
            headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'ACCOUNTS_OVERVIEW_FAILED');
    return Map<String, dynamic>.from(data['overview'] as Map);
  }

  Future<Map<String, dynamic>> accountsReport(CehSession session,
      {required String endpoint,
      Map<String, String> filters = const {}}) async {
    final uri = Uri.parse('$baseUrl/$endpoint')
        .replace(queryParameters: filters.isEmpty ? null : filters);
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 40));
    final data = _decodeObject(response);
    _requireOk(response, data, 'ACCOUNTS_REPORT_FAILED');
    return data;
  }

  Future<ProductionReportFile> accountsReportPdf(CehSession session,
      {required String endpoint,
      required String filename,
      Map<String, String> filters = const {}}) async {
    final uri = Uri.parse('$baseUrl/$endpoint')
        .replace(queryParameters: filters.isEmpty ? null : filters);
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var error = 'ACCOUNTS_REPORT_PDF_FAILED';
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map && data['error'] != null) error = '${data['error']}';
      } catch (_) {}
      throw ApiException(error, statusCode: response.statusCode);
    }
    if (!(response.headers['content-type'] ?? '')
            .toLowerCase()
            .startsWith('application/pdf') ||
        response.bodyBytes.length < 5 ||
        String.fromCharCodes(response.bodyBytes.take(5)) != '%PDF-') {
      throw const ApiException('ACCOUNTS_REPORT_PDF_FAILED');
    }
    return ProductionReportFile(bytes: response.bodyBytes, filename: filename);
  }

  Future<List<CehBankAccount>> bankAccounts(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/bank_accounts.php'),
            headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'BANK_ACCOUNTS_FAILED');
    return (data['bank_accounts'] as List? ?? const [])
        .map((item) =>
            CehBankAccount.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<CehBankTransaction>> bankTransactions(
      CehSession session, int bankAccountId) async {
    final uri = Uri.parse('$baseUrl/bank_transactions.php')
        .replace(queryParameters: {'bank_account_id': '$bankAccountId'});
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'BANK_TRANSACTIONS_FAILED');
    return (data['transactions'] as List? ?? const [])
        .map((item) =>
            CehBankTransaction.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<PettyCashOverview> pettyCashOverview(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/petty_cash_summary.php'),
            headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'PETTY_CASH_FAILED');
    return PettyCashOverview.fromJson(data);
  }

  Future<void> updatePettyCashCustodian(CehSession session,
      {required int userId, required bool isActive}) async {
    await _postJson(
        session,
        'petty_cash_custodian_update.php',
        {'user_id': userId, 'is_active': isActive},
        'PETTY_CASH_CUSTODIAN_UPDATE_FAILED');
  }

  Future<List<Map<String, dynamic>>> pettyCashTransactions(
      CehSession session, int custodianUserId) async {
    final uri = Uri.parse('$baseUrl/petty_cash_transactions.php')
        .replace(queryParameters: {'custodian_user_id': '$custodianUserId'});
    final response = await http
        .get(uri, headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'PETTY_CASH_TRANSACTIONS_FAILED');
    return (data['transactions'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<int> fundPettyCash(
      CehSession session, Map<String, dynamic> payload) async {
    final data = await _postJson(
        session, 'petty_cash_fund.php', payload, 'PETTY_CASH_FUND_FAILED');
    return (data['funding']['id'] as num).toInt();
  }

  Future<CreatedPettyCashExpense> createPettyCashExpense(
      CehSession session, Map<String, dynamic> payload) async {
    final data = await _postJson(session, 'petty_cash_expense_create.php',
        payload, 'PETTY_CASH_EXPENSE_CREATE_FAILED');
    return CreatedPettyCashExpense.fromJson(
        Map<String, dynamic>.from(data['expense'] as Map));
  }

  Future<List<ExpenseSupplier>> expenseSuppliers(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/suppliers.php'), headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'SUPPLIERS_FAILED');
    return (data['suppliers'] as List? ?? const [])
        .map((item) =>
            ExpenseSupplier.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<CostCentre>> costCentres(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/cost_centres.php'),
            headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'COST_CENTRES_FAILED');
    return (data['cost_centres'] as List? ?? const [])
        .map((item) =>
            CostCentre.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<ExpenseSupplier> createExpenseSupplier(
      CehSession session, Map<String, dynamic> payload) async {
    final data = await _postJson(
        session, 'supplier_create.php', payload, 'SUPPLIER_CREATE_FAILED');
    return ExpenseSupplier.fromJson(
        Map<String, dynamic>.from(data['supplier'] as Map));
  }

  Future<CreatedPettyCashExpense> createGeneralExpense(
      CehSession session, Map<String, dynamic> payload) async {
    final data = await _postJson(session, 'general_expense_create.php', payload,
        'GENERAL_EXPENSE_CREATE_FAILED');
    return CreatedPettyCashExpense.fromJson(
        Map<String, dynamic>.from(data['expense'] as Map));
  }

  Future<void> updateGeneralExpense(
          CehSession session, int expenseId, Map<String, dynamic> payload) =>
      _postJson(
              session,
              'general_expense_update.php',
              {'expense_id': expenseId, ...payload},
              'GENERAL_EXPENSE_UPDATE_FAILED')
          .then((_) {});

  Future<void> submitGeneralExpense(CehSession session, int expenseId) =>
      _postJson(session, 'general_expense_submit.php',
              {'expense_id': expenseId}, 'GENERAL_EXPENSE_SUBMIT_FAILED')
          .then((_) {});

  Future<void> reviewGeneralExpense(CehSession session,
          {required int expenseId,
          required String action,
          String reason = ''}) =>
      _postJson(
              session,
              'general_expense_review.php',
              {'expense_id': expenseId, 'action': action, 'reason': reason},
              'GENERAL_EXPENSE_REVIEW_FAILED')
          .then((_) {});

  Future<List<Map<String, dynamic>>> generalExpenses(CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/general_expenses.php'),
            headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'GENERAL_EXPENSES_FAILED');
    return (data['expenses'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> reclassifyExpenseLine(CehSession session,
          {required String sourceType,
          required int sourceRecordId,
          required int lineId,
          required String reason,
          required Map<String, dynamic> classification}) =>
      _postJson(
              session,
              'expense_line_reclassify.php',
              {
                'source_type': sourceType,
                'source_record_id': sourceRecordId,
                'line_id': lineId,
                'reason': reason,
                ...classification
              },
              'EXPENSE_LINE_RECLASSIFY_FAILED')
          .then((_) {});

  Future<void> submitPettyCashExpense(CehSession session, int expenseId) async {
    await _postJson(session, 'petty_cash_expense_submit.php',
        {'expense_id': expenseId}, 'PETTY_CASH_EXPENSE_SUBMIT_FAILED');
  }

  Future<void> updatePettyCashExpense(
    CehSession session, {
    required int expenseId,
    required Map<String, dynamic> payload,
  }) async {
    await _postJson(
      session,
      'petty_cash_expense_update.php',
      {'expense_id': expenseId, ...payload},
      'PETTY_CASH_EXPENSE_UPDATE_FAILED',
    );
  }

  Future<void> reviewPettyCashExpense(CehSession session,
      {required int expenseId,
      required String action,
      String reason = ''}) async {
    await _postJson(
        session,
        'petty_cash_expense_review.php',
        {'expense_id': expenseId, 'action': action, 'reason': reason},
        'PETTY_CASH_EXPENSE_REVIEW_FAILED');
  }

  Future<void> deleteExpense(CehSession session,
      {required String sourceType, required int sourceRecordId}) async {
    await _postJson(
        session,
        'expense_delete.php',
        {'source_type': sourceType, 'source_record_id': sourceRecordId},
        'EXPENSE_DELETE_FAILED');
  }

  Future<void> voidExpense(CehSession session,
      {required String sourceType,
      required int sourceRecordId,
      required String reason,
      String? voidBasis}) async {
    await _postJson(
        session,
        'expense_void.php',
        {
          'source_type': sourceType,
          'source_record_id': sourceRecordId,
          'reason': reason,
          if (voidBasis != null) 'void_basis': voidBasis,
        },
        'EXPENSE_VOID_FAILED');
  }

  Future<void> reclassifyExpense(CehSession session,
      {required String sourceType,
      required int sourceRecordId,
      required String reason,
      required Map<String, dynamic> classification}) async {
    await _postJson(
        session,
        'expense_reclassify.php',
        {
          'source_type': sourceType,
          'source_record_id': sourceRecordId,
          'reason': reason,
          ...classification,
        },
        'EXPENSE_RECLASSIFY_FAILED');
  }

  Future<List<Map<String, dynamic>>> pettyCashExpenses(
      CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/petty_cash_expenses.php'),
            headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'PETTY_CASH_EXPENSES_FAILED');
    return (data['expenses'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<List<ConsolidatedExpense>> consolidatedExpenses(
      CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/expenses.php'), headers: authHeaders(session))
        .timeout(const Duration(seconds: 25));
    final data = _decodeObject(response);
    _requireOk(response, data, 'EXPENSES_FAILED');
    return (data['expenses'] as List? ?? const [])
        .map((item) => ConsolidatedExpense.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> importBankStatement(
      CehSession session, Map<String, dynamic> payload) async {
    return _postJson(session, 'bank_statement_import.php', payload,
        'BANK_STATEMENT_IMPORT_FAILED');
  }

  Future<void> reconcileBankRow(CehSession session,
      {required int statementRowId,
      required String sourceType,
      required int sourceRecordId}) async {
    await _postJson(
        session,
        'bank_reconcile.php',
        {
          'statement_row_id': statementRowId,
          'source_type': sourceType,
          'source_record_id': sourceRecordId,
        },
        'BANK_RECONCILE_FAILED');
  }

  Future<void> uploadFinancialEvidence(CehSession session,
      {required String sourceType,
      required int sourceRecordId,
      required String filename,
      required String mimeType,
      required Uint8List bytes}) async {
    await _postJson(
      session,
      'financial_evidence_upload.php',
      {
        'source_type': sourceType,
        'source_record_id': sourceRecordId,
        'filename': filename,
        'mime_type': mimeType,
        'data_base64': base64Encode(bytes),
      },
      'FINANCIAL_EVIDENCE_UPLOAD_FAILED',
    );
  }

  Future<int> uploadFinancialEvidenceRecord(CehSession session,
      {required String sourceType,
      required int sourceRecordId,
      required String filename,
      required String mimeType,
      required Uint8List bytes}) async {
    final data = await _postJson(
      session,
      'financial_evidence_upload.php',
      {
        'source_type': sourceType,
        'source_record_id': sourceRecordId,
        'filename': filename,
        'mime_type': mimeType,
        'data_base64': base64Encode(bytes),
      },
      'FINANCIAL_EVIDENCE_UPLOAD_FAILED',
    );
    return ((data['evidence'] as Map)['id'] as num).toInt();
  }

  Future<CompanyRegionalSettings> companyRegionalSettings(
      CehSession session) async {
    final response = await http
        .get(Uri.parse('$baseUrl/company_regional_settings.php'),
            headers: authHeaders(session))
        .timeout(const Duration(seconds: 20));
    final data = _decodeObject(response);
    _requireOk(response, data, 'COMPANY_SETTINGS_FAILED');
    return CompanyRegionalSettings.fromJson(
        Map<String, dynamic>.from(data['regional_settings'] as Map));
  }

  Future<CompanyRegionalSettings> updateCompanyRegionalSettings(
    CehSession session, {
    required String timeZone,
    required String dateFormat,
    required String timeFormat,
    required String baseCurrency,
    String? changeReason,
  }) async {
    final data = await _postJson(
      session,
      'company_regional_settings_update.php',
      {
        'time_zone': timeZone,
        'date_format': dateFormat,
        'time_format': timeFormat,
        'base_currency': baseCurrency,
        if (changeReason?.trim().isNotEmpty == true)
          'change_reason': changeReason!.trim(),
      },
      'COMPANY_SETTINGS_UPDATE_FAILED',
    );
    return CompanyRegionalSettings.fromJson(
        Map<String, dynamic>.from(data['regional_settings'] as Map));
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
    return decodeApiObjectResponse(response);
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
