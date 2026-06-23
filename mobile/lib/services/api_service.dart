import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'storage_service.dart';
import '../config/environment.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _storage = StorageService();

  String get _base => '${EnvironmentConfig.apiBaseUrl}/api/v1';

  Map<String, String> _headers({bool multipart = false}) {
    final token = _storage.accessToken;
    return {
      if (!multipart) HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.acceptHeader: 'application/json',
      if (token != null) HttpHeaders.authorizationHeader: 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _handleResponse(http.Response res) async {
    if (res.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (!refreshed) throw ApiException(401, 'Unauthorized');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, body['detail']?.toString() ?? 'Error');
    }
    return body;
  }

  Future<bool> _tryRefresh() async {
    final refresh = _storage.refreshToken;
    if (refresh == null) return false;
    try {
      final res = await http.post(
        Uri.parse('$_base/auth/refresh'),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        body: jsonEncode({'refresh_token': refresh}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        await _storage.setString('access_token', data['access_token'] as String);
        await _storage.setString('refresh_token', data['refresh_token'] as String);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$_base$path'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _handleResponse(res);
  }

  Future<dynamic> get(String path, {Map<String, String>? params}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers());
    if (res.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (!refreshed) throw ApiException(401, 'Unauthorized');
    }
    final body = jsonDecode(res.body);
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, (body as Map)['detail']?.toString() ?? 'Error');
    }
    return body;
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    final res = await http.put(
      Uri.parse('$_base$path'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _handleResponse(res);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final res = await http.delete(Uri.parse('$_base$path'), headers: _headers());
    return _handleResponse(res);
  }

  Future<Map<String, dynamic>> uploadFile(String path, File file, String fieldName) async {
    final token = _storage.accessToken;
    final req = http.MultipartRequest('POST', Uri.parse('$_base$path'));
    if (token != null) req.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    req.files.add(await http.MultipartFile.fromPath(fieldName, file.path));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    return _handleResponse(res);
  }
}
