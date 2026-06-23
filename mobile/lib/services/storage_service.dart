import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String? getString(String key) => _prefs.getString(key);
  Future<bool> setString(String key, String value) => _prefs.setString(key, value);
  Future<bool> remove(String key) => _prefs.remove(key);
  Future<bool> clear() => _prefs.clear();

  String? get accessToken => getString('access_token');
  String? get refreshToken => getString('refresh_token');
  String? get userJson => getString('user_json');

  Future<void> saveAuth({
    required String accessToken,
    required String refreshToken,
    required String userJson,
  }) async {
    await setString('access_token', accessToken);
    await setString('refresh_token', refreshToken);
    await setString('user_json', userJson);
  }

  Future<void> clearAuth() async {
    await remove('access_token');
    await remove('refresh_token');
    await remove('user_json');
  }
}
