import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import 'storage_service.dart';

class ApiService {
  final StorageService _storage = StorageService();
  Future<bool>? _refreshFuture;

  /// Builds a URI, ensuring the path has a trailing slash before any query
  /// string — this matches FastAPI's default routing conventions and avoids
  /// 307 redirects that lose the POST body.
  Uri _uri(String endpoint) {
    final qi = endpoint.indexOf('?');
    final path = qi >= 0 ? endpoint.substring(0, qi) : endpoint;
    final query = qi >= 0 ? endpoint.substring(qi) : '';
    final normalised = path.endsWith('/') ? path : '$path/';
    return Uri.parse('${AppConstants.baseUrl}$normalised$query');
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _storage.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> get(String endpoint) async {
    try {
      final response = await http.get(
        _uri(endpoint),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      if (response.statusCode == 401) {
        await _refreshToken();
        return get(endpoint);
      }
      throw Exception('Failed to load data: ${response.statusCode}');
    } catch (e) {
      debugPrint('GET Error: $e');
      return null;
    }
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        _uri(endpoint),
        headers: await _getHeaders(),
        body: jsonEncode(data),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return response.body.isNotEmpty ? jsonDecode(response.body) : {};
      }
      if (response.statusCode == 401) {
        await _refreshToken();
        return post(endpoint, data);
      }
      throw Exception(
        'Failed to create: ${response.statusCode} — ${response.body}',
      );
    } catch (e) {
      debugPrint('POST Error: $e');
      return null;
    }
  }

  Future<dynamic> put(String endpoint, [Map<String, dynamic>? data]) async {
    try {
      final response = await http.put(
        _uri(endpoint),
        headers: await _getHeaders(),
        body: data != null ? jsonEncode(data) : null,
      );
      if (response.statusCode == 200) {
        return response.body.isNotEmpty ? jsonDecode(response.body) : {};
      }
      if (response.statusCode == 401) {
        await _refreshToken();
        return put(endpoint, data);
      }
      throw Exception('Failed to update: ${response.statusCode}');
    } catch (e) {
      debugPrint('PUT Error: $e');
      return null;
    }
  }

  Future<dynamic> delete(String endpoint) async {
    try {
      final response = await http.delete(
        _uri(endpoint),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return response.body.isNotEmpty ? jsonDecode(response.body) : {};
      }
      if (response.statusCode == 401) {
        await _refreshToken();
        return delete(endpoint);
      }
      throw Exception('Failed to delete: ${response.statusCode}');
    } catch (e) {
      debugPrint('DELETE Error: $e');
      return null;
    }
  }

  Future<dynamic> updateRoute(String routeId, Map<String, dynamic> data) =>
      put('/routes/$routeId', data);

  Future<dynamic> startRouteFollow(Map<String, dynamic> data) =>
      post('/route-follow-sessions/start', data);

  Future<dynamic> stopRouteFollow(
    String sessionId, [
    Map<String, dynamic>? data,
  ]) => post(
    '/route-follow-sessions/$sessionId/stop',
    data ?? <String, dynamic>{},
  );

  Future<dynamic> completeRouteFollow(
    String sessionId, [
    Map<String, dynamic>? data,
  ]) => post(
    '/route-follow-sessions/$sessionId/complete',
    data ?? <String, dynamic>{},
  );

  Future<dynamic> getMyRouteFollowSession() => get('/route-follow-sessions/me');

  Future<dynamic> listRouteFollowSessions([
    Map<String, dynamic>? params,
  ]) => get(
    '/route-follow-sessions${params == null ? '' : '?${Uri(queryParameters: params.map((k, v) => MapEntry(k, v.toString()))).query}'}',
  );

  Future<void> _refreshToken() async {
    // Serialize concurrent refresh attempts so only one network call is made.
    if (_refreshFuture != null) {
      await _refreshFuture;
      return;
    }

    final completer = Completer<bool>();
    _refreshFuture = completer.future;
    try {
      final refreshToken = await _storage.getRefreshToken();
      if (refreshToken == null) {
        completer.complete(false);
        return;
      }

      final response = await http.post(
        _uri('/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _storage.saveToken(data['access_token']);
        if (data['refresh_token'] != null) {
          await _storage.saveRefreshToken(data['refresh_token']);
        }
        completer.complete(true);
        return;
      }
      completer.complete(false);
    } catch (e) {
      debugPrint('Refresh Token Error: $e');
      completer.complete(false);
    } finally {
      _refreshFuture = null;
    }
  }
}
