import 'dart:convert';
import '../gge_client.dart';
import '../models.dart';

class StatsService {
  final GgeClient conn;
  StatsService(this.conn);

  Future<List<CastleStats>> getAllCastleStats({
    Map<int, UnitCatalogEntry>? catalog,
  }) async {
    // 1. Get castle names from gcl
    final names = <int, String>{};
    try {
      final gclResp =
          await conn.sendXtAndWait('gcl', '{}', responseCmd: 'gcl');
      if (gclResp.resultCode == 0 && gclResp.payload != null) {
        final gclData =
            jsonDecode(gclResp.payload!) as Map<String, dynamic>;
        for (final k in (gclData['C'] as List? ?? [])) {
          for (final areaObj in (k['AI'] as List? ?? [])) {
            final ai = areaObj['AI'] as List?;
            if (ai == null || ai.length < 11) continue;
            final aid = _asInt(ai[3]);
            final name = ai[10] as String? ?? '';
            if (aid > 0 && name.isNotEmpty) names[aid] = name;
          }
        }
      }
    } catch (_) {}

    // 2. Get detailed stats from dcl
    final resp =
        await conn.sendXtAndWait('dcl', '{"CD":1}', responseCmd: 'dcl');
    if (resp.resultCode != 0) {
      throw Exception('dcl: ${errorName(resp.resultCode)}');
    }
    final data = jsonDecode(resp.payload!) as Map<String, dynamic>;

    final pid = _asIntOrNull(data['PID']);
    if (pid != null && pid > 0) conn.cachedPlayerId = pid;

    final out = <CastleStats>[];
    for (final k in (data['C'] as List? ?? [])) {
      final kid = _asInt(k['KID']);
      for (final a in (k['AI'] as List? ?? [])) {
        final stats = _parseArea(a, kid, catalog, names);
        if (stats != null) out.add(stats);
      }
    }

    // ═══ Cache for notifications details ═══
    final cacheMap = <int, CastleStats>{};
    for (final s in out) cacheMap[s.areaId] = s;
    conn.cachedStatsByArea = cacheMap;

    return out;
  }

  CastleStats? _parseArea(
    dynamic a,
    int kid,
    Map<int, UnitCatalogEntry>? catalog,
    Map<int, String> names,
  ) {
    if (a is! Map) return null;
    final aid = _asInt(a['AID']);
    if (aid <= 0) return null;

    final gpa = a['gpa'] as Map<String, dynamic>?;

    List<CastleUnit> units(List? raw) {
      final out = <CastleUnit>[];
      for (final u in (raw ?? const [])) {
        if (u is! List || u.length < 2) continue;
        final id = _asInt(u[0]);
        final amt = _asInt(u[1]);
        if (id > 0 && amt > 0) {
          out.add(CastleUnit(wodId: id, amount: amt, info: catalog?[id]));
        }
      }
      return out;
    }

    return CastleStats(
      areaId: aid,
      kingdomId: kid,
      name: names[aid],
      wood: _asInt(a['W']),
      stone: _asInt(a['S']),
      food: _asInt(a['F']),
      coal: _asInt(a['C']),
      oil: _asInt(a['O']),
      glass: _asInt(a['G']),
      iron: _asInt(a['I']),
      honey: _asInt(a['HONEY']),
      mead: _asInt(a['MEAD']),
      aqua: _asInt(a['A']),
      // ✅ FIXED: no /10 — DW is already per hour
      deltaWood: _asNum(gpa?['DW']),
      deltaStone: _asNum(gpa?['DS']),
      deltaFood: _asNum(gpa?['DF']),
      deltaCoal: _asNum(gpa?['DC']),
      deltaOil: _asNum(gpa?['DO']),
      deltaGlass: _asNum(gpa?['DG']),
      deltaIron: _asNum(gpa?['DI']),
      deltaHoney: _asNum(gpa?['DHONEY']),
      deltaMead: _asNum(gpa?['DMEAD']),
      deltaAqua: _asNum(gpa?['DA']),
      maxWood: _asInt(gpa?['MRW']),  // ✅ FIXED: MRW not MRF
      maxStone: _asInt(gpa?['MRS']),
      maxFood: _asInt(gpa?['MRF']),
      maxCoal: _asInt(gpa?['MRC']),
      maxOil: _asInt(gpa?['MRO']),
      maxGlass: _asInt(gpa?['MRG']),
      maxIron: _asInt(gpa?['MRI']),
      maxHoney: _asInt(gpa?['MRHONEY']),
      maxMead: _asInt(gpa?['MRMEAD']),
      maxAqua: _asInt(gpa?['MRA']),
      units: units(a['AC'] as List?),
      strongholdUnits: units(a['SHI'] as List?),
      hospitalUnits: units(a['HI'] as List?),
      travelingUnits: units(a['TU'] as List?),
      defense: _asInt(a['D']),
      marketCarriages: _asInt(a['MC']),
      hasBarracks: a['B'] == true,
      hasSiegeWorkshop: a['WS'] == true,
      hasDefenseWorkshop: a['DW'] == true,
      hasHospital: a['H'] == true,
    );
  }

  static int _asInt(dynamic v, [int def = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? def;
    return def;
  }
  static int? _asIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
  static double _asNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}