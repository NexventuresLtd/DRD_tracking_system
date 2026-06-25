import 'package:flutter/material.dart';
import '../services/api_service.dart';

class FacilityData {
  final String id;
  final String name;
  final String facilityType;
  final String? description;
  final String? address;
  final String? region;
  final double? latitude;
  final double? longitude;
  final String status;
  final bool isPublished;

  const FacilityData({
    required this.id,
    required this.name,
    required this.facilityType,
    this.description,
    this.address,
    this.region,
    this.latitude,
    this.longitude,
    required this.status,
    required this.isPublished,
  });

  factory FacilityData.fromJson(Map<String, dynamic> j) => FacilityData(
        id: j['id'] as String,
        name: j['name'] as String,
        facilityType: j['facility_type'] as String? ?? 'base',
        description: j['description'] as String?,
        address: j['address'] as String?,
        region: j['region'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        status: j['status'] as String? ?? 'active',
        isPublished: j['is_published'] as bool? ?? false,
      );
}

const _typeIcons = {
  'base':          Icons.home_work_outlined,
  'hospital':      Icons.local_hospital_outlined,
  'checkpoint':    Icons.flag_outlined,
  'supply_depot':  Icons.inventory_2_outlined,
  'command_post':  Icons.account_balance_outlined,
  'observation':   Icons.visibility_outlined,
  'prison':        Icons.lock_outlined,
  'airfield':      Icons.flight_outlined,
  'port':          Icons.anchor_outlined,
};

const _typeColors = {
  'base':          Color(0xFF3B82F6),
  'hospital':      Color(0xFFEC4899),
  'checkpoint':    Color(0xFF22C55E),
  'supply_depot':  Color(0xFF8B5CF6),
  'command_post':  Color(0xFFF59E0B),
  'observation':   Color(0xFF0EA5E9),
  'prison':        Color(0xFFDC2626),
  'airfield':      Color(0xFF14B8A6),
  'port':          Color(0xFF6366F1),
};

class FacilitiesScreen extends StatefulWidget {
  const FacilitiesScreen({super.key});

  @override
  State<FacilitiesScreen> createState() => _FacilitiesScreenState();
}

class _FacilitiesScreenState extends State<FacilitiesScreen> {
  List<FacilityData> _facilities = [];
  bool _loading = true;
  String? _typeFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService().get('/posts?published_only=true') as List<dynamic>;
      if (!mounted) return;
      setState(() => _facilities = data
          .cast<Map<String, dynamic>>()
          .map(FacilityData.fromJson)
          .toList());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<FacilityData> get _filtered =>
      _typeFilter == null ? _facilities : _facilities.where((f) => f.facilityType == _typeFilter).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            const Text('Facilities', style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(width: 8),
            if (!_loading)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF1F2937), borderRadius: BorderRadius.circular(10)),
                child: Text('${_facilities.length}', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
              ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF9CA3AF)), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)))
          : _buildList(),
    );
  }

  Widget _buildList() {
    final types = _facilities.map((f) => f.facilityType).toSet().toList();
    return Column(
      children: [
        // Type filter chips
        if (types.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _FilterChip(label: 'All', selected: _typeFilter == null, onTap: () => setState(() => _typeFilter = null)),
                ...types.map((t) => _FilterChip(
                  label: _typeLabel(t),
                  selected: _typeFilter == t,
                  color: _typeColors[t],
                  onTap: () => setState(() => _typeFilter = _typeFilter == t ? null : t),
                )),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            color: const Color(0xFF22C55E),
            backgroundColor: const Color(0xFF0F172A),
            onRefresh: _load,
            child: _filtered.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 200),
                      Center(child: Text('No facilities available', style: TextStyle(color: Color(0xFF6B7280)))),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) => _FacilityTile(facility: _filtered[i]),
                  ),
          ),
        ),
      ],
    );
  }


  String _typeLabel(String type) =>
      type.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

// ── Facility list tile ────────────────────────────────────────────────────────

class _FacilityTile extends StatelessWidget {
  final FacilityData facility;
  const _FacilityTile({required this.facility});

  @override
  Widget build(BuildContext context) {
    final color = _typeColors[facility.facilityType] ?? const Color(0xFF3B82F6);
    final icon = _typeIcons[facility.facilityType] ?? Icons.place;
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF0F172A),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _FacilitySheet(facility: facility),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1F2937)),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.3))),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(facility.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(_typeLabel(facility.facilityType), style: TextStyle(color: color, fontSize: 11)),
                  if (facility.region != null)
                    Text(facility.region!, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF374151), size: 20),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String type) =>
      type.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

// ── Facility detail sheet ─────────────────────────────────────────────────────

class _FacilitySheet extends StatelessWidget {
  final FacilityData facility;
  const _FacilitySheet({required this.facility});

  @override
  Widget build(BuildContext context) {
    final color = _typeColors[facility.facilityType] ?? const Color(0xFF3B82F6);
    final icon = _typeIcons[facility.facilityType] ?? Icons.place;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFF374151), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(facility.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(_typeLabel(facility.facilityType), style: TextStyle(color: color, fontSize: 12)),
                  ],
                ),
              ),
              _StatusBadge(status: facility.status),
            ],
          ),
          const SizedBox(height: 16),
          if (facility.description != null && facility.description!.isNotEmpty) ...[
            const Text('Description', style: TextStyle(color: Color(0xFF6B7280), fontSize: 11, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(facility.description!, style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13, height: 1.5)),
            const SizedBox(height: 12),
          ],
          if (facility.address != null) _DetailRow(label: 'Address', value: facility.address!),
          if (facility.region != null) _DetailRow(label: 'Region', value: facility.region!),
          if (facility.latitude != null && facility.longitude != null)
            _DetailRow(
              label: 'Coordinates',
              value: '${facility.latitude!.toStringAsFixed(5)}, ${facility.longitude!.toStringAsFixed(5)}',
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _typeLabel(String type) =>
      type.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text('$label:', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 12))),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == 'active' ? const Color(0xFF22C55E) : const Color(0xFF6B7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF22C55E);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.2) : const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? c : const Color(0xFF374151)),
        ),
        child: Text(label, style: TextStyle(color: selected ? c : const Color(0xFF9CA3AF), fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}
