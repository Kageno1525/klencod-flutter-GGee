import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../gge_client.dart';
import '../models.dart';

// ═══════════════════════════════════════════════════
//  ثوابت
// ═══════════════════════════════════════════════════
const Set<int> kSamuraiCampTypes = {29, 37, 38};
const int kSamuraiChunkSize = 13;
const int kSamuraiRadiusMin = 10;
const int kSamuraiRadiusMax = 100;
const int kSamuraiRadiusStep = 10;
const int kSamuraiDefaultRadius = 30;
const int kSamuraiDefaultCooldownMin = 5;

const Set<int> kDefensiveUnitWodIds = {
  1, 2, 3, 4, 5, 6, 7, 8, 9,
};

const int kSafeMaxFlankUnits = 42;
const int kSafeMaxMiddleUnits = 124;

class SamuraiMath {
  static int maxAttackers(int lvl) {
    if (lvl <= 69) {
      final a = 5 * lvl + 8;
      return a < 260 ? a : 260;
    }
    return 320;
  }
  static int flankMax(int lvl) => (0.2 * maxAttackers(lvl)).ceil();
  static int middleMax(int lvl) => maxAttackers(lvl) - 2 * flankMax(lvl);
  static int toolCapFlank(int lvl) {
    if (lvl < 37) return 10;
    if (lvl < 50) return 20;
    if (lvl < 69) return 30;
    return 40;
  }
  static int toolCapMiddle(int lvl) {
    if (lvl < 11) return 10;
    if (lvl < 37) return 20;
    if (lvl < 50) return 30;
    if (lvl < 69) return 40;
    return 50;
  }
  static int wavesUnlocked(int playerLvl) {
    if (playerLvl >= 51) return 4;
    if (playerLvl >= 26) return 3;
    if (playerLvl >= 13) return 2;
    return 1;
  }
}

// ═══════════════════════════════════════════════════
//  إعدادات أمر الهجوم (تم إصلاح copyWith)
// ═══════════════════════════════════════════════════
class SamuraiAttackConfig {
  final int waves;
  final int? toolId;
  final int toolL;
  final int toolR;
  final int toolM;

  const SamuraiAttackConfig({
    this.waves = 3,
    this.toolId = 166,
    this.toolL = 20,
    this.toolR = 20,
    this.toolM = 30,
  });

  bool get useTools =>
      toolId != null && toolId! > 0 && (toolL + toolR + toolM) > 0;

  int get toolsPerWave => useTools ? (toolL + toolR + toolM) : 0;

  SamuraiAttackConfig copyWith({
    int? waves, int? toolId, int? toolL, int? toolR, int? toolM,
    bool clearToolId = false,
  }) => SamuraiAttackConfig(
        waves: waves ?? this.waves,
        toolId: clearToolId ? null : (toolId ?? this.toolId),
        toolL: toolL ?? this.toolL,
        toolR: toolR ?? this.toolR,
        toolM: toolM ?? this.toolM,
      );

  SamuraiAttackConfig withoutTools() => SamuraiAttackConfig(
        waves: waves, toolId: null,
        toolL: toolL, toolR: toolR, toolM: toolM,
      );
}

// ═══════════════════════════════════════════════════
class SamuraiCamp {
  final int x, y, kid;
  final int type;
  final int hp;
  final int level;
  final int level2;
  final int campId;
  final int ownerId;
  final double distanceFromSource;
  final int sourceAreaId;
  final String sourceName;

  DateTime? lastAttackAt;
  int? lastAttackMid;

  SamuraiCamp({
    required this.x, required this.y, required this.kid,
    required this.type, required this.hp,
    required this.level, required this.level2,
    this.campId = 0, this.ownerId = -1,
    required this.distanceFromSource,
    required this.sourceAreaId, required this.sourceName,
    this.lastAttackAt, this.lastAttackMid,
  });

