import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config/constants.dart';

class StorageService {
  static late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Token Management
  Future<void> saveToken(String token) async {
    await _prefs.setString(AppConstants.tokenKey, token);
  }

  Future<String?> getToken() async {
    return _prefs.getString(AppConstants.tokenKey);
  }

  Future<void> saveRefreshToken(String token) async {
    await _prefs.setString(AppConstants.refreshTokenKey, token);
  }

  Future<String?> getRefreshToken() async {
    return _prefs.getString(AppConstants.refreshTokenKey);
  }

  // User Data
  Future<void> saveUserData(Map<String, dynamic> user) async {
    await _prefs.setString(AppConstants.userKey, jsonEncode(user));
  }

  Future<Map<String, dynamic>?> getUserData() async {
    final data = _prefs.getString(AppConstants.userKey);
    if (data != null) {
      return jsonDecode(data);
    }
    return null;
  }

  // Clear All
  Future<void> clearAll() async {
    await _prefs.clear();
  }
}