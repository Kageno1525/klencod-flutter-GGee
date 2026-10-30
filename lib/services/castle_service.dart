import 'dart:convert';
import '../gge_client.dart';
import '../models.dart';

class CastleService {
  final GgeClient conn;
  CastleService(this.conn);

  Future<List<OwnedCastle>> getCastles() async {
    final resp = await conn.sendXtAndWait('gcl', '{}', responseCmd: 'gcl');
    if (resp.resultCode != 0) {
      throw Exception('gcl: ${errorName(resp.resultCode)}');
    }
    final data = jsonDecode(resp.payload!) as Map<String, dynamic>;
    final out = <OwnedCastle>[];
    for (final kingdom in data['C'] as List) {
      final kid = _asInt(kingdom['KID']);
      for (final areaObj in kingdom['AI'] as List) {
        final ai = areaObj['AI'] as List;
        String name = '';
        if (ai.length > 10 && ai[10] is String) name = ai[10] as String;
        out.add(OwnedCastle(
          kingdomId: kid,
          areaType: _asInt(ai[0]),
          x: _asInt(ai[1]),
          y: _asInt(ai[2]),
          areaId: _asInt(ai[3]),
          name: name,
        ));
      }
    }
    return out;
  }

  Future<List<CastleUnit>> getCastleUnits(
    int kingdomId,
    int areaId,
    Map<int, UnitCatalogEntry> catalog,
  ) async {
    TrafficLog.add('ST', '[DCL] Requesting units: KID=$kingdomId areaId=$areaId');

    final resp = await conn.sendXtAndWait('dcl', '{"CD":1}', responseCmd: 'dcl');
    if (resp.resultCode != 0) {
      TrafficLog.add('ER', '[DCL] Failed: ${errorName(resp.resultCode)}');
      throw Exception('dcl: ${errorName(resp.resultCode)}');
    }

    final data = jsonDecode(resp.payload!) as Map<String, dynamic>;
    final castles = data['C'] as List? ?? [];
    TrafficLog.add('ST', '[DCL] Response has ${castles.length} kingdoms');

    // ✅ البحث الأساسي: مطابقة KID + AID
    for (final k in castles) {
      final kKid = _asInt(k['KID']);
      if (kKid != kingdomId) continue;
      final areas = (k['AI'] as List?) ?? [];
      for (final a in areas) {
        final aAid = _asInt(a['AID']);
        if (aAid != areaId) continue;
        return _parseUnits(a, aAid, catalog);
      }
    }

    // ⚠️ Fallback: لو مش لاقيها بالـ KID، ندور في كل الممالك بالـ AID
    TrafficLog.add('ST',
        '[DCL] Not found in KID=$kingdomId, scanning all kingdoms for AID=$areaId');
    for (final k in castles) {
      final kKid = _asInt(k['KID']);
      final areas = (k['AI'] as List?) ?? [];
      for (final a in areas) {
        final aAid = _asInt(a['AID']);
        if (aAid != areaId) continue;
        TrafficLog.add('ST',
            '[DCL] Found AID=$areaId in KID=$kKid (expected $kingdomId)');
        return _parseUnits(a, aAid, catalog);
      }
    }

    TrafficLog.add('ER', '[DCL] Castle areaId=$areaId not found in any kingdom');
    return [];
  }

  List<CastleUnit> _parseUnits(
    dynamic areaObj,
    int areaId,
    Map<int, UnitCatalogEntry> catalog,
  ) {
    final ac = (areaObj['AC'] as List?) ?? [];
    TrafficLog.add('ST',
        '[DCL] Area $areaId → AC has ${ac.length} units');

    final out = <CastleUnit>[];
    int missingCatalog = 0;
    for (final u in ac) {
      if (u is! List || u.length < 2) continue;
      final id = _asInt(u[0]);
      final amt = _asInt(u[1]);
      if (amt > 0) {
        final info = catalog[id];
        if (info == null) missingCatalog++;
        out.add(CastleUnit(wodId: id, amount: amt, info: info));
      }
    }
    if (missingCatalog > 0) {
      TrafficLog.add('ST',
          '[DCL] ⚠️ $missingCatalog unit types missing from catalog');
    }
    TrafficLog.add('ST', '[DCL] Returning ${out.length} units');
    return out;
  }

  static int _asInt(dynamic v, [int def = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? def;
    return def;
  }
}