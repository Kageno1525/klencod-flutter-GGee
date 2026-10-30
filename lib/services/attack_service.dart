import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../gge_client.dart';
import '../models.dart';

const List<int> kAllUiLevels = [40, 50, 60, 70, 80];
const int kRadiusMin = 5;
const int kRadiusMax = 100;
const int kRadiusStep = 5;
const int kChunkSize = 13;

class NpcTarget {
  final int x, y, kid;
  final int type; // 24 = NPC عادي, 25 = gold camp
  final int areaId;
  final int uiLevel; // 40-80 (من rawLevel أو من GC بعد enrich)
  final int sourceAreaId;
  final String sourceName;
  final double distanceFromSource;

  int? goldCampValue;    // من ssi (GC) — بس لـ type 25
  final int? attacksRemaining; // من gaa AI[0][7] — بس لـ type 25
  DateTime? lastEnrichedAt;

  NpcTarget({
    required this.x, required this.y, required this.kid,
    required this.type, required this.areaId, required this.uiLevel,
    required this.sourceAreaId, required this.sourceName,
    required this.distanceFromSource,
    this.goldCampValue, this.attacksRemaining, this.lastEnrichedAt,
  });

  NpcTarget copyWith({
    int? uiLevel, int? goldCampValue, DateTime? lastEnrichedAt,
  }) =>
      NpcTarget(
        x: x, y: y, kid: kid, type: type, areaId: areaId,
        uiLevel: uiLevel ?? this.uiLevel,
        sourceAreaId: sourceAreaId,
        sourceName: sourceName,
        distanceFromSource: distanceFromSource,
        goldCampValue: goldCampValue ?? this.goldCampValue,
        attacksRemaining: attacksRemaining,
        lastEnrichedAt: lastEnrichedAt ?? this.lastEnrichedAt,
      );

  bool get isEnriched => lastEnrichedAt != null;
  bool get isStaleEnrichment {
    if (lastEnrichedAt == null) return true;
    return DateTime.now().difference(lastEnrichedAt!).inMinutes >= 5;
  }

  // ✅ الذهبي: GC=75 و type=25 فقط
  bool get isLegendary => type == 25 && (goldCampValue ?? 0) >= 75;

  // ✅ يعرض GC badge: بس لو type 25 و GC>=40 (يمنع GC:15 المزعج)
  bool get hasGold => type == 25 && (goldCampValue ?? 0) >= 40;

  // ✅ الهجمات: لو null أو -1 → غير محدود
  bool get hasAttacksLimit =>
      attacksRemaining != null && attacksRemaining! >= 0;

  String get typeLabel => type == 24 ? 'NPC' : 'Gold Camp';
}

class NpcAttackResult {
  final bool success;
  final String? error;
  final int? movementId;
  final NpcTarget? target;
  final int totalUnits;

  NpcAttackResult._({
    required this.success, this.error, this.movementId, this.target,
    this.totalUnits = 0,
  });

  factory NpcAttackResult.ok(int mid, NpcTarget t, int units) =>
      NpcAttackResult._(success: true, movementId: mid, target: t, totalUnits: units);
  factory NpcAttackResult.fail(String err) =>
      NpcAttackResult._(success: false, error: err);
}

class AttackFilterSettings {
  Set<int> visibleUiLevels;
  int radiusTiles;
  String sortBy;
  bool onlyGoldCamps;
  int sourceAreaId;

  AttackFilterSettings({
    Set<int>? visibleUiLevels,
    this.radiusTiles = 50,
    this.sortBy = 'level',
    this.onlyGoldCamps = false,
    this.sourceAreaId = 0,
  }) : visibleUiLevels = visibleUiLevels ?? kAllUiLevels.toSet();

  static const _kLevels = 'atk_levels_v6';
  static const _kRadius = 'atk_radius_v4';
  static const _kSort = 'atk_sort';
  static const _kGold = 'atk_gold_only';
  static const _kSource = 'atk_source';

