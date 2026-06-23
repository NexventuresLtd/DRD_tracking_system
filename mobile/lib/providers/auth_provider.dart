import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  String? _error;

  AuthStatus get status => _status;
  User? get user => _user;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  final _api = ApiService();
  final _storage = StorageService();

  AuthProvider() {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final userJson = _storage.userJson;
    final token = _storage.accessToken;
    if (userJson != null && token != null) {
      try {
        _user = User.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
        _status = AuthStatus.authenticated;
        notifyListeners();
        await _refreshMe();
      } catch (_) {
        await logout();
      }
    } else {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  Future<void> _refreshMe() async {
    try {
      final data = await _api.get('/auth/me') as Map<String, dynamic>;
      _user = User.fromJson(data);
      await _storage.setString('user_json', jsonEncode(_user!.toJson()));
      notifyListeners();
    } catch (_) {}
  }

  // Returns otp_session on success, null on failure
  Future<Map<String, String>?> initiateLogin(String email, String password) async {
    _error = null;
    notifyListeners();
    try {
      final data = await _api.post('/auth/login', {'email': email, 'password': password});
      return {
        'otp_session': data['otp_session'] as String,
        'email_hint': data['email_hint'] as String,
      };
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    }
  }

  Future<bool> verifyOtp(String otpSession, String otpCode) async {
    _error = null;
    notifyListeners();
    try {
      final data = await _api.post('/auth/verify-otp', {
        'otp_session': otpSession,
        'otp_code': otpCode,
      });
      _user = User.fromJson(data['user'] as Map<String, dynamic>);
      await _storage.saveAuth(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
        userJson: jsonEncode(_user!.toJson()),
      );
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> resendOtp(String otpSession) async {
    try {
      await _api.post('/auth/resend-otp', {'otp_session': otpSession});
    } catch (_) {}
  }

  Future<bool> login(String email, String password) async {
    _error = null;
    notifyListeners();
    try {
      final data = await _api.post('/auth/login', {'email': email, 'password': password});
      _user = User.fromJson(data['user'] as Map<String, dynamic>);
      await _storage.saveAuth(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
        userJson: jsonEncode(_user!.toJson()),
      );
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> enrollWithVoucher(String code) async {
    _error = null;
    try {
      final data = await _api.post('/auth/enroll/voucher', {'code': code});
      _user = User.fromJson(data['user'] as Map<String, dynamic>);
      await _storage.saveAuth(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
        userJson: jsonEncode(_user!.toJson()),
      );
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> enrollWithQR(String code) async => enrollWithVoucher(code);

  Future<void> updateUser(User updated) async {
    _user = updated;
    await _storage.setString('user_json', jsonEncode(updated.toJson()));
    notifyListeners();
  }

  Future<void> logout() async {
    final refresh = _storage.refreshToken;
    if (refresh != null) {
      _api.post('/auth/logout', {'refresh_token': refresh}).catchError((_) => <String, dynamic>{});
    }
    await _storage.clearAuth();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
