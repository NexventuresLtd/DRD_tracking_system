import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/user_model.dart';
import 'storage_service.dart';

class AuthService {
  final StorageService _storage = StorageService();

  /// Step 1: submit credentials → returns either
  ///   {'success': true, 'user': UserModel}           (legacy / no OTP)
  ///   {'otp_required': true, 'session_id': '...', 'email_hint': '...'}
  ///   {'success': false, 'message': '...'}
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // OTP flow: server returns {status: "otp_required", session_id, email_hint}
        if (data['status'] == 'otp_required') {
          return {
            'otp_required': true,
            'session_id': data['session_id'] as String,
            'email_hint': data['email_hint'] as String? ?? '',
          };
        }

        // Legacy / direct-token response (shouldn't happen with current backend)
        await _storage.saveToken(data['access_token']);
        await _storage.saveRefreshToken(data['refresh_token']);
        await _storage.saveUserData(data['user'] as Map<String, dynamic>);
        return {
          'success': true,
          'user': UserModel.fromJson(data['user'] as Map<String, dynamic>),
          'token': data['access_token'],
        };
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        return {'success': false, 'message': error['detail'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Step 2: submit OTP (or bypass "555555") → returns tokens
  Future<Map<String, dynamic>> verifyOtp(String sessionId, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'otp': otp}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _storage.saveToken(data['access_token']);
        await _storage.saveRefreshToken(data['refresh_token']);
        await _storage.saveUserData(data['user'] as Map<String, dynamic>);
        return {
          'success': true,
          'user': UserModel.fromJson(data['user'] as Map<String, dynamic>),
          'token': data['access_token'],
        };
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        return {'success': false, 'message': error['detail'] ?? 'Verification failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<bool> logout() async {
    await _storage.clearAll();
    return true;
  }

  Future<String?> getToken() async {
    return await _storage.getToken();
  }

  Future<UserModel?> getCurrentUser() async {
    final userData = await _storage.getUserData();
    if (userData != null) {
      return UserModel.fromJson(userData);
    }
    return null;
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Fetch latest user profile from server (including team info) and save to storage.
  Future<UserModel?> refreshUserProfile() async {
    final token = await getToken();
    if (token == null) return null;
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/auth/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await _storage.saveUserData(data);
      return UserModel.fromJson(data);
    }
    return null;
  }
}