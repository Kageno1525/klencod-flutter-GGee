import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../gge_client.dart';
import '../models.dart';
import 'samurai_service.dart';

class SamuraiAutoStatusEntry {
  final DateTime at;
  final String message;
  SamuraiAutoStatusEntry(this.at, this.message);
}

class SamuraiAutoService {
  static final SamuraiAutoService instance = SamuraiAutoService._();
  SamuraiAutoService._();

  // ═══ Keys ═══
  static const _kEnabled = 'samurai_auto_enabled';
  static const _kSourceAreaId = 'samurai_auto_source_area';
  static const _kSourceKid = 'samurai_auto_source_kid';
  static const _kSourceX = 'samurai_auto_source_x';
  static const _kSourceY = 'samurai_auto_source_y';
  static const _kMinUnits = 'samurai_auto_min_units';
  static const _kCommanderIds = 'samurai_auto_commander_ids';
  static const _kToolId = 'samurai_auto_tool_id';
  static const _kToolL = 'samurai_auto_tool_l';
  static const _kToolR = 'samurai_auto_tool_r';
  static const _kToolM = 'samurai_auto_tool_m';
  static const _kWaves = 'samurai_auto_waves';
  static const _kMaxLevel = 'samurai_auto_max_level';
  static const _kSkipDaimyo = 'samurai_auto_skip_daimyo';
  static const _kDelayMin = 'samurai_auto_delay_min';
  static const _kDelayMax = 'samurai_auto_delay_max';
  static const _kMaxAttacksDay = 'samurai_auto_max_attacks_day';
  static const _kAttacksToday = 'samurai_auto_attacks_today';
  static const _kAttacksDate = 'samurai_auto_attacks_date';
  static const _kCooldowns = 'samurai_cooldowns_v1';
  static const _kFailedCamps = 'samurai_auto_failed_camps';
  static const _kLastScan = 'samurai_auto_last_scan';

  static const int kDefMinUnits = 30;
  static const int kDefToolId = 166;
  static const int kDefToolL = 20;
  static const int kDefToolR = 20;
  static const int kDefToolM = 30;
  static const int kDefWaves = 3;
  static const int kDefMaxLevel = 60;
  static const int kDefDelayMin = 10;
  static const int kDefDelayMax = 15;
  static const int kDefMaxAttacksDay = 0;

  // ✅ radius البحث (5 تيلز)
  static const int kCampsScanRadius = 5;
  // ✅ كل 5 دقايق يعيد البحث
  static const int kCampsScanCacheMin = 5;
  static const int kFailedCampCooldownMin = 30;
  // ⚠️ لم يعد مستخدمًا
  static const int kSuccessCooldownMin = 5;

  static const Set<int> kDefensiveWodIds = {1, 2, 3, 4, 5, 6, 7, 8};

  // ═══ State ═══
  final ValueNotifier<String> statusNotifier = ValueNotifier('Idle');
  final List<SamuraiAutoStatusEntry> _history = [];
  List<SamuraiAutoStatusEntry> get statusHistory => List.unmodifiable(_history);

  int attacksThisSession = 0;
  int campsScanned = 0;

  Timer? _timer;
  bool _running = false;
  SamuraiService? _svc;
  GgeClient? _client;

  List<SamuraiCamp> _camps = [];
  List<SamuraiCamp> get camps => List.unmodifiable(_camps);

  final Map<String, DateTime> _cooldowns = {};
  final Map<String, DateTime> _failedCamps = {};

  Future<void>? _activeTick;
  final Set<String> _attackedThisTick = {};

  bool get isRunning => _running;