  String get typeName => switch (type) {
        29 => 'Samurai Camp',
        37 => 'Samurai I',
        38 => 'Samurai II',
        _ => 'Camp $type',
      };

  String get coordsLabel => '($x,$y)';
  String get key => '$x,$y,$kid';
  bool get isDead => type != 29 && hp <= 0;
  bool get isPlayerCamp => ownerId != -1;

  SamuraiCamp copyWith({
    int? hp, int? level, int? level2,
    DateTime? lastAttackAt, int? lastAttackMid,
  }) => SamuraiCamp(
        x: x, y: y, kid: kid, type: type,
        hp: hp ?? this.hp,
        level: level ?? this.level,
        level2: level2 ?? this.level2,
        campId: campId, ownerId: ownerId,
        distanceFromSource: distanceFromSource,
        sourceAreaId: sourceAreaId, sourceName: sourceName,
        lastAttackAt: lastAttackAt ?? this.lastAttackAt,
        lastAttackMid: lastAttackMid ?? this.lastAttackMid,
      );
}

// ═══════════════════════════════════════════════════
class SamuraiAttackResult {
  final bool success;
  final String? error;
  final int? movementId;
  final SamuraiCamp? target;
  final int totalUnits;
  final int wavesSent;
  final int toolsUsed;
  final bool usedTools;
  final int lordIdUsed;

  SamuraiAttackResult._({
    required this.success, this.error, this.movementId,
    this.target, this.totalUnits = 0, this.wavesSent = 0,
    this.toolsUsed = 0, this.usedTools = false, this.lordIdUsed = 0,
  });

  factory SamuraiAttackResult.ok({
    required int mid, required SamuraiCamp t,
    required int units, required int waves,
    required int tools, required bool usedTools, int lordIdUsed = 0,
  }) => SamuraiAttackResult._(
        success: true, movementId: mid, target: t,
        totalUnits: units, wavesSent: waves,
        toolsUsed: tools, usedTools: usedTools, lordIdUsed: lordIdUsed,
      );

  factory SamuraiAttackResult.fail(String err) =>
      SamuraiAttackResult._(success: false, error: err);

  SamuraiAttackResult copyWithLordId(int lid) => SamuraiAttackResult._(
        success: success, error: error, movementId: movementId,
        target: target, totalUnits: totalUnits, wavesSent: wavesSent,
        toolsUsed: toolsUsed, usedTools: usedTools, lordIdUsed: lid,
      );
}

// ═══════════════════════════════════════════════════
class SamuraiSettings {
  int radiusTiles;
  int sourceAreaId;
  int maxLevel;
  bool skipPlayerCamps;

  SamuraiSettings({
    this.radiusTiles = kSamuraiDefaultRadius,
    this.sourceAreaId = 0,
    this.maxLevel = 100,
    this.skipPlayerCamps = true,
  });

  static const _kRadius = 'samurai_radius_v1';
  static const _kSource = 'samurai_source_v1';
  static const _kMaxLevel = 'samurai_max_level_v1';
  static const _kSkipPlayer = 'samurai_skip_player_v1';

  static Future<SamuraiSettings> load() async {
    final p = await SharedPreferences.getInstance();
    int r = p.getInt(_kRadius) ?? kSamuraiDefaultRadius;
    r = r.clamp(kSamuraiRadiusMin, kSamuraiRadiusMax);
    return SamuraiSettings(
      radiusTiles: r,
      sourceAreaId: p.getInt(_kSource) ?? 0,
      maxLevel: p.getInt(_kMaxLevel) ?? 100,
      skipPlayerCamps: p.getBool(_kSkipPlayer) ?? true,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kRadius, radiusTiles);
    await p.setInt(_kSource, sourceAreaId);
    await p.setInt(_kMaxLevel, maxLevel);
    await p.setBool(_kSkipPlayer, skipPlayerCamps);
  }
}

// ═══════════════════════════════════════════════════
class SamuraiService {
  final GgeClient conn;
  SamuraiService(this.conn);

  int? _currentKid;
  DateTime? _lastJcaAt, _lastScanAt;
  static const _scanCooldown = Duration(seconds: 10);

  final Map<String, DateTime> _cooldowns = {};
  static const _kCooldowns = 'samurai_cooldowns_v1';
  final Map<String, DateTime> _activeCamps = {};

  Future<void> loadCooldowns() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kCooldowns);
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final now = DateTime.now();
      _cooldowns.clear();
      for (final e in data.entries) {
        final dt = DateTime.tryParse(e.value as String);
        if (dt != null && dt.isAfter(now)) _cooldowns[e.key] = dt;
      }
    } catch (_) {}
  }

  Future<void> _saveCooldowns() async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final data = <String, String>{};
    for (final e in _cooldowns.entries) {
      if (e.value.isAfter(now)) data[e.key] = e.value.toIso8601String();
    }
    await p.setString(_kCooldowns, jsonEncode(data));
  }

  bool isCampInCooldown(SamuraiCamp c) {
    final dt = _cooldowns[c.key];
    if (dt == null) return false;
    if (dt.isBefore(DateTime.now())) {
      _cooldowns.remove(c.key);
      return false;
    }
    return true;
  }

  Duration campCooldownRemaining(SamuraiCamp c) {
    final dt = _cooldowns[c.key];
    if (dt == null) return Duration.zero;
    final r = dt.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  bool isCampUnderAttack(SamuraiCamp c) {
    final dt = _activeCamps[c.key];
    if (dt == null) return false;
    if (DateTime.now().difference(dt).inMinutes >= 30) {
      _activeCamps.remove(c.key);
      return false;
    }
    return true;
  }

  Future<void> markCampAttacked(SamuraiCamp c,
      {int minutes = kSamuraiDefaultCooldownMin}) async {
    _cooldowns[c.key] = DateTime.now().add(Duration(minutes: minutes));
    _activeCamps[c.key] = DateTime.now();
    await _saveCooldowns();
  }

  Future<void> _ensureKingdom(int kid) async {
    if (_currentKid == kid &&
        _lastJcaAt != null &&
        DateTime.now().difference(_lastJcaAt!).inMinutes < 5) return;
    try {
      await conn.sendXtAndWait('jca', jsonEncode({'CID': -1, 'KID': kid}),
          responseCmd: 'jaa', timeoutMs: 8000, isAction: false);
      _currentKid = kid;
      _lastJcaAt = DateTime.now();
    } catch (_) {}
  }

  Future<List<SamuraiCamp>> scanArea({
    required OwnedCastle source,
    required int radiusTiles,
    int maxLevel = 100,
    bool skipPlayerCamps = true,
    void Function(int done, int total)? onProgress,
  }) async {
    if (_lastScanAt != null &&
        DateTime.now().difference(_lastScanAt!) < _scanCooldown) {
      throw Exception('SCAN_COOLDOWN: انتظر قبل مسح جديد');
    }
    _lastScanAt = DateTime.now();
    await _ensureKingdom(source.kingdomId);

    final cx = source.x, cy = source.y;
    final minX = (cx - radiusTiles).clamp(1, 1000);
    final maxX = (cx + radiusTiles).clamp(1, 1000);
    final minY = (cy - radiusTiles).clamp(1, 1000);
    final maxY = (cy + radiusTiles).clamp(1, 1000);

    final startX = (minX ~/ kSamuraiChunkSize) * kSamuraiChunkSize;
    final endX = (maxX ~/ kSamuraiChunkSize) * kSamuraiChunkSize;
    final startY = (minY ~/ kSamuraiChunkSize) * kSamuraiChunkSize;
    final endY = (maxY ~/ kSamuraiChunkSize) * kSamuraiChunkSize;

    final chunks = <List<int>>[];
    for (int x = startX; x <= endX; x += kSamuraiChunkSize) {
      for (int y = startY; y <= endY; y += kSamuraiChunkSize) {
        chunks.add([
          x, y,
          (x + kSamuraiChunkSize - 1).clamp(1, 1000),
          (y + kSamuraiChunkSize - 1).clamp(1, 1000),
        ]);
      }
    }
    if (chunks.length > 40) chunks.removeRange(40, chunks.length);

    final found = <SamuraiCamp>[];
    final seen = <String>{};
    int done = 0;

    for (final chunk in chunks) {
      try {
        final resp = await conn.sendXtAndWait(
          'gaa',
          jsonEncode({
            'KID': source.kingdomId,
            'AX1': chunk[0], 'AY1': chunk[1],
            'AX2': chunk[2], 'AY2': chunk[3],
          }),
          responseCmd: 'gaa', timeoutMs: 15000, isAction: false,
        );

        if (resp.resultCode == 0 && resp.payload != null) {
          final data = jsonDecode(resp.payload!) as Map<String, dynamic>;
          final ai = data['AI'] as List?;
          if (ai != null) {
            for (final entry in ai) {
              if (entry is! List || entry.length < 3) continue;
              final type = _asInt(entry[0]);
              if (!kSamuraiCampTypes.contains(type)) continue;

              final x = _asInt(entry[1]);
              final y = _asInt(entry[2]);
              final key = '$x,$y';
              if (seen.contains(key)) continue;

              final ownerId = _asInt(entry[3], -1);
              int hp = 0, level = 0, level2 = 0, campId = 0;

              if (type == 29) {
                if (entry.length > 8) campId = _asInt(entry[8]);
                if (entry.length > 9) level = _asInt(entry[9]);
                if (entry.length > 10) level2 = _asInt(entry[10]);
                if (level <= 0 && level2 > 0) level = level2;
              } else {
                if (entry.length > 8) hp = _asInt(entry[8]);
                if (entry.length > 9) level = _asInt(entry[9]);
                if (entry.length > 10) level2 = _asInt(entry[10]);
                if (level <= 0 && level2 > 0) level = level2;
              }

              if (skipPlayerCamps && ownerId != -1) {
                TrafficLog.add('ST',
                    '[Samurai] ⏭️ Skip player camp at ($x,$y) ownerId=$ownerId');
                continue;
              }
              if (maxLevel > 0 && level > maxLevel) {
                TrafficLog.add('ST',
                    '[Samurai] ⏭️ Skip high-level camp ($x,$y) Lv$level > max$maxLevel');
                continue;
              }

              seen.add(key);
              final dx = (x - cx).toDouble();
              final dy = (y - cy).toDouble();
              found.add(SamuraiCamp(
                x: x, y: y, kid: source.kingdomId,
                type: type, hp: hp,
                level: level, level2: level2,
                campId: campId, ownerId: ownerId,
                distanceFromSource: sqrt(dx * dx + dy * dy),
                sourceAreaId: source.areaId,
                sourceName: source.displayName,
              ));
            }
          }
        }
      } catch (_) {}
      done++;
      onProgress?.call(done, chunks.length);
      if (done < chunks.length) {
        await Future.delayed(
            Duration(milliseconds: 800 + Random().nextInt(400)));
      }
    }
    return found;
  }

  Future<SamuraiAttackResult> attack({
    required SamuraiCamp camp,
    required OwnedCastle source,
    required int lordId,
    required List<CastleUnit> availableUnits,
    SamuraiAttackConfig config = const SamuraiAttackConfig(),
    int? manualLevel,
    List<Lord>? fallbackLords,
    bool markCooldownAfterSuccess = true,
  }) async {
    if (isCampUnderAttack(camp)) {
      return SamuraiAttackResult.fail(
          'CAMP_UNDER_ATTACK: فيه هجوم شغال على (${camp.coordsLabel})');
    }

    final lordsToTry = <int>[lordId];
    if (fallbackLords != null) {
      for (final l in fallbackLords) {
        if (l.id != lordId && l.id > 0 && !lordsToTry.contains(l.id)) {
          lordsToTry.add(l.id);
        }
      }
    }

    SamuraiAttackResult? lastResult;

    for (final lid in lordsToTry) {
      TrafficLog.add('ST',
          '[Samurai] ⚔️ Try Lord $lid on ${camp.coordsLabel}');

      var result = await _tryAttack(
        camp: camp, source: source, lordId: lid,
        availableUnits: availableUnits, config: config,
        manualLevel: manualLevel, unitScale: 1.0,
      );

      if (result.success) {
        if (markCooldownAfterSuccess) await markCampAttacked(camp);
        return result.copyWithLordId(lid);
      }

      if (result.error == 'CRA 313' || result.error == 'TOO_MANY_UNITS_313') {
        TrafficLog.add('ST',
            '[Samurai] ⚠️ 313 → retry 1 wave · 70% units · same tools');
        result = await _tryAttack(
          camp: camp, source: source, lordId: lid,
          availableUnits: availableUnits,
          config: config.copyWith(waves: 1),
          manualLevel: manualLevel, unitScale: 0.7,
        );
        if (result.success) {
          if (markCooldownAfterSuccess) await markCampAttacked(camp);
          return result.copyWithLordId(lid);
        }
      }

      if (config.useTools && (result.error?.contains('313') == true ||
          result.error == 'CRA 100' ||
          result.error == 'UNIT_NOT_SENDABLE_91')) {
        TrafficLog.add('ST',
            '[Samurai] ⚠️ retry 1 wave · 70% units · WITHOUT tools');
        result = await _tryAttack(
          camp: camp, source: source, lordId: lid,
          availableUnits: availableUnits,
          config: config.withoutTools().copyWith(waves: 1),
          manualLevel: manualLevel, unitScale: 0.7,
        );
        if (result.success) {
          if (markCooldownAfterSuccess) await markCampAttacked(camp);
          return result.copyWithLordId(lid);
        }
      }

      lastResult = result;

      final err = result.error ?? '';
      final isLordIssue = err.contains('256') ||
          err.contains('218') ||
          err.contains('CRA 6') ||
          err.contains('404');
      if (!isLordIssue) break;
      TrafficLog.add('ST',
          '[Samurai] 🔄 Lord $lid failed ($err) → try next lord');
    }

    return lastResult ?? SamuraiAttackResult.fail('ALL_ATTEMPTS_FAILED');
  }

  Future<SamuraiAttackResult> _tryAttack({
    required SamuraiCamp camp,
    required OwnedCastle source,
    required int lordId,
    required List<CastleUnit> availableUnits,
    required SamuraiAttackConfig config,
    int? manualLevel,
    double unitScale = 1.0,
  }) async {
    final lvl = manualLevel ?? (camp.level > 0 ? camp.level : camp.level2);
    if (lvl <= 0) {
      return SamuraiAttackResult.fail(
          'LEVEL_UNKNOWN: محتاج تحدد level المعسكر يدويًا');
    }

    final rawFlank = SamuraiMath.flankMax(lvl);
    final rawMiddle = SamuraiMath.middleMax(lvl);
    final maxFlankUnits = min(rawFlank, kSafeMaxFlankUnits);
    final maxMiddleUnits = min(rawMiddle, kSafeMaxMiddleUnits);
    final maxFlankTools = SamuraiMath.toolCapFlank(lvl);
    final maxMiddleTools = SamuraiMath.toolCapMiddle(lvl);

    final combat = availableUnits
        .where((u) => u.amount > 0 && _isOffensiveUnit(u))
        .toList();
    if (combat.isEmpty) {
      return SamuraiAttackResult.fail(
          'NO_OFFENSIVE_UNITS: مفيش وحدات هجومية في القلعة');
    }

    final melee = combat.where((u) {
      if (u.info?.role == 'melee') return true;
      if (u.info?.role == 'ranged') return false;
      return u.wodId >= 10 && u.wodId <= 20;
    }).toList()..sort((a, b) => b.amount.compareTo(a.amount));

    final ranged = combat.where((u) {
      if (u.info?.role == 'ranged') return true;
      if (u.info?.role == 'melee') return false;
      return !(u.wodId >= 10 && u.wodId <= 20);
    }).toList()..sort((a, b) => b.amount.compareTo(a.amount));

    int waveCount = config.waves.clamp(1, 3);
    final totalUnits = combat.fold<int>(0, (s, u) => s + u.amount);
    final perWaveMax = maxFlankUnits * 2 + maxMiddleUnits;
    final maxByUnits = (totalUnits / perWaveMax).ceil().clamp(1, 3);
    if (waveCount > maxByUnits) waveCount = maxByUnits;

    final remaining = <int, int>{};
    for (final u in combat) remaining[u.wodId] = u.amount;

    final wavesPayload = <Map<String, dynamic>>[];
    int totalSent = 0;
    int toolsUsed = 0;

    for (int w = 0; w < waveCount; w++) {
      final isFirstWave = (w == 0);
      final flankPool = (isFirstWave || melee.isEmpty) ? ranged : melee;
      final middlePool = ranged.isNotEmpty ? ranged : melee;

      final scaledFlank = (maxFlankUnits * unitScale).round();
      final scaledMiddle = (maxMiddleUnits * unitScale).round();

      final lU = _fillFromPool(remaining, flankPool, scaledFlank, 2);
      final rU = _fillFromPool(remaining, flankPool, scaledFlank, 2);
      final mU = _fillFromPool(remaining, middlePool, scaledMiddle, 6);

      final waveSum = _sum(lU) + _sum(rU) + _sum(mU);
      if (waveSum == 0) break;

      totalSent += waveSum;

      List<List<int>> lT2, rT2, mT2;
      if (config.useTools) {
        lT2 = _fillTools(config.toolId!, config.toolL, 2, maxFlankTools);
        rT2 = _fillTools(config.toolId!, config.toolR, 2, maxFlankTools);
        mT2 = _fillTools(config.toolId!, config.toolM, 3, maxMiddleTools);
        toolsUsed += _sumTools(lT2) + _sumTools(rT2) + _sumTools(mT2);
      } else {
        lT2 = List.generate(2, (_) => [-1, 0]);
        rT2 = List.generate(2, (_) => [-1, 0]);
        mT2 = List.generate(3, (_) => [-1, 0]);
      }

      wavesPayload.add({
        'L': {'T': lT2, 'U': lU},
        'R': {'T': rT2, 'U': rU},
        'M': {'T': mT2, 'U': mU},
      });
    }

    if (wavesPayload.isEmpty) return SamuraiAttackResult.fail('NO_WAVES');

    final usedIds = <int>{};
    for (final w in wavesPayload) {
      for (final wing in ['L', 'R', 'M']) {
        for (final u in (w[wing]['U'] as List)) {
          if ((u as List)[0] > 0) usedIds.add(u[0] as int);
        }
      }
    }
    if (usedIds.length > 10) {
      return SamuraiAttackResult.fail(
          'TOO_MANY_UNIT_TYPES (${usedIds.length} > 10)');
    }

    final payload = {
      'SX': source.x, 'SY': source.y,
      'TX': camp.x, 'TY': camp.y,
      'KID': camp.kid, 'LID': lordId,
      'WT': 0, 'HBW': -1, 'BPC': 0, 'ATT': 0, 'AV': 0,
      'LP': 0, 'FC': 0, 'PTT': 1, 'SD': 0, 'ICA': 0, 'CD': 99,
      'A': wavesPayload,
      'BKS': [],
      'AST': [-1, -1, -1],
      'RW': List.generate(8, (_) => [-1, 0]),
      'ASCT': 0,
    };

    await _ensureKingdom(camp.kid);

    final result = await _sendAttack(payload, camp);

    if (result.success) {
      return SamuraiAttackResult.ok(
        mid: result.movementId ?? -1, t: camp,
        units: totalSent, waves: wavesPayload.length,
        tools: toolsUsed, usedTools: config.useTools,
        lordIdUsed: lordId,
      );
    }
    return result;
  }

  Future<SamuraiAttackResult> _sendAttack(
    Map<String, dynamic> payload, SamuraiCamp camp,
  ) async {
    try {
      final resp = await conn.sendXtAndWait(
        'cra', jsonEncode(payload),
        responseCmd: 'cra', timeoutMs: 25000, isAction: true,
      );

      if (resp.resultCode == 0) {
        int? mid;
        if (resp.payload != null) {
          try {
            mid = _extractMovementMid(
                jsonDecode(resp.payload!) as Map<String, dynamic>);
          } catch (_) {}
        }
        return SamuraiAttackResult.ok(
          mid: mid ?? -1, t: camp,
          units: 0, waves: 0, tools: 0, usedTools: false,
        );
      }

      final code = resp.resultCode;
      if (code == 6) return SamuraiAttackResult.fail('CRA 6');
      if (code == 91) return SamuraiAttackResult.fail('UNIT_NOT_SENDABLE_91');
      if (code == 100) return SamuraiAttackResult.fail('CRA 100');
      if (code == 218) return SamuraiAttackResult.fail('LORD_BUSY_218');
      if (code == 181) return SamuraiAttackResult.fail('MAX_MOVEMENTS_181');
      if (code == 256) return SamuraiAttackResult.fail('CRA 256');
      if (code == 313) return SamuraiAttackResult.fail('TOO_MANY_UNITS_313');
      return SamuraiAttackResult.fail('CRA $code');
    } catch (e) {
      return SamuraiAttackResult.fail('$e');
    }
  }

  bool _isOffensiveUnit(CastleUnit u) {
    if (u.info?.fightType != null) {
      return u.info!.fightType == 0;
    }
    if (kDefensiveUnitWodIds.contains(u.wodId)) return false;
    return u.info?.role == 'melee' || u.info?.role == 'ranged';
  }

  List<List<int>> _fillFromPool(
    Map<int, int> remaining, List<CastleUnit> pool, int maxTotal, int slots,
  ) {
    final out = <List<int>>[];
    int allocated = 0;
    for (final u in pool) {
      if (allocated >= maxTotal || out.length >= slots) break;
      final rem = remaining[u.wodId] ?? 0;
      if (rem <= 0) continue;
      final take = (maxTotal - allocated).clamp(0, rem);
      if (take <= 0) continue;
      out.add([u.wodId, take]);
      remaining[u.wodId] = rem - take;
      allocated += take;
    }
    while (out.length < slots) out.add([-1, 0]);
    return out;
  }

  List<List<int>> _fillTools(int toolId, int total, int slots, int cap) {
    if (toolId <= 0 || total <= 0) {
      return List.generate(slots, (_) => [-1, 0]);
    }
    final effective = total.clamp(0, cap);
    if (effective <= 0) return List.generate(slots, (_) => [-1, 0]);

    final out = List.generate(slots, (_) => [-1, 0]);
    out[0] = [toolId, effective];
    return out;
  }

  int _sum(List<List<int>> u) =>
      u.fold<int>(0, (s, e) => s + (e[0] > 0 ? e[1] : 0));
  int _sumTools(List<List<int>> u) =>
      u.fold<int>(0, (s, e) => s + (e[0] > 0 ? e[1] : 0));

  int? _extractMovementMid(Map<String, dynamic> data) {
    final m = (data['A'] as Map?)?['M'] as Map?;
    if (m != null) {
      final mid = _asIntOrNull(m['MID']);
      if (mid != null && mid > 0) return mid;
    }
    return _asIntOrNull(data['MID']);
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
}