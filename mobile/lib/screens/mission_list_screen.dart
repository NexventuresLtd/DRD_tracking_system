import 'package:flutter/material.dart';
import '../services/api_service.dart';

class MissionData {
  final String id;
  final String name;
  final String status;
  final String? areaOfOperations;
  final int objectiveCount;
  final int completedCount;

  const MissionData({
    required this.id,
    required this.name,
    required this.status,
    this.areaOfOperations,
    required this.objectiveCount,
    required this.completedCount,
  });

  factory MissionData.fromJson(Map<String, dynamic> j) => MissionData(
        id: j['id'] as String,
        name: j['name'] as String,
        status: j['status'] as String,
        areaOfOperations: j['area_of_operations'] as String?,
        objectiveCount: (j['objectives'] as List?)?.length ?? 0,
        completedCount: (j['objectives'] as List?)?.where((o) => (o as Map)['is_completed'] == true).length ?? 0,
      );
}

const _statusColors = {
  'draft':     Color(0xFF6B7280),
  'planned':   Color(0xFF3B82F6),
  'active':    Color(0xFF22C55E),
  'suspended': Color(0xFFF59E0B),
  'completed': Color(0xFF8B5CF6),
  'archived':  Color(0xFF374151),
};

class MissionListScreen extends StatefulWidget {
  const MissionListScreen({super.key});
  @override
  State<MissionListScreen> createState() => _MissionListScreenState();
}

class _MissionListScreenState extends State<MissionListScreen> {
  List<MissionData> _missions = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService().get('/missions') as List<dynamic>;
      if (!mounted) return;
      setState(() => _missions = data.map((e) => MissionData.fromJson(e as Map<String, dynamic>)).toList());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<MissionData> get _filtered =>
      _filter == 'all' ? _missions : _missions.where((m) => m.status == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Missions', style: TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF9CA3AF)),
            onPressed: _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: ['all', 'active', 'planned', 'draft', 'completed'].map((s) {
                final selected = _filter == s;
                return GestureDetector(
                  onTap: () => setState(() => _filter = s),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF1D4ED8) : const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      s == 'all' ? 'All (${_missions.length})' : '${s[0].toUpperCase()}${s.substring(1)} (${_missions.where((m) => m.status == s).length})',
                      style: TextStyle(
                        color: selected ? Colors.white : const Color(0xFF9CA3AF),
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : _filtered.isEmpty
              ? const Center(child: Text('No missions', style: TextStyle(color: Color(0xFF6B7280))))
              : RefreshIndicator(
                  color: const Color(0xFF2563EB),
                  backgroundColor: const Color(0xFF1F2937),
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final m = _filtered[i];
                      final color = _statusColors[m.status] ?? const Color(0xFF6B7280);
                      final progress = m.objectiveCount > 0 ? m.completedCount / m.objectiveCount : 0.0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF1F2937)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(m.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: color.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    m.status[0].toUpperCase() + m.status.substring(1),
                                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            if (m.areaOfOperations != null) ...[
                              const SizedBox(height: 4),
                              Text(m.areaOfOperations!, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                            ],
                            if (m.objectiveCount > 0) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        backgroundColor: const Color(0xFF1F2937),
                                        color: color,
                                        minHeight: 4,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${m.completedCount}/${m.objectiveCount}',
                                    style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