  static Future<AttackFilterSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final lvlList = p.getStringList(_kLevels);
    Set<int>? uiLevels;
    if (lvlList != null && lvlList.isNotEmpty) {
      uiLevels = lvlList
          .map((s) => int.tryParse(s) ?? 0)
          .where((i) => kAllUiLevels.contains(i))
          .toSet();
      if (uiLevels.isEmpty) uiLevels = kAllUiLevels.toSet();
    }
    int radius = p.getInt(_kRadius) ?? 50;
    if (radius > kRadiusMax) radius = kRadiusMax;
    if (radius < kRadiusMin) radius = kRadiusMin;

    return AttackFilterSettings(
      visibleUiLevels: uiLevels,
      radiusTiles: radius,
      sortBy: p.getString(_kSort) ?? 'level',
      onlyGoldCamps: p.getBool(_kGold) ?? false,
      sourceAreaId: p.getInt(_kSource) ?? 0,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        _kLevels, visibleUiLevels.map((i) => i.toString()).toList());
    await p.setInt(_kRadius, radiusTiles);
    await p.setString(_kSort, sortBy);
    await p.setBool(_kGold, onlyGoldCamps);
    await p.setInt(_kSource, sourceAreaId);
  }
}

class AttackService {
  final GgeClient conn;
  AttackService(this.conn);

  int? _currentKid;
  DateTime? _lastJcaAt;
  DateTime? _lastScanAt;
  static const _scanCooldown = Duration(seconds: 30);

  Future<void> _ensureKingdom(int kid) async {
    if (_currentKid == kid &&
        _lastJcaAt != null &&
        DateTime.now().difference(_lastJcaAt!).inMinutes < 5) {
      return;
    }
    try {
      await conn.sendXtAndWait(
        'jca',
        jsonEncode({'CID': -1, 'KID': kid}),
        responseCmd: 'jaa',
        timeoutMs: 8000,
        isAction: false,
      );
      _currentKid = kid;
      _lastJcaAt = DateTime.now();
    } catch (e) {
      TrafficLog.add('ER', '[Attack] jca failed: $e');
    }
  }

  Future<List<NpcTarget>> scanArea({
    required OwnedCastle source,
    required int radiusTiles,
    void Function(int done, int total)? onProgress,
  }) async {
    if (_lastScanAt != null &&
        DateTime.now().difference(_lastScanAt!) < _scanCooldown) {
      throw Exception('SCAN_COOLDOWN: انتظر قليلاً قبل مسح جديد');
    }
    _lastScanAt = DateTime.now();

    await _ensureKingdom(source.kingdomId);

    final cx = source.x;
    final cy = source.y;
    final minX = (cx - radiusTiles).clamp(1, 1000);
    final maxX = (cx + radiusTiles).clamp(1, 1000);
    final minY = (cy - radiusTiles).clamp(1, 1000);
    final maxY = (cy + radiusTiles).clamp(1, 1000);

    // ✅ chunk 13×13 (زي اللعبة)
    final startX = (minX ~/ kChunkSize) * kChunkSize;
    final endX = (maxX ~/ kChunkSize) * kChunkSize;
    final startY = (minY ~/ kChunkSize) * kChunkSize;
    final endY = (maxY ~/ kChunkSize) * kChunkSize;

    final chunks = <List<int>>[];
    for (int x = startX; x <= endX; x += kChunkSize) {
      for (int y = startY; y <= endY; y += kChunkSize) {
        chunks.add([
          x, y,
          (x + kChunkSize - 1).clamp(1, 1000),
          (y + kChunkSize - 1).clamp(1, 1000),
        ]);
      }
    }

    if (chunks.length > 40) {
      chunks.removeRange(40, chunks.length);
      TrafficLog.add('ST', '[Attack] Scan capped to 40 chunks');
    }

    final found = <NpcTarget>[];
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
          responseCmd: 'gaa',
          timeoutMs: 15000,
          isAction: false,
        );

