import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

class BackendApi {
  BackendApi._();
  static final BackendApi instance = BackendApi._();

  static const _fallbackUrl = 'http://10.0.2.2:8000';
  static String _currentUrl = _fallbackUrl;

  static String get baseUrl => _currentUrl;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('api_base_url');
    _currentUrl = (savedUrl != null && savedUrl.trim().isNotEmpty)
        ? savedUrl.trim()
        : const String.fromEnvironment('API_BASE_URL',
            defaultValue: _fallbackUrl);
  }

  Future<void> setBaseUrl(String newUrl) async {
    final normalized = newUrl.trim();
    _currentUrl = normalized.isEmpty ? _fallbackUrl : normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', _currentUrl);
  }

  String? _token;
  void Function()? onUnauthorized;
  String? get token => _token;
  bool get isAuthenticated => _token != null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<dynamic> _request(String method, String path,
      {Map<String, Object?>? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final request = switch (method) {
      'GET' => http.get(uri, headers: _headers),
      'POST' => http.post(uri, headers: _headers, body: jsonEncode(body)),
      'PATCH' => http.patch(uri, headers: _headers, body: jsonEncode(body)),
      'DELETE' => http.delete(uri, headers: _headers),
      _ =>
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method'),
    };

    late final http.Response response;
    try {
      response = await request.timeout(const Duration(seconds: 30));
    } on http.ClientException {
      throw ApiException(
          'Cannot reach the server at $baseUrl. Check if the backend is running and your IP is correct.');
    } on TimeoutException {
      throw const ApiException(
          'The server did not respond. Check your connection.');
    }

    dynamic data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      data = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 && _token != null) {
        _token = null;
        onUnauthorized?.call();
        throw const ApiException('Session expired. Please sign in again.');
      }
      throw ApiException(
          _errorMessage(data) ?? 'Request failed (${response.statusCode}).');
    }
    return data;
  }

  static String? _errorMessage(dynamic data) {
    if (data is! Map<String, dynamic>) return null;
    final detail = data['detail'];
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map<String, dynamic>) {
        final loc = first['loc'];
        final field = loc is List && loc.isNotEmpty ? loc.last.toString() : '';
        return field.isEmpty ? '${first['msg']}' : '$field: ${first['msg']}';
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> register(String email, String password) async {
    final data = await _request('POST', '/auth/register',
        body: {'email': email, 'password': password});
    _token = data['access_token'] as String;
    return data['user'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = await _request('POST', '/auth/login',
        body: {'email': email, 'password': password});
    _token = data['access_token'] as String;
    return data['user'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifyReceipt(
      {required String bank,
      String? reference,
      double? amount,
      String? accountNumber,
      String? phoneNumber,
      String? qrData}) async {
    return await _request('POST', '/transactions/verify', body: {
      'bank': bank,
      if (reference != null) 'reference': reference,
      if (amount != null) 'amount': amount,
      if (accountNumber != null) 'account_number': accountNumber,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (qrData != null) 'qr_data': qrData,
    }) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> history({bool admin = false}) async {
    final data =
        await _request('GET', admin ? '/admin/alerts' : '/transactions')
            as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> updateAlert(int id, String status) async {
    await _request('PATCH', '/admin/alerts/$id', body: {'status': status});
  }

  Future<List<Map<String, dynamic>>> communityReports(
      {bool admin = false}) async {
    final path = admin ? '/admin/community/reports' : '/community/reports';
    final data = await _request('GET', path) as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> myCommunityReports() async {
    final data =
        await _request('GET', '/community/my-reports') as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> communityReportTrends({int days = 30}) async {
    return await _request(
      'GET',
      '/admin/community/report-trends?days=$days',
    ) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitCommunityReport({
    required String category,
    required String title,
    required String description,
    String? indicator,
    String? provider,
  }) async {
    return await _request('POST', '/community/reports', body: {
      'category': category,
      'title': title,
      'description': description,
      if (indicator != null && indicator.isNotEmpty) 'indicator': indicator,
      if (provider != null && provider.isNotEmpty) 'provider': provider,
    }) as Map<String, dynamic>;
  }

  Future<void> updateCommunityReport(int id, String status) async {
    await _request(
      'PATCH',
      '/admin/community/reports/$id',
      body: {'status': status},
    );
  }

  Future<Map<String, dynamic>> reconciliation() async {
    return await _request('GET', '/reconciliation') as Map<String, dynamic>;
  }

  Future<void> addExpectedPayment({
    required String provider,
    required double expectedAmount,
    String? reference,
    String? description,
  }) async {
    await _request('POST', '/reconciliation/expected', body: {
      'provider': provider,
      'expected_amount': expectedAmount,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
      if (description != null && description.isNotEmpty)
        'description': description,
    });
  }

  Future<void> deleteExpectedPayment(int id) async {
    await _request('DELETE', '/reconciliation/expected/$id');
  }

  Future<List<Map<String, dynamic>>> chekiBanks() async {
    final data = await _request('GET', '/cheki/banks') as Map<String, dynamic>;
    return (data['banks'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> scoreTransfer(
      {required double amount,
      required int hour,
      required int accountAgeDays,
      required int transactions24h,
      required bool newRecipient,
      required bool simChanged}) async {
    return await _request('POST', '/transactions/score', body: {
      'amount': amount,
      'hour': hour,
      'account_age_days': accountAgeDays,
      'transactions_24h': transactions24h,
      'new_recipient': newRecipient,
      'sim_changed': simChanged,
    }) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listUsers() async {
    final data = await _request('GET', '/admin/users') as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listEducation() async {
    final data = await _request('GET', '/education') as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> addEducation({
    required String title,
    required String description,
    String category = 'general',
    String? videoUrl,
    File? videoFile,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/education');
    final request = http.MultipartRequest('POST', uri);

    request.headers.addAll({
      if (_token != null) 'Authorization': 'Bearer $_token',
    });

    request.fields['title'] = title;
    request.fields['description'] = description;
    request.fields['category'] = category;
    if (videoUrl != null) request.fields['video_url'] = videoUrl;

    if (videoFile != null) {
      final multipartFile =
          await http.MultipartFile.fromPath('video_file', videoFile.path);
      request.files.add(multipartFile);
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    dynamic data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      data = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
          _errorMessage(data) ?? 'Upload failed (${response.statusCode}).');
    }
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> addEducationPost({
    required String postType,
    required String title,
    required String description,
    required String category,
    File? imageFile,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/education/posts');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll({
      if (_token != null) 'Authorization': '******',
    });
    request.fields['post_type'] = postType;
    request.fields['title'] = title;
    request.fields['description'] = description;
    request.fields['category'] = category;
    if (imageFile != null) {
      request.files.add(
        await http.MultipartFile.fromPath('image_file', imageFile.path),
      );
    }

    final streamedResponse = await request.send().timeout(
          const Duration(seconds: 30),
        );
    final response = await http.Response.fromStream(streamedResponse);
    dynamic data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      data = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        _errorMessage(data) ?? 'Publish failed (${response.statusCode}).',
      );
    }
    return data as Map<String, dynamic>;
  }

  Future<void> deleteEducation(int id) async {
    await _request('DELETE', '/admin/education/$id');
  }

  Future<String> aiChat(String message) async {
    final data = await _request('POST', '/ai/chat', body: {'message': message});
    return data['response'] as String;
  }

  void logout() => _token = null;
}
