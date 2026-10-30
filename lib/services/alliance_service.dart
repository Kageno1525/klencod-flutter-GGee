import 'dart:convert';
import '../gge_client.dart';
import '../models.dart';

class AllianceService {
  final GgeClient conn;
  AllianceService(this.conn);

  Future<int?> getMyAllianceId() async {
    final cached = conn.cachedAllianceId;
    if (cached != null && cached > 0) {
      return cached;
    }
    // Wait for gbd (up to 3s)
    if (!conn.gbdReceived) {
      TrafficLog.add('ST', 'Waiting for gbd (up to 3s)...');
      final start = DateTime.now();
      while (!conn.gbdReceived &&
          DateTime.now().difference(start).inMilliseconds < 3000) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      final aid = conn.cachedAllianceId;
      if (aid != null && aid > 0) {
        return aid;
      }
    }
    // Fallback: jca → jaa
    TrafficLog.add('ST', 'Fallback: jca → jaa');
    conn.sendXt('jca', '{"CID":-1,"KID":0}');
    await Future.delayed(const Duration(milliseconds: 1500));
    return conn.cachedAllianceId;
  }

  Future<List<AllyMember>> getMembers() async {
    final cached = conn.cachedAllianceMembers;
    if (cached != null && cached.isNotEmpty) {
      TrafficLog.add('ST', 'Using cached ${cached.length} members');
      return List.from(cached);
    }

    final aid = await getMyAllianceId();
    if (aid == null) throw Exception('not_in_alliance');

    TrafficLog.add('ST', 'Sending ain with AID=$aid');
    final resp = await conn.sendXtAndWait(
      'ain',
      jsonEncode({'AID': aid}),
      responseCmd: 'ain',
      timeoutMs: 10000,
    );
    if (resp.resultCode != 0) {
      throw Exception('ain: ${errorName(resp.resultCode)}');
    }
    final data = jsonDecode(resp.payload!) as Map<String, dynamic>;
    final a = data['A'] as Map<String, dynamic>?;
    if (a == null) return [];
    final members = a['M'] as List? ?? [];
    conn.cachedAllianceMembers = _parse(members);
    return conn.cachedAllianceMembers!;
  }

  List<AllyMember> _parse(List raw) {
    final out = <AllyMember>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final castles = <AllyCastle>[];
      for (final p in (m['AP'] as List? ?? [])) {
        if (p is! List || p.length < 5) continue;
        castles.add(AllyCastle(
          kingdomId: _asInt(p[0]),
          areaId: _asInt(p[1]),
          x: _asInt(p[2]),
          y: _asInt(p[3]),
          areaType: _asInt(p[4]),
        ));
      }
      out.add(AllyMember(
        playerId: _asInt(m['OID']),
        name: (m['N'] as String?) ?? 'Unknown',
        level: _asInt(m['L']),
        peaceTimeSeconds: _asInt(m['RPT']),
        castles: castles,
      ));
    }
    return out;
  }

  static int _asInt(dynamic v, [int def = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? def;
    return def;
  }
}