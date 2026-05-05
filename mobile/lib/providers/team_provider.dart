import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TeamProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  
  List<Map<String, dynamic>> _teams = [];
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> get teams => _teams;
  List<Map<String, dynamic>> get members => _members;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchTeams() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get('/teams');
      if (response != null) {
        _teams = List<Map<String, dynamic>>.from(response);
      }
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchTeamMembers(String teamId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get('/teams/$teamId');
      if (response != null) {
        _members = List<Map<String, dynamic>>.from(response['members'] ?? []);
      }
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Map<String, dynamic>? getTeamById(String teamId) {
    try {
      return _teams.firstWhere((team) => team['id'] == teamId);
    } catch (_) {
      return null;
    }
  }

  String getTeamColor(String? teamName) {
    const colors = {
      'Team Alpha': '#22C55E',
      'Team Bravo': '#F59E0B',
      'Team Charlie': '#EF4444',
      'Team Delta': '#8B5CF6',
      'Team Echo': '#06B6D4',
    };
    return colors[teamName] ?? '#3B82F6';
  }
}