import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  UserModel? _user;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _errorMessage;
  String? _pendingSessionId;
  String? _pendingEmailHint;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get errorMessage => _errorMessage;
  String? get pendingSessionId => _pendingSessionId;
  String? get pendingEmailHint => _pendingEmailHint;

  Future<void> checkAuthStatus() async {
    final isLoggedIn = await _authService.isLoggedIn();
    if (isLoggedIn) {
      _user = await _authService.getCurrentUser();
      _isAuthenticated = true;
      notifyListeners();
      // Refresh profile from server to get latest team info
      _authService
          .refreshUserProfile()
          .then((fresh) {
            if (fresh != null) {
              _user = fresh;
              notifyListeners();
            }
          })
          .catchError((_) {});
    } else {
      notifyListeners();
    }
  }

  Future<bool?> login(String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.login(username, password);

    _isLoading = false;

    if (result['otp_required'] == true) {
      _pendingSessionId = result['session_id'] as String?;
      _pendingEmailHint = result['email_hint'] as String?;
      notifyListeners();
      return null;
    }

    if (result['success'] == true) {
      _user = result['user'];
      _isAuthenticated = true;
      _pendingSessionId = null;
      _pendingEmailHint = null;
      notifyListeners();
      return true;
    } else {
      _errorMessage = result['message'];
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyOtp(String otp) async {
    final sessionId = _pendingSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      _errorMessage = 'OTP session expired. Please log in again.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.verifyOtp(sessionId, otp);

    _isLoading = false;
    if (result['success'] == true) {
      _user = result['user'];
      _isAuthenticated = true;
      clearOtpState();
      notifyListeners();
      return true;
    }

    _errorMessage = result['message'];
    notifyListeners();
    return false;
  }

  /// Refresh user info from the server (/auth/me) and update in-memory user.
  Future<void> loadUserInfo() async {
    try {
      final fresh = await _authService.refreshUserProfile();
      if (fresh != null) {
        _user = fresh;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> logout() async {
    await _authService.logout();
    _user = null;
    _isAuthenticated = false;
    clearOtpState();
    notifyListeners();
  }

  void clearOtpState() {
    _pendingSessionId = null;
    _pendingEmailHint = null;
  }

  String getHomeRoute() {
    if (_user == null) return '/login';

    switch (_user!.role) {
      case 'super_admin':
      case 'admin':
      case 'commander':
        return '/commander/home';
      case 'operator':
        return '/operator/home';
      case 'field_unit':
        return '/field/tactical';
      case 'viewer':
      default:
        return '/viewer/home';
    }
  }
}