  // ═══ Config ═══
  Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;

  Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, v);
    TrafficLog.add('ST', '[Samurai-Auto] enabled=$v');
  }

  Future<void> setSource({
    required int areaId, required int kid,
    required int x, required int y,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kSourceAreaId, areaId);
    await p.setInt(_kSourceKid, kid);
    await p.setInt(_kSourceX, x);
    await p.setInt(_kSourceY, y);
    TrafficLog.add('ST', '[Samurai-Auto] source: area=$areaId kid=$kid ($x,$y)');
  }

  Future<int> getMinUnits() async =>
      (await SharedPreferences.getInstance()).getInt(_kMinUnits) ?? kDefMinUnits;

  Future<void> setMinUnits(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kMinUnits, v);
  }

  Future<List<int>> getCommanderIds() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kCommanderIds) ?? [];
    return raw.map((s) => int.tryParse(s) ?? 0).where((i) => i > 0).toList();
  }

  Future<void> setCommanderIds(List<int> ids) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kCommanderIds, ids.map((e) => e.toString()).toList());
    TrafficLog.add('ST', '[Samurai-Auto] cmds: $ids');
  }

  Future<int> getToolId() async =>
      (await SharedPreferences.getInstance()).getInt(_kToolId) ?? kDefToolId;

  Future<int> getToolL() async =>
      (await SharedPreferences.getInstance()).getInt(_kToolL) ?? kDefToolL;

  Future<int> getToolR() async =>
      (await SharedPreferences.getInstance()).getInt(_kToolR) ?? kDefToolR;

  Future<int> getToolM() async =>
      (await SharedPreferences.getInstance()).getInt(_kToolM) ?? kDefToolM;

  Future<void> setToolAmounts({int? l, int? r, int? m}) async {
    final p = await SharedPreferences.getInstance();
    if (l != null) await p.setInt(_kToolL, l);
    if (r != null) await p.setInt(_kToolR, r);
    if (m != null) await p.setInt(_kToolM, m);
  }

  Future<int> getWaves() async =>
      (await SharedPreferences.getInstance()).getInt(_kWaves) ?? kDefWaves;

  Future<void> setWaves(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kWaves, v.clamp(1, 3));
  }

  Future<int> getMaxLevel() async =>
      (await SharedPreferences.getInstance()).getInt(_kMaxLevel) ?? kDefMaxLevel;

  Future<void> setMaxLevel(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kMaxLevel, v.clamp(1, 100));
  }

  Future<bool> getSkipDaimyo() async =>
      (await SharedPreferences.getInstance()).getBool(_kSkipDaimyo) ?? true;

  Future<void> setSkipDaimyo(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSkipDaimyo, v);
  }

  Future<int> getDelayMin() async =>
      (await SharedPreferences.getInstance()).getInt(_kDelayMin) ?? kDefDelayMin;

  Future<int> getDelayMax() async =>
      (await SharedPreferences.getInstance()).getInt(_kDelayMax) ?? kDefDelayMax;

  Future<void> setDelay({int? min, int? max}) async {
    final p = await SharedPreferences.getInstance();
    if (min != null) await p.setInt(_kDelayMin, min.clamp(5, 120));
    if (max != null) await p.setInt(_kDelayMax, max.clamp(5, 120));
  }

  Future<int> getMaxAttacksDay() async =>
      (await SharedPreferences.getInstance()).getInt(_kMaxAttacksDay) ?? kDefMaxAttacksDay;

  Future<void> setMaxAttacksDay(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kMaxAttacksDay, v.clamp(0, 9999));
  }

  Future<int> getAttacksToday() async {
    final p = await SharedPreferences.getInstance();
    final today = _todayStr();
    final savedDate = p.getString(_kAttacksDate) ?? '';
    if (savedDate != today) {
      await p.setInt(_kAttacksToday, 0);
      await p.setString(_kAttacksDate, today);
      return 0;
    }
    return p.getInt(_kAttacksToday) ?? 0;
  }

  String _todayStr() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // ═══ Start / Stop ═══
  Future<void> start(GgeClient client, {int? sourceAreaId}) async {
    if (_running) {
      TrafficLog.add('ST', '[Samurai-Auto] already running');
      return;
    }

    if (_activeTick != null) {
      TrafficLog.add('ST', '[Samurai-Auto] ⏳ waiting for old tick...');
      try { await _activeTick!.timeout(const Duration(seconds: 60)); } catch (_) {}
    }

    _attackedThisTick.clear();
    _client = client;
    _svc = SamuraiService(client);
    await _svc!.loadCooldowns();
    await _loadFailedCamps();
    await _loadCooldowns();

    attacksThisSession = 0;
    campsScanned = 0;

    if (sourceAreaId != null && sourceAreaId > 0) {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kSourceAreaId, sourceAreaId);
    }

    _running = true;
    _setStatus('🚀 Started');
    TrafficLog.add('ST', '[Samurai-Auto] 🚀 Started');
    _tick();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    _setStatus('🛑 Stopped');
    TrafficLog.add('ST', '[Samurai-Auto] 🛑 Stopped');
  }

  void _setStatus(String s) {
    statusNotifier.value = s;
    _history.add(SamuraiAutoStatusEntry(DateTime.now(), s));
    if (_history.length > 200) _history.removeAt(0);
    TrafficLog.add('ST', '[Samurai-Auto] $s');
  }

  // ═══ Persistence ═══
  Future<void> _loadCooldowns() async {
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

  Future<void> _loadFailedCamps() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kFailedCamps);
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final now = DateTime.now();
      _failedCamps.clear();
      for (final e in data.entries) {
        final dt = DateTime.tryParse(e.value as String);
        if (dt != null && dt.isAfter(now)) _failedCamps[e.key] = dt;
      }
    } catch (_) {}
  }

  Future<void> _saveFailedCamps() async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final data = <String, String>{};
    for (final e in _failedCamps.entries) {
      if (e.value.isAfter(now)) data[e.key] = e.value.toIso8601String();
    }
    await p.setString(_kFailedCamps, jsonEncode(data));
  }

  /// 🧹 امسح كل الـ state (cooldowns + failedCamps)
  /// استخدمها لو كل الأبراج بقت blocked ومش عايز تستنى
  Future<void> clearAllState() async {
    _cooldowns.clear();
    _failedCamps.clear();
    _attackedThisTick.clear();
    final p = await SharedPreferences.getInstance();
    await p.remove(_kFailedCamps);
    await p.remove(_kCooldowns);
    TrafficLog.add('ST',
        '[Samurai-Auto] 🧹 All state cleared (cooldowns + failedCamps)');
    _setStatus('🧹 State cleared');
  }

  // ═══ Tick ═══
  Future<void> _tick() async {
    if (!_running) return;
    if (_activeTick != null) return;
    _activeTick = _doTick();
    try {
      await _activeTick;
    } catch (e) {
      TrafficLog.add('ER', '[Samurai-Auto] tick error: $e');
    } finally {
      _activeTick = null;
    }
  }

  Future<void> _doTick() async {
    if (!await isEnabled()) {
      _setStatus('⏸️ Disabled');
      return;
    }
    if (_client == null || _svc == null) return;

    const initialStatus = '⏱️ Checking...';
    _setStatus(initialStatus);
    _attackedThisTick.clear();

    try {
      await _maybeRescan();
      if (!_running) return;
      await _tryAttackCamps();

      if (_running && statusNotifier.value == initialStatus) {
        _setStatus('💤 Idle · ⏱ 30s');
      }
    } catch (e) {
      _setStatus('❌ Error: $e');
    }
  }

  // ═══ Scan ═══
  Future<void> _maybeRescan() async {
    if (_client == null || _svc == null) return;

    final p = await SharedPreferences.getInstance();
    final lastStr = p.getString(_kLastScan);
    if (lastStr != null) {
      final last = DateTime.tryParse(lastStr);
      if (last != null &&
          DateTime.now().difference(last).inMinutes < kCampsScanCacheMin &&
          _camps.isNotEmpty) {
        return;
      }
    }

    final srcArea = p.getInt(_kSourceAreaId) ?? 0;
    if (srcArea == 0) {
      _setStatus('❌ No source area');
      return;
    }

    try {
      final castles = await _client!.getCastles();
      OwnedCastle? source;
      for (final c in castles) {
        if (c.areaId == srcArea) source = c;
      }
      if (source == null) {
        _setStatus('❌ Source castle not found');
        return;
      }

      final maxLevel = p.getInt(_kMaxLevel) ?? kDefMaxLevel;
      final skipDaimyo = p.getBool(_kSkipDaimyo) ?? true;

      _setStatus('🔍 Scanning camps...');
      _camps = await _svc!.scanArea(
        source: source,
        radiusTiles: kCampsScanRadius,
        maxLevel: maxLevel,
        skipPlayerCamps: true,
        includeDaimyo: !skipDaimyo,
        onProgress: (d, t) {
          if (_running) _setStatus('🔍 Scanning $d/$t · ${_camps.length}');
        },
      );
      campsScanned = _camps.length;
      await p.setString(_kLastScan, DateTime.now().toIso8601String());
      _setStatus('✓ Found ${_camps.length} camps');
    } catch (e) {
      _setStatus('❌ Scan error: $e');
    }
  }

  // ═══ Attack Loop ═══
  Future<void> _tryAttackCamps() async {
    if (_client == null || _svc == null) return;

    const int safetyMaxAttacks = 100;
    const int maxFailStreak = 10;

    final p = await SharedPreferences.getInstance();
    final srcArea = p.getInt(_kSourceAreaId) ?? 0;
    if (srcArea == 0) return;

    final minUnits = p.getInt(_kMinUnits) ?? kDefMinUnits;
    final maxAttacksDay = p.getInt(_kMaxAttacksDay) ?? kDefMaxAttacksDay;
    final selectedCmds = await getCommanderIds();
    final skipDaimyo = p.getBool(_kSkipDaimyo) ?? true;

    final attacksToday = await getAttacksToday();
    if (maxAttacksDay > 0 && attacksToday >= maxAttacksDay) {
      _setStatus('🛑 Daily limit ($attacksToday/$maxAttacksDay)');
      return;
    }

    try {
      int attacksThisTick = 0;
      int failStreak = 0;

      // ─── بناء pool قابل للاستخدام (shuffled round-robin) ───
      List<SamuraiCamp> buildPool() {
        final now = DateTime.now();
        return _camps
            .where((c) => !c.isDead)
            .where((c) => !c.isPlayerCamp)
            .where((c) => !(skipDaimyo && c.isDaimyoCastle))
            .where((c) {
              final fail = _failedCamps[c.key];
              return fail == null || !fail.isAfter(now);
            })
            .toList()
          ..shuffle();
      }

      var pool = buildPool();
      TrafficLog.add('ST',
          '[Samurai-Auto] 🎯 Pool: ${pool.length}/${_camps.length} camps usable');
      if (pool.isEmpty) {
        _setStatus('⏳ All camps blocked — clear state or wait');
        return;
      }

      while (_running && attacksThisTick < safetyMaxAttacks) {
        // ─── 🔄 REFRESH units + lords ───
        final castles = await _client!.getCastles();
        OwnedCastle? source;
        for (final c in castles) {
          if (c.areaId == srcArea) source = c;
        }
        if (source == null) {
          _setStatus('❌ Source castle not found');
          return;
        }

        final catalog = await _client!.loadCatalog();
        final freshUnits = await _client!.getCastleUnits(
            source.kingdomId, source.areaId, catalog);
        final sendable = freshUnits
            .where((u) => _isOffensiveUnit(u) && u.amount > 0)
            .toList();
        final totalUnits = sendable.fold<int>(0, (s, u) => s + u.amount);

        // ═══ STOP: الجنود خلصت ═══
        if (totalUnits < minUnits) {
          _setStatus('💤 Idle — units: $totalUnits (< $minUnits)');
          if (attacksThisTick > 0) {
            TrafficLog.add('ST',
                '[Samurai-Auto] ✅ Done $attacksThisTick attacks — units ran out');
          }
          return;
        }

        final cmds = await _client!.getCommanders();
        var freeLords = cmds.where((c) => !c.isBusy).toList();
        if (selectedCmds.isNotEmpty) {
          freeLords = freeLords
              .where((c) => selectedCmds.contains(c.lord.id))
              .toList();
        }

        // ═══ STOP: كل القواد مشغولين ═══
        if (freeLords.isEmpty) {
          _setStatus('💤 Idle — no free commanders');
          if (attacksThisTick > 0) {
            TrafficLog.add('ST',
                '[Samurai-Auto] ✅ Done $attacksThisTick attacks — all lords busy');
          }
          return;
        }

        // ─── pool فضي؟ اعمله rebuild (round-robin) ───
        if (pool.isEmpty) {
          pool = buildPool();
          if (pool.isEmpty) {
            _setStatus('⏳ All camps blocked — waiting next cycle');
            if (attacksThisTick > 0) {
              TrafficLog.add('ST',
                  '[Samurai-Auto] ✅ Done $attacksThisTick attacks — no targets');
            }
            return;
          }
          TrafficLog.add('ST',
              '[Samurai-Auto] 🔄 New round: ${pool.length} camps');
        }

        // ─── اسحب camp من الـ pool ───
        final camp = pool.removeAt(0);

        final config = SamuraiAttackConfig(
          waves: await getWaves(),
          toolId: await getToolId(),
          toolL: await getToolL(),
          toolR: await getToolR(),
          toolM: await getToolM(),
          attackDaimyoCastles: !skipDaimyo,
        );

        // ─── محاولة الهجوم ───
        bool attacked = false;
        for (final lordInfo in freeLords) {
          _setStatus(
              '⚔️ ${camp.coordsLabel} · L${lordInfo.lord.id} '
              '(#${attacksThisTick + 1})');

          final result = await _svc!.attack(
            camp: camp,
            source: source,
            lordId: lordInfo.lord.id,
            fallbackLords: null,
            availableUnits: sendable,
            allUnitsForTools: freshUnits,
            config: config,
            markCooldownAfterSuccess: false,
          );

          // ═══ نجح ═══
          if (result.success) {
            attacksThisTick++;
            attacksThisSession++;
            await _incrementAttacksToday();
            failStreak = 0;
            TrafficLog.add('ST',
                '[Samurai-Auto] ✅ HIT ${camp.coordsLabel} '
                'units=${result.totalUnits} (#$attacksThisTick)');
            _setStatus('✅ Hit ${camp.coordsLabel}! (#$attacksThisTick)');

            // فاصل 3-5 ثواني
            final gapMs = 3000 + Random().nextInt(2000);
            TrafficLog.add('ST',
                '[Samurai-Auto] ⏱ gap ${gapMs}ms');
            await Future.delayed(Duration(milliseconds: gapMs));
            if (!_running) return;
            attacked = true;
            break;
          }

          // ═══ فشل ═══
          final err = result.error ?? '';

          // لورد مشغول → جرّب لورد تاني على نفس الـ camp
          if (err.contains('256') ||
              err.contains('218') ||
              err.contains('LORD_BUSY')) {
            continue;
          }

          // رفض نهائي → احجبه (ساعتين)
          if (err.contains('CRA 6') || err.contains('TARGET_REJECTED')) {
            _failedCamps[camp.key] =
                DateTime.now().add(const Duration(hours: 2));
            await _saveFailedCamps();
            TrafficLog.add('ER',
                '[Samurai-Auto] ⛔ ${camp.coordsLabel}: $err (blocked 2h)');
            break;
          }

          // أي فشل تاني → سجله بس متحجبهوش (هيرجع للـ pool تاني)
          TrafficLog.add('ER',
              '[Samurai-Auto] ❌ ${camp.coordsLabel}: $err (will retry)');
          break;
        }

        if (!attacked) {
          failStreak++;
          TrafficLog.add('ST',
              '[Samurai-Auto] ⚠️ fail streak: $failStreak/$maxFailStreak');
          if (failStreak >= maxFailStreak) {
            _setStatus('🛑 Too many failures — waiting next cycle');
            return;
          }
          await Future.delayed(const Duration(seconds: 3));
        }
      }

      if (attacksThisTick >= safetyMaxAttacks) {
        TrafficLog.add('ST',
            '[Samurai-Auto] ⚠️ Safety limit ($safetyMaxAttacks) reached');
      }
    } catch (e) {
      _setStatus('❌ Attack loop error: $e');
    }
  }

  bool _isOffensiveUnit(CastleUnit u) {
    if (kDefensiveWodIds.contains(u.wodId)) return false;
    if (u.info?.fightType != null) return u.info!.fightType == 0;
    return u.info?.role == 'melee' || u.info?.role == 'ranged';
  }

  Future<void> _incrementAttacksToday() async {
    final p = await SharedPreferences.getInstance();
    final today = _todayStr();
    final savedDate = p.getString(_kAttacksDate) ?? '';
    if (savedDate != today) {
      await p.setInt(_kAttacksToday, 1);
      await p.setString(_kAttacksDate, today);
    } else {
      final current = p.getInt(_kAttacksToday) ?? 0;
      await p.setInt(_kAttacksToday, current + 1);
    }
  }
}