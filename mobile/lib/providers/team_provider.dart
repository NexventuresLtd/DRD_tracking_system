import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class TeamData {
  final String id;
  final String name;
  final String? description;
  final String color;
  final int memberCount;

  const TeamData({
    required this.id,
    required this.name,
    this.description,
    required this.color,
    required this.memberCount,
  });

  factory TeamData.fromJson(Map<String, dynamic> j) => TeamData(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        color: j['color'] as String? ?? '#3b82f6',
        memberCount: j['member_count'] as int? ?? 0,
      );
}

class TeamProvider extends ChangeNotifier {
  List<TeamData> _teams = [];
  bool _loading = false;

  List<TeamData> get teams => _teams;
  bool get loading => _loading;

  final _api = ApiService();

  Future<void> loadTeams() async {
    _loading = true;
    notifyListeners();
    try {
      final data = await _api.get('/teams?mine=true') as List<dynamic>;
      _teams = data.map((e) => TeamData.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }
}