        if (resp.resultCode == 0 && resp.payload != null) {
          final data = jsonDecode(resp.payload!) as Map<String, dynamic>;
          final ai = data['AI'] as List?;
          if (ai != null) {
            for (final entry in ai) {
              if (entry is! List || entry.length < 9) continue;
              final type = _asInt(entry[0]);

              int uiLevel;
              int? attacks;

              if (type == 24) {
                // NPC عادي: rawLevel في index[8], هجمات = index[7] (-1 = غير محدود)
                final rawLevel = _asInt(entry[8]);
                if (rawLevel < 2 || rawLevel > 6) continue;
                uiLevel = rawLevel * 10 + 20;
                attacks = _asInt(entry[7]); // -1 = unlimited
              } else if (type == 25) {
                // ✅ gold camp: لازم index[6]==0 (مفيش موارد) و index[7]>0 (فيه هجمات)
                //    لو index[6]>0 → resource node (مش للهجوم)
                final currentRes = _asInt(entry[6]);
                final atk = _asInt(entry[7]);
                if (currentRes > 0 || atk <= 0) continue; // مش gold camp
                attacks = atk; // 3-10 هجمات
                uiLevel = 0; // هنحسبها بعدين من GC
              } else {
                continue;
              }

              final x = _asInt(entry[1]);
              final y = _asInt(entry[2]);
              final areaId = _asInt(entry[3]);

              final key = '$x,$y,$areaId';
              if (seen.contains(key)) continue;
              seen.add(key);

              final dx = (x - cx).toDouble();
              final dy = (y - cy).toDouble();

              found.add(NpcTarget(
                x: x, y: y, kid: source.kingdomId,
                type: type, areaId: areaId, uiLevel: uiLevel,
                sourceAreaId: source.areaId,
                sourceName: source.displayName,
                distanceFromSource: sqrt(dx * dx + dy * dy),
                attacksRemaining: attacks,
              ));
            }
          }
        }
      } catch (e) {
        TrafficLog.add('ER', '[Attack] gaa chunk error: $e');
      }

      done++;
      onProgress?.call(done, chunks.length);
      if (done < chunks.length) {
        await Future.delayed(Duration(milliseconds: 800 + Random().nextInt(400)));
      }
    }

    final npcCount = found.where((t) => t.type == 24).length;
    final goldCount = found.where((t) => t.type == 25).length;
    TrafficLog.add('ST',
        '[Attack] Scan done: ${found.length} targets ($npcCount NPC + $goldCount gold) from ${chunks.length} chunks');
    return found;
  }

  Future<NpcTarget> enrich(NpcTarget target) async {
    await _ensureKingdom(target.kid);

    try {
      final resp = await conn.sendXtAndWait(
        'ssi',
        jsonEncode({'TX': target.x, 'TY': target.y, 'KID': target.kid}),
        responseCmd: 'ssi',
        timeoutMs: 10000,
        isAction: false,
      );

      if (resp.resultCode != 0 || resp.payload == null) return target;

      final data = jsonDecode(resp.payload!) as Map<String, dynamic>;
      final gc = _asInt(data['GC']);

      // ✅ حساب uiLevel من GC لـ type 25
      int newLevel = target.uiLevel;
      if (target.type == 25 && gc >= 40) {
        if (gc >= 75) {
          newLevel = 80;
        } else {
          // round to nearest 10, clamped [40, 80]
          newLevel = ((gc / 10).round() * 10).clamp(40, 80);
        }
      }

      TrafficLog.add('ST',
          '[Attack] ssi (${target.x},${target.y}) type=${target.type} '
          'GC=$gc AS=${data['AS']} Lv=$newLevel attacks=${target.attacksRemaining}');

      return target.copyWith(
        goldCampValue: gc,
        uiLevel: newLevel,
        lastEnrichedAt: DateTime.now(),
      );
    } catch (e) {
      TrafficLog.add('ER', '[Attack] ssi error: $e');
      return target;
    }
  }

  Future<NpcAttackResult> attack({
    required NpcTarget target,
    required OwnedCastle source,
    required List<List<int>> units,
    required int lordId,
  }) async {
    if (units.isEmpty) return NpcAttackResult.fail('NO_UNITS');
    if (units.length > 10) return NpcAttackResult.fail('TOO_MANY_UNIT_TYPES');

    if (source.kingdomId != target.kid) {
      return NpcAttackResult.fail('CROSS_KINGDOM');
    }

    await _ensureKingdom(target.kid);

    try {
      final adiResp = await conn.sendXtAndWait(
        'adi',
        jsonEncode({
          'SX': source.x, 'SY': source.y,
          'TX': target.x, 'TY': target.y, 'KID': target.kid,
        }),
        responseCmd: 'adi',
        timeoutMs: 10000,
        isAction: false,
      );
      if (adiResp.resultCode != 0) {
        TrafficLog.add('ST',
            '[Attack] adi result=${adiResp.resultCode} (proceeding)');
      }
    } catch (e) {
      TrafficLog.add('ST', '[Attack] adi skipped: $e');
    }

    try {
      final payload = _buildCraPayload(
        sx: source.x, sy: source.y,
        tx: target.x, ty: target.y,
        kid: target.kid, lid: lordId, units: units,
      );

      final totalUnits = units.fold<int>(0, (s, e) => s + e[1]);
      TrafficLog.add('ST',
          '[CRA] → (${target.x},${target.y}) Lv${target.uiLevel} '
          'type=${target.type} units=${jsonEncode(units)} LID=$lordId');

      final resp = await conn.sendXtAndWait(
        'cra',
        jsonEncode(payload),
        responseCmd: 'cra',
        timeoutMs: 25000,
        isAction: true,
      );

      TrafficLog.add('ST',
          '[CRA-RESP] result=${resp.resultCode} payload=${resp.payload ?? "null"}');

      if (resp.resultCode == 0) {
        final mid = _extractMid(resp.payload);
        return NpcAttackResult.ok(mid ?? -1, target, totalUnits);
      }

      if (resp.resultCode == 100) {
        final ms = _extractMs(resp.payload);
        return NpcAttackResult.fail(
            'CRA_100: ${ms != null ? "MS=$ms (جرب جيش أكبر)" : "unknown"}');
      }

      if (resp.resultCode == 91) return NpcAttackResult.fail('UNIT_NOT_SENDABLE_91');
      if (resp.resultCode == 218) return NpcAttackResult.fail('LORD_BUSY_218');
      if (resp.resultCode == 181) return NpcAttackResult.fail('MAX_MOVEMENTS_181');
      if ([219, 222, 256, 404].contains(resp.resultCode)) {
        return NpcAttackResult.fail('LORD_UNAVAILABLE');
      }

      return NpcAttackResult.fail(
          'CRA error ${resp.resultCode}: ${resp.payload ?? errorName(resp.resultCode)}');
    } catch (e) {
      TrafficLog.add('ER', '[CRA] exception: $e');
      return NpcAttackResult.fail('$e');
    }
  }

  Map<String, dynamic> _buildCraPayload({
    required int sx, sy, tx, ty, kid, lid,
    required List<List<int>> units,
  }) {
    List<List<int>> fill(List<List<int>> u, int count) {
      final r = <List<int>>[];
      for (int i = 0; i < count; i++) {
        r.add(i < u.length ? u[i] : [-1, 0]);
      }
      return r;
    }

    final m = units.take(6).toList();
    final l = units.skip(6).take(2).toList();
    final r = units.skip(8).take(2).toList();

    return {
      'SX': sx, 'SY': sy, 'TX': tx, 'TY': ty, 'KID': kid,
      'LID': lid, 'WT': 0, 'HBW': -1, 'BPC': 0, 'ATT': 0, 'AV': 0,
      'LP': 0, 'FC': 0, 'PTT': 0, 'SD': 0, 'ICA': 0, 'CD': 99,
      'A': [{
        'L': {'T': List.generate(2, (_) => [-1, 0]), 'U': fill(l, 2)},
        'R': {'T': List.generate(2, (_) => [-1, 0]), 'U': fill(r, 2)},
        'M': {'T': List.generate(6, (_) => [-1, 0]), 'U': fill(m, 6)},
      }],
      'BKS': [],
      'AST': [-1, -1, -1],
      'RW': List.generate(8, (_) => [-1, 0]),
      'ASCT': 0,
    };
  }

  int? _extractMs(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final ms = data['MS'];
      if (ms is int) return ms;
      if (ms is num) return ms.toInt();
    } catch (_) {}
    return null;
  }

  int? _extractMid(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final candidates = <dynamic>[
        data['MID'],
        data['MS'],
        (data['A'] as Map?)?['M'] != null
            ? ((data['A'] as Map)['M'] as Map)['MID']
            : null,
      ];
      for (final c in candidates) {
        if (c is int) return c;
        if (c is num) return c.toInt();
        if (c is String) return int.tryParse(c);
      }
    } catch (_) {}
    return null;
  }

  static int _asInt(dynamic v, [int def = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? def;
    return def;
  }
}