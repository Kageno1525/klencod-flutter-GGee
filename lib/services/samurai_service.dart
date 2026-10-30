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

// ═══════════════════════════════════════════════════
//  Level-based formulas (من البوت القديم)
// ═══════════════════════════════════════════════════
class SamuraiMath {
  /// الحد الأقصى للوحدات في الموجة الكاملة (flank*2 + middle)
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

  /// عدد الـ waves المتاح حسب level اللاعب
  static int wavesUnlocked(int playerLvl) {
    if (playerLvl >= 51) return 4;
    if (playerLvl >= 26) return 3;
    if (playerLvl >= 13) return 2;
    return 1;
  }
}

// ═══════════════════════════════════════════════════
//  إعدادات أمر الهجوم
// ═══════════════════════════════════════════════════
class SamuraiAttackConfig {
  final int waves;        // 1..3
  final int? toolId;      // 166 = أداة عملات الساموراي (null = بدون أدوات)
  final int toolL;        // عدد الأدوات في الجناح اليسار
  final int toolR;        // اليمين
  final int toolM;        // الأمام

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
  }) => SamuraiAttackConfig(
        waves: waves ?? this.waves,
        toolId: toolId ?? this.toolId,
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
//  معسكر الساموراي
// ═══════════════════════════════════════════════════
class SamuraiCamp {
  final int x, y, kid;
  final int type;
  final int hp;         // ai[8] للأنواع 37/38 (لـ 29 = campID)
  final int level;      // ai[9] — level المعسكر
  final int level2;     // ai[10] — level احتياطي
  final int campId;     // للـ type 29 فقط
  final double distanceFromSource;
  final int sourceAreaId;
  final String sourceName;

  DateTime? lastAttackAt;
  int? lastAttackMid;

  SamuraiCamp({
    required this.x, required this.y, required this.kid,
    required this.type, required this.hp,
    required this.level, required this.level2,
    this.campId = 0,
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

  /// مدمر لو HP=0 (الأنواع 37/38 فقط — لـ 29 مفيش HP في AI)
  bool get isDead => type != 29 && hp <= 0;

  bool get hasActiveAttack {
    if (lastAttackAt == null) return false;
    return DateTime.now().difference(lastAttackAt!).inMinutes < 30;
  }

  SamuraiCamp copyWith({
    int? hp, int? level, int? level2,
    DateTime? lastAttackAt, int? lastAttackMid,
  }) => SamuraiCamp(
        x: x, y: y, kid: kid, type: type,
        hp: hp ?? this.hp,
        level: level ?? this.level,
        level2: level2 ?? this.level2,
        campId: campId,
        distanceFromSource: distanceFromSource,
        sourceAreaId: sourceAreaId, sourceName: sourceName,
        lastAttackAt: lastAttackAt ?? this.lastAttackAt,
        lastAttackMid: lastAttackMid ?? this.lastAttackMid,
      );
}

// ═══════════════════════════════════════════════════
//  نتيجة الهجوم
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

  SamuraiAttackResult._({
    required this.success, this.error, this.movementId,
    this.target, this.totalUnits = 0, this.wavesSent = 0,
    this.toolsUsed = 0, this.usedTools = false,
  });

  factory SamuraiAttackResult.ok({
    required int mid, required SamuraiCamp t,
    required int units, required int waves,
    required int tools, required bool usedTools,
  }) => SamuraiAttackResult._(
        success: true, movementId: mid, target: t,
        totalUnits: units, wavesSent: waves,
        toolsUsed: tools, usedTools: usedTools,
      );

  factory SamuraiAttackResult.fail(String err) =>
      SamuraiAttackResult._(success: false, error: err);
}

// ═══════════════════════════════════════════════════
//  إعدادات المسح
// ═══════════════════════════════════════════════════
class SamuraiSettings {
  int radiusTiles;
  int sourceAreaId;

  SamuraiSettings({
    this.radiusTiles = kSamuraiDefaultRadius,
    this.sourceAreaId = 0,
  });

  static const _kRadius = 'samurai_radius_v1';
  static const _kSource = 'samurai_source_v1';

  static Future<SamuraiSettings> load() async {
    final p = await SharedPreferences.getInstance();
    int r = p.getInt(_kRadius) ?? kSamuraiDefaultRadius;
    r = r.clamp(kSamuraiRadiusMin, kSamuraiRadiusMax);
    return SamuraiSettings(
      radiusTiles: r,
      sourceAreaId: p.getInt(_kSource) ?? 0,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kRadius, radiusTiles);
    await p.setInt(_kSource, sourceAreaId);
  }
}

// ═══════════════════════════════════════════════════
//  الخدمة الرئيسية
// ═══════════════════════════════════════════════════
class SamuraiService {
  final GgeClient conn;
  SamuraiService(this.conn);

  int? _currentKid;
  DateTime? _lastJcaAt, _lastScanAt;
  static const _scanCooldown = Duration(seconds: 10);

  final Map<String, DateTime> _cooldowns = {};
  static const _kCooldowns = 'samurai_cooldowns_v1';

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

  Future<void> markCampAttacked(SamuraiCamp c,
      {int minutes = kSamuraiDefaultCooldownMin}) async {
    _cooldowns[c.key] = DateTime.now().add(Duration(minutes: minutes));
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

  // ═══════════════════════════════════════════════
  //  المسح
  // ═══════════════════════════════════════════════
  Future<List<SamuraiCamp>> scanArea({
    required OwnedCastle source,
    required int radiusTiles,
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
              seen.add(key);

              int hp = 0, level = 0, level2 = 0, campId = 0;

              if (type == 29) {
                // ⚠️ ai[8] = eventAutoScalingCampID (مش HP!)
                if (entry.length > 8) campId = _asInt(entry[8]);
                if (entry.length > 9) level = _asInt(entry[9]);
                if (entry.length > 10) level2 = _asInt(entry[10]);
                // لو الـ level صفر، استخدم level2 كـ fallback
                if (level <= 0 && level2 > 0) level = level2;
              } else {
                // 37 و 38: ai[8] = HP, ai[9] = level, ai[10] = maxLevel
                if (entry.length > 8) hp = _asInt(entry[8]);
                if (entry.length > 9) level = _asInt(entry[9]);
                if (entry.length > 10) level2 = _asInt(entry[10]);
                if (level <= 0 && level2 > 0) level = level2;
              }

              final dx = (x - cx).toDouble();
              final dy = (y - cy).toDouble();
              found.add(SamuraiCamp(
                x: x, y: y, kid: source.kingdomId,
                type: type, hp: hp,
                level: level, level2: level2,
                campId: campId,
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

  // ═══════════════════════════════════════════════
  //  🔥 الهجوم (كامل — waves + tools + fallback)
  // ═══════════════════════════════════════════════
  Future<SamuraiAttackResult> attack({
    required SamuraiCamp camp,
    required OwnedCastle source,
    required int lordId,
    required List<CastleUnit> availableUnits,
    SamuraiAttackConfig config = const SamuraiAttackConfig(),
    int? manualLevel,
    bool markCooldownAfterSuccess = true,
  }) async {
    // 1) تحديد الـ level
    final lvl = manualLevel ?? (camp.level > 0 ? camp.level : camp.level2);
    if (lvl <= 0) {
      return SamuraiAttackResult.fail(
          'LEVEL_UNKNOWN: محتاج تحدد level المعسكر يدويًا');
    }

    // 2) الحد الأقصى للوحدات لكل موقع
    final maxFlankUnits = SamuraiMath.flankMax(lvl);
    final maxMiddleUnits = SamuraiMath.middleMax(lvl);
    final maxFlankTools = SamuraiMath.toolCapFlank(lvl);
    final maxMiddleTools = SamuraiMath.toolCapMiddle(lvl);

    // 3) فلترة الوحدات
    final combat = availableUnits
        .where((u) => u.isCombat && u.amount > 0)
        .toList();
    if (combat.isEmpty) return SamuraiAttackResult.fail('NO_UNITS');

    // 4) فصل melee / ranged
    final melee = combat.where((u) {
      if (u.info?.role == 'melee') return true;
      if (u.info?.role == 'ranged') return false;
      return u.wodId >= 601 && u.wodId <= 620;
    }).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    final ranged = combat.where((u) {
      if (u.info?.role == 'ranged') return true;
      if (u.info?.role == 'melee') return false;
      return !(u.wodId >= 601 && u.wodId <= 620);
    }).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    // 5) عدد الـ waves
    int waveCount = config.waves.clamp(1, 3);
    final totalUnits = combat.fold<int>(0, (s, u) => s + u.amount);
    final perWaveMax = maxFlankUnits * 2 + maxMiddleUnits;
    final maxByUnits = (totalUnits / perWaveMax).ceil().clamp(1, 3);
    if (waveCount > maxByUnits) waveCount = maxByUnits;

    // 6) بناء الـ waves
    final remaining = <int, int>{};
    for (final u in combat) remaining[u.wodId] = u.amount;

    final wavesPayload = <Map<String, dynamic>>[];
    int totalSent = 0;
    int toolsUsed = 0;

    for (int w = 0; w < waveCount; w++) {
      final isFirstWave = (w == 0);

      // Wave 0: ranged flanks (اختبار) — Waves 1+: melee flanks (ضربة قوية)
      final flankPool = (isFirstWave || melee.isEmpty) ? ranged : melee;
      final middlePool = ranged.isNotEmpty ? ranged : melee;

      final lU = _fillFromPool(remaining, flankPool, maxFlankUnits, 2);
      final rU = _fillFromPool(remaining, flankPool, maxFlankUnits, 2);
      final mU = _fillFromPool(remaining, middlePool, maxMiddleUnits, 6);

      final waveSum = _sum(lU) + _sum(rU) + _sum(mU);
      if (waveSum == 0) break;

      totalSent += waveSum;

      // Tools
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

    // 7) تحقق من حد 10 أنواع
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

    // 8) بناء الـ payload
    Map<String, dynamic> buildPayload(List<Map<String, dynamic>> waves) => {
          'SX': source.x, 'SY': source.y,
          'TX': camp.x, 'TY': camp.y,
          'KID': camp.kid, 'LID': lordId,
          'WT': 0, 'HBW': -1, 'BPC': 0, 'ATT': 0, 'AV': 0,
          'LP': 0, 'FC': 0, 'PTT': 1, 'SD': 0, 'ICA': 0, 'CD': 99,
          'A': waves,
          'BKS': [],
          'AST': [-1, -1, -1],
          'RW': List.generate(8, (_) => [-1, 0]),
          'ASCT': 0,
        };

    await _ensureKingdom(camp.kid);

    // 9) إرسال
    final firstTry = await _sendAttack(buildPayload(wavesPayload), camp);

    if (firstTry.success) {
      if (markCooldownAfterSuccess) await markCampAttacked(camp);
      return SamuraiAttackResult.ok(
        mid: firstTry.movementId ?? -1,
        t: camp,
        units: totalSent,
        waves: wavesPayload.length,
        tools: toolsUsed,
        usedTools: config.useTools,
      );
    }

    // 10) fallback — لو فشل ومفعّل الأدوات، جرّب بدونها
    if (config.useTools && firstTry.error != 'LEVEL_UNKNOWN') {
      final noToolWaves = wavesPayload.map((w) => {
            'L': {
              'T': List.generate(2, (_) => [-1, 0]),
              'U': w['L']['U'],
            },
            'R': {
              'T': List.generate(2, (_) => [-1, 0]),
              'U': w['R']['U'],
            },
            'M': {
              'T': List.generate(3, (_) => [-1, 0]),
              'U': w['M']['U'],
            },
          }).toList();

      final secondTry =
          await _sendAttack(buildPayload(noToolWaves), camp);

      if (secondTry.success) {
        if (markCooldownAfterSuccess) await markCampAttacked(camp);
        return SamuraiAttackResult.ok(
          mid: secondTry.movementId ?? -1,
          t: camp,
          units: totalSent,
          waves: noToolWaves.length,
          tools: 0,
          usedTools: false,
        );
      }
      return secondTry;
    }

    return firstTry;
  }

  Future<SamuraiAttackResult> _sendAttack(
    Map<String, dynamic> payload,
    SamuraiCamp camp,
  ) async {
    try {
      final resp = await conn.sendXtAndWait(
        'cra',
        jsonEncode(payload),
        responseCmd: 'cra',
        timeoutMs: 25000,
        isAction: true,
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
      if (code == 91) return SamuraiAttackResult.fail('UNIT_NOT_SENDABLE_91');
      if (code == 218) return SamuraiAttackResult.fail('LORD_BUSY_218');
      if (code == 181) return SamuraiAttackResult.fail('MAX_MOVEMENTS_181');
      if (code == 100) return SamuraiAttackResult.fail('CRA_100');
      if (code == 313) return SamuraiAttackResult.fail('TOO_MANY_UNITS_313');
      return SamuraiAttackResult.fail('CRA $code');
    } catch (e) {
      return SamuraiAttackResult.fail('$e');
    }
  }

  // ═══════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════
  List<List<int>> _fillFromPool(
    Map<int, int> remaining,
    List<CastleUnit> pool,
    int maxTotal,
    int slots,
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

    // وزّع على الـ slots بالعدل
    final out = <List<int>>[];
    int remaining = effective;
    for (int i = 0; i < slots; i++) {
      final left = slots - i;
      final take = (remaining / left).ceil();
      if (take > 0 && remaining > 0) {
        final amt = take > remaining ? remaining : take;
        out.add([toolId, amt]);
        remaining -= amt;
      } else {
        out.add([-1, 0]);
      }
    }
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