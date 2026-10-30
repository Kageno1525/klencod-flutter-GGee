import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/io.dart';
import 'models.dart';
import 'services/alliance_service.dart';
import 'services/castle_service.dart';
import 'services/catalog_service.dart';
import 'services/commanders_service.dart';
import 'services/smuggle_service.dart';
import 'services/training_service.dart';
import 'services/transfer_service.dart';

class TransferResult {
  final bool success;
  final String? error;
  final int? movementId;
  TransferResult._(this.success, this.error, [this.movementId]);
  factory TransferResult.ok([int? movementId]) =>
      TransferResult._(true, null, movementId);
  factory TransferResult.fail(String err) => TransferResult._(false, err);
}

// ═══════════════════════════════════════════════════════════
//  LOG SYSTEM (with categories)
// ═══════════════════════════════════════════════════════════
enum LogCategory {
  all, login, smuggle, attack, desert, defense, spy, gam, general, errors;

  String get label {
    switch (this) {
      case LogCategory.all: return 'الكل';
      case LogCategory.login: return 'Login';
      case LogCategory.smuggle: return 'Smuggle';
      case LogCategory.attack: return 'Attack';
      case LogCategory.desert: return 'Desert';
      case LogCategory.defense: return 'Defense';
      case LogCategory.spy: return 'Spy';
      case LogCategory.gam: return 'GAM';
      case LogCategory.general: return 'General';
      case LogCategory.errors: return 'Errors';
    }
  }
}

class LogEntry {
  final DateTime at;
  final String dir;
  final String text;
  final LogCategory category;

  LogEntry({
    required this.at, required this.dir,
    required this.text, required this.category,
  });

  String get timestamp =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}.'
      '${at.millisecond.toString().padLeft(3, '0')}';

  String get line => '[$timestamp] [$dir] $text';
}

class TrafficLog {
  TrafficLog._();
  static final List<LogEntry> _entries = [];
  static final StreamController<LogEntry> _ctrl = StreamController.broadcast();
  static const int maxEntries = 3000;

  static List<String> get entries => _entries.map((e) => e.line).toList();
  static Stream<String> get stream => _ctrl.stream.map((e) => e.line);

  static List<LogEntry> get logEntries => List.unmodifiable(_entries);
  static Stream<LogEntry> get entryStream => _ctrl.stream;

  static void add(String dir, String text) {
    if (text.isEmpty) return;
    final entry = LogEntry(
      at: DateTime.now(),
      dir: dir,
      text: text,
      category: _detectCategory(dir, text),
    );
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    if (!_ctrl.isClosed) _ctrl.add(entry);
  }

  static void clear() {
    _entries.clear();
    if (!_ctrl.isClosed) {
      _ctrl.add(LogEntry(
        at: DateTime.now(), dir: 'ST', text: '─── LOG CLEARED ───',
        category: LogCategory.general,
      ));
    }
  }

  static void clearCategory(LogCategory cat) {
    _entries.removeWhere((e) => e.category == cat);
    if (!_ctrl.isClosed) {
      _ctrl.add(LogEntry(
        at: DateTime.now(), dir: 'ST', text: '─── ${cat.label} CLEARED ───',
        category: LogCategory.general,
      ));
    }
  }

  static String dump() {
    final buf = StringBuffer();
    buf.writeln('═══ GGE Traffic Log ═══');
    buf.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buf.writeln('Total entries: ${_entries.length}');
    buf.writeln('═══════════════════════');
    buf.writeln();
    for (final e in _entries) buf.writeln(e.line);
    return buf.toString();
  }

  static LogCategory _detectCategory(String dir, String text) {
    if (dir == 'ER') return LogCategory.errors;
    final l = text.toLowerCase();

    if (l.contains('verchk') || l.contains('apiok') || l.contains('rlu') ||
        l.contains('joinok') || l.contains('lli') || l.contains('gbd') ||
        l.contains('login') || l.contains('token') || l.contains('websocket') ||
        l.contains('auto-reconnect') || l.contains('reconnect') ||
        l.contains('init sequence') || l.contains('connected') ||
        l.contains('opening') || l.contains('handshake')) {
      return LogCategory.login;
    }
    if (l.contains('[desert') || l.contains('desert-auto') ||
        l.contains('desert-attack')) {
      return LogCategory.desert;
    }
    if (l.contains('[smuggle]') || l.contains('%cds%') || l.contains('cds ')) {
      return LogCategory.smuggle;
    }
    if (l.contains('[attack') || l.contains('%cra%') || l.contains('cra ')) {
      return LogCategory.attack;
    }
    if (l.contains('[defense') || l.contains('[auto') ||
        l.contains('evac') || l.contains('recall')) {
      return LogCategory.defense;
    }
    if (l.contains('%csm%') || l.contains('%bsd%') || l.contains('%mmr%') ||
        l.contains('%sne%') || l.contains('spy')) {
      return LogCategory.spy;
    }
    if (l.contains('%gam%') || l.contains('%mrm%') ||
        l.contains('incoming attack') || l.contains('attack from')) {
      return LogCategory.gam;
    }
    return LogCategory.general;
  }
}

// ═══════════════════════════════════════════════════════════
class GgeClient {
  static GgeClient? _instance;
  factory GgeClient() => _instance ??= GgeClient._internal();

  static bool allowBackgroundReconnect = false;

  IOWebSocketChannel? _channel;
  StreamSubscription? _sub;

  final StreamController<XtMessage> _xtCtrl = StreamController.broadcast();
  final StreamController<String> _rawCtrl = StreamController.broadcast();
  final StreamController<List<dynamic>> _gamCtrl = StreamController.broadcast();
  final StreamController<AttackAlert> _attackCtrl = StreamController.broadcast();

  Stream<XtMessage> get xtStream => _xtCtrl.stream;
  Stream<String> get rawStream => _rawCtrl.stream;
  Stream<List<dynamic>> get gamStream => _gamCtrl.stream;
  Stream<AttackAlert> get attackStream => _attackCtrl.stream;

  bool _connected = false;
  bool get isConnected => _connected;
  bool get isLoggedIn => _savedToken != null && _savedToken!.isNotEmpty;

  Timer? _pollingTimer;
  int? _cachedAllianceId;
  int? _mainCastleAreaId;
  bool _backgroundPollingActive = false;
  List<AllyMember>? _cachedAllianceMembers;
  bool _gbdReceived = false;
  Map<int, UnitCatalogEntry>? _cachedCatalog;
  DateTime _lastActionTime = DateTime.now();
  String? _savedToken;
  bool _disposed = false;
  bool _reconnecting = false;
  bool _appForeground = true;
  DateTime? _lastRxTime;
  bool _networkWaitActive = false;

  int? _cachedPlayerId;
  final Map<int, AttackAlert> _latestAlertByMid = {};

  final Set<int> _unlockedUnitIds = {};
  Set<int> get unlockedUnitIds => _unlockedUnitIds;

  final Map<int, Set<int>> _unlockedByAreaId = {};
  Set<int> getUnlockedForArea(int areaId) =>
      _unlockedByAreaId[areaId] ?? const <int>{};

  final Map<int, int> _barracksLevelByCastle = {};
  int? getBarracksLevel(int areaId) => _barracksLevelByCastle[areaId];

  Map<int, CastleStats>? _cachedStatsByArea;
  Map<int, CastleStats>? get cachedStatsByArea => _cachedStatsByArea;
  set cachedStatsByArea(Map<int, CastleStats>? v) => _cachedStatsByArea = v;

  void Function()? onSessionConflict;

  final List<String> debugLog = [];
  void Function()? onLog;
  void Function(String)? onStatus;

  static const int _maxPlausibleAllianceId = 10000000;
  static const String _gameUrl =
      'ep-live-mz-sa1-ae1-eg1-arab1-game.goodgamestudios.com';
  static const String _gameServer = 'EmpireEx_34';

  static bool _isPlausibleAllianceId(int? aid) =>
      aid != null && aid > 0 && aid < _maxPlausibleAllianceId;

  late final CastleService castleService = CastleService(this);
  late final AllianceService allianceService = AllianceService(this);
  late final CatalogService catalogService = CatalogService();
  late final CommandersService commandersService = CommandersService(this);
  late final SmuggleService smuggleService =
      SmuggleService(this, commandersService);
  late final TrainingService trainingService = TrainingService(this);
  late final TransferService transferService =
      TransferService(this, commandersService);

  int? get cachedAllianceId => _cachedAllianceId;
  set cachedAllianceId(int? v) => _cachedAllianceId = v;

  List<AllyMember>? get cachedAllianceMembers => _cachedAllianceMembers;
  set cachedAllianceMembers(List<AllyMember>? v) => _cachedAllianceMembers = v;

  bool get gbdReceived => _gbdReceived;
  int? get mainCastleAreaId => _mainCastleAreaId;

  int? get cachedPlayerId => _cachedPlayerId;
  set cachedPlayerId(int? v) => _cachedPlayerId = v;

  GgeClient._internal() {
    TrafficLog.add('ST', '🟢 GgeClient initialized');
    xtStream.listen(_handleXt);
  }

  void _handleXt(XtMessage msg) {
    if (msg.command == 'gbd') {
      TrafficLog.add('ST',
          '📥 gbd received (payload=${msg.payload?.length ?? 0} chars)');
      _gbdReceived = true;
      if (msg.payload == null) {
        TrafficLog.add('ER', 'gbd has null payload');
        return;
      }
      try {
        final data = jsonDecode(msg.payload!) as Map<String, dynamic>;

        final gpi = data['gpi'];
        if (gpi is Map) {
          final pid = _asIntOrNull(gpi['PID']);
          if (pid != null && pid > 0) {
            _cachedPlayerId = pid;
            TrafficLog.add('ST', '✅ PID from gbd.gpi: $pid');
          }
        }

        final gal = data['gal'];
        if (gal is Map) {
          final aid = _asIntOrNull(gal['AID']);
          if (_isPlausibleAllianceId(aid)) {
            _cachedAllianceId = aid;
            TrafficLog.add('ST', '✅ AID from gbd.gal: $aid');
          }
        }

        final ain = data['ain'];
        if (ain is Map) {
          final a = ain['A'];
          if (a is Map) {
            final aid = _asIntOrNull(a['AID']);
            if (_isPlausibleAllianceId(aid)) {
              _cachedAllianceId = aid;
            }
            final members = a['M'];
            if (members is List) {
              _cachedAllianceMembers = _parseAllyMembers(members);
              TrafficLog.add('ST',
                  '✅ Cached ${_cachedAllianceMembers!.length} members from gbd.ain');
            }
          }
        }

        final gpc = data['gpc'];
        if (gpc is Map) {
          final areas = gpc['A'] as List?;
          if (areas != null) {
            _unlockedUnitIds.clear();
            _unlockedByAreaId.clear();
            for (final area in areas) {
              if (area is! Map) continue;
              final u = area['U'];
              if (u is! Map) continue;
              final aid = _asInt(area['AID']);
              final areaSet = <int>{};

              final unlockedU = u['U'] as List?;
              if (unlockedU != null) {
                for (final id in unlockedU) {
                  final wod = _asIntOrNull(id);
                  if (wod != null && wod > 0) {
                    _unlockedUnitIds.add(wod);
                    areaSet.add(wod);
                  }
                }
              }

              final unlockedL = u['L'] as List?;
              if (unlockedL != null) {
                for (final id in unlockedL) {
                  final wod = _asIntOrNull(id);
                  if (wod != null && wod > 0) {
                    _unlockedUnitIds.add(wod);
                    areaSet.add(wod);
                  }
                }
              }

              if (aid > 0 && areaSet.isNotEmpty) {
                _unlockedByAreaId[aid] = areaSet;
              }
            }
          }
          TrafficLog.add(
              'ST',
              '✅ Unlocked units from gpc: ${_unlockedUnitIds.length} total, '
              '${_unlockedByAreaId.length} areas tracked');
        }
      } catch (e) {
        TrafficLog.add('ER', '❌ gbd parse error: $e');
      }
      return;
    }

    if (msg.command == 'jaa' && msg.payload != null) {
      try {
        final data = jsonDecode(msg.payload!) as Map<String, dynamic>;
        final gca = data['gca'];
        if (gca is Map) {
          final a = gca['A'] as List?;
          if (a != null && a.length >= 4) {
            final areaId = _asInt(a[3]);
            final bg = gca['BG'] as List?;
            if (bg != null) {
              for (final b in bg) {
                if (b is List && b.length >= 2) {
                  if (_asInt(b[0]) == 200) {
                    final level = _asInt(b[1]);
                    _barracksLevelByCastle[areaId] = level;
                    TrafficLog.add('ST',
                        '✅ Barracks Level: $level (Area: $areaId)');
                    break;
                  }
                }
              }
            }
          }
        }

        int? aid;
        if (gca is Map) {
          final o = gca['O'] as Map?;
          aid = _asIntOrNull(o?['AID']);
        }
        if (_isPlausibleAllianceId(aid) && _cachedAllianceId != aid) {
          _cachedAllianceId = aid;
        }
      } catch (e) {
        TrafficLog.add('ER', 'jaa parse error: $e');
      }
    }

    if (msg.command == 'slt' && msg.payload != null) {
      try {
        final data = jsonDecode(msg.payload!) as Map<String, dynamic>;
        final lt = _asString(data['LT']);
        if (lt != null && lt.isNotEmpty) {
          _savedToken = lt;
          AppStorage.setToken(lt);
          TrafficLog.add('ST', 'Token saved automatically');
        }
      } catch (_) {}
    }

    if (msg.command == 'gam' && msg.payload != null) {
      try {
        final data = jsonDecode(msg.payload!) as Map<String, dynamic>;
        final moves = data['M'] as List? ?? [];
        if (!_gamCtrl.isClosed) _gamCtrl.add(moves);
        try {
          _processAttacks(data);
        } catch (e) {
          TrafficLog.add('ER', 'Attack process error: $e');
        }
      } catch (_) {}
    }

    if (msg.command == 'gcl' && msg.payload != null) {
      try {
        final data = jsonDecode(msg.payload!) as Map<String, dynamic>;
        final pid = _asIntOrNull(data['PID']);
        if (pid != null && pid > 0 && _cachedPlayerId == null) {
          _cachedPlayerId = pid;
        }
        final castles = data['C'] as List? ?? [];
        for (final k in castles) {
          for (final a in (k['AI'] as List? ?? [])) {
            final ai = a['AI'] as List?;
            if (ai != null && ai.isNotEmpty && ai[0] == 1) {
              _mainCastleAreaId = _asInt(ai[3]);
              break;
            }
          }
        }
      } catch (_) {}
    }

    if (msg.command == 'ain' && msg.payload != null) {
      try {
        final data = jsonDecode(msg.payload!) as Map<String, dynamic>;
        final a = data['A'] as Map?;
        if (a != null) {
          final members = a['M'] as List?;
          if (members != null) {
            _cachedAllianceMembers = _parseAllyMembers(members);
            TrafficLog.add('ST',
                '✅ Cached ${_cachedAllianceMembers!.length} members from ain');
          }
        }
      } catch (_) {}
    }

    if (msg.command == 'mrm' && msg.payload != null) {
      try {
        final data = jsonDecode(msg.payload!) as Map<String, dynamic>;
        final mid = _asInt(data['MID']);
        if (mid <= 0) return;
        final existing = _latestAlertByMid[mid];
        if (existing == null || existing.isCancelled) return;

        final recalled = AttackAlert(
          movementId: existing.movementId,
          attackerId: existing.attackerId,
          attackerName: existing.attackerName,
          attackerAlliance: existing.attackerAlliance,
          attackerCastleName: existing.attackerCastleName,
          attackerAreaId: existing.attackerAreaId,
          attackerX: existing.attackerX,
          attackerY: existing.attackerY,
          targetX: existing.targetX,
          targetY: existing.targetY,
          targetCastleName: existing.targetCastleName,
          targetAreaId: existing.targetAreaId,
          targetPlayerName: existing.targetPlayerName,
          kingdomId: existing.kingdomId,
          totalTime: existing.totalTime,
          paidTime: existing.paidTime,
          units: existing.units,
          receivedAt: existing.receivedAt,
          isAllianceAttack: existing.isAllianceAttack,
          cancelledAt: DateTime.now(),
        );
        _latestAlertByMid[mid] = recalled;
        if (!_attackCtrl.isClosed) _attackCtrl.add(recalled);
        TrafficLog.add('ST',
            '❌ Attack mid=$mid recalled by ${existing.attackerName}');
      } catch (e) {
        TrafficLog.add('ER', 'mrm parse error: $e');
      }
    }
  }

  void _processAttacks(Map<String, dynamic> data) {
    final myPid = _cachedPlayerId;
    if (myPid == null || myPid <= 0) return;

    final owners = <int, Map<String, dynamic>>{};
    for (final o in (data['O'] as List? ?? [])) {
      if (o is Map) {
        owners[_asInt(o['OID'])] = Map<String, dynamic>.from(o);
      }
    }

    final allyIds = <int>{};
    if (_cachedAllianceMembers != null) {
      for (final m in _cachedAllianceMembers!) {
        allyIds.add(m.playerId);
      }
    }

    for (final m in (data['M'] as List? ?? [])) {
      if (m is! Map) continue;
      final mov = m['M'] as Map<String, dynamic>?;
      if (mov == null) continue;

      if (_asInt(mov['T']) != 0) continue;

      final ta = mov['TA'] as List?;
      final sa = mov['SA'] as List?;
      if (ta == null || ta.length < 5) continue;
      if (sa == null || sa.length < 5) continue;

      final targetPid = _asInt(ta[4]);
      final sourcePid = _asInt(sa[4]);

      final isMeAttacked = targetPid == myPid && sourcePid != myPid;
      final isAllyAttacked = !isMeAttacked &&
          allyIds.contains(targetPid) &&
          sourcePid != myPid &&
          !allyIds.contains(sourcePid);
      if (!isMeAttacked && !isAllyAttacked) continue;

      final mid = _asInt(mov['MID']);
      if (mid <= 0) continue;

      final units = <AttackUnit>[];
      final ga = m['GA'] as Map<String, dynamic>?;
      if (ga != null) {
        _extractUnits(ga['L'], 'left', units);
        _extractUnits(ga['M'], 'middle', units);
        _extractUnits(ga['R'], 'right', units);
        _extractUnits(ga['RW'], 'courtyard', units);
      }

      final existing = _latestAlertByMid[mid];

      if (existing != null) {
        if (existing.isCancelled) continue;
        if (units.isEmpty) continue;
        if (existing.units.isNotEmpty) continue;
        TrafficLog.add('ST',
            '🔁 Units arrived for mid=$mid (${units.length} types, ${units.fold<int>(0, (s, u) => s + u.amount)} units)');
      }

      final attacker = owners[sourcePid];
      final attackerName = _asString(attacker?['N']) ??
          (sa.length > 10 ? _asString(sa[10]) : null) ??
          'Unknown';
      final attackerAlliance = _asString(attacker?['AN']);
      final attackerCastleName = sa.length > 10 ? _asString(sa[10]) : null;
      final attackerAreaId = sa.length > 3 ? _asInt(sa[3]) : 0;
      final attackerX = _asInt(sa[1]);
      final attackerY = _asInt(sa[2]);

      final targetCastleName = ta.length > 10 ? _asString(ta[10]) : null;
      final targetAreaId = ta.length > 3 ? _asInt(ta[3]) : 0;

      final targetOwner = owners[targetPid];
      String? targetPlayerName = _asString(targetOwner?['N']);
      if (targetPlayerName == null || targetPlayerName.isEmpty) {
        if (_cachedAllianceMembers != null) {
          for (final ally in _cachedAllianceMembers!) {
            if (ally.playerId == targetPid) {
              targetPlayerName = ally.name;
              break;
            }
          }
        }
      }

      final alert = AttackAlert(
        movementId: mid,
        attackerId: sourcePid,
        attackerName: attackerName,
        attackerAlliance: attackerAlliance,
        attackerCastleName: attackerCastleName,
        attackerAreaId: attackerAreaId,
        attackerX: attackerX,
        attackerY: attackerY,
        targetX: _asInt(ta[1]),
        targetY: _asInt(ta[2]),
        targetCastleName: targetCastleName,
        targetAreaId: targetAreaId,
        targetPlayerName: targetPlayerName,
        kingdomId: _asInt(mov['KID']),
        totalTime: existing?.totalTime ?? _asInt(mov['TT']),
        paidTime: existing?.paidTime ?? _asInt(mov['PT']),
        units: units,
        receivedAt: existing?.receivedAt ?? DateTime.now(),
        isAllianceAttack: isAllyAttacked,
      );

      if (_latestAlertByMid.length >= 30) {
        _latestAlertByMid.remove(_latestAlertByMid.keys.first);
      }
      _latestAlertByMid[mid] = alert;
      if (!_attackCtrl.isClosed) _attackCtrl.add(alert);

      if (existing == null) {
        final tag = isAllyAttacked ? '🛡️ Ally' : '🚨';
        TrafficLog.add('ST',
            '$tag Attack from $attackerName [${attackerAlliance ?? "no ally"}] → ${alert.remainingLabel}');
      }
    }
  }

  void _extractUnits(dynamic arr, String position, List<AttackUnit> out) {
    if (arr is! List) return;
    for (final u in arr) {
      if (u is! List || u.length < 2) continue;
      final id = _asInt(u[0]);
      final amt = _asInt(u[1]);
      if (id > 0 && amt > 0) {
        out.add(AttackUnit(
          wodId: id,
          amount: amt,
          position: position,
          name: _cachedCatalog?[id]?.displayName,
        ));
      }
    }
  }

  List<AllyMember> _parseAllyMembers(List raw) {
    final out = <AllyMember>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final castles = <AllyCastle>[];
      final ap = m['AP'] as List? ?? [];
      for (final p in ap) {
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
        name: _asString(m['N']) ?? 'Unknown',
        level: _asInt(m['L']),
        peaceTimeSeconds: _asInt(m['RPT']),
        castles: castles,
      ));
    }
    return out;
  }

  void _log(String line) {
    debugLog.add(line);
    if (debugLog.length > 500) {
      debugLog.removeRange(0, debugLog.length - 500);
    }
    onLog?.call();
  }

  void _status(String s) {
    debugPrint('[GGE] $s');
    onStatus?.call(s);
    TrafficLog.add('ST', s);
    _log(s);
  }

  void _errorLog(String s) {
    debugPrint('[GGE-ERR] $s');
    TrafficLog.add('ER', s);
    _log(s);
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

  static String? _asString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  void sendXt(String cmd, String payload) => _sendXt(cmd, payload);

  Future<XtMessage> sendXtAndWait(
    String cmd,
    String payload, {
    required String responseCmd,
    int timeoutMs = 30000,
    bool isAction = false,
    bool Function(XtMessage)? predicate,
  }) =>
      _sendXtAndWait(
        cmd,
        payload,
        responseCmd: responseCmd,
        timeoutMs: timeoutMs,
        isAction: isAction,
        predicate: predicate,
      );

  Future<String> sendAndWaitRaw(
    String message,
    bool Function(String) predicate, {
    int timeoutMs = 30000,
    String? debugLabel,
    bool isAction = false,
  }) =>
      _sendAndWaitRaw(
        message,
        predicate,
        timeoutMs: timeoutMs,
        debugLabel: debugLabel,
        isAction: isAction,
      );

  Future<void> _throttle({int baseMs = 5000, bool isAction = true}) async {
    if (!isAction) return;
    final now = DateTime.now();
    final diff = now.difference(_lastActionTime).inMilliseconds;
    if (diff < baseMs) {
      final waitTime = baseMs - diff + Random().nextInt(1500);
      await Future.delayed(Duration(milliseconds: waitTime));
    } else {
      await Future.delayed(Duration(milliseconds: Random().nextInt(1000)));
    }
    _lastActionTime = DateTime.now();
  }

  Future<void> connect() async {
    if (_connected) return;

    _cachedAllianceId = null;
    _cachedAllianceMembers = null;
    _gbdReceived = false;

    _status('Opening WebSocket...');
    final uri = Uri.parse('wss://$_gameUrl/');

    try {
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          'Origin': 'https://empire-html5.goodgamestudios.com',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:158.0) Gecko/20100101 Firefox/158.0',
          'Accept': '*/*',
          'Accept-Language': 'ar,en-US;q=0.9,en;q=0.8',
          'Accept-Encoding': 'gzip, deflate, br',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
          'Sec-Fetch-Dest': 'empty',
          'Sec-Fetch-Mode': 'websocket',
          'Sec-Fetch-Site': 'same-site',
          'Sec-WebSocket-Extensions': 'permessage-deflate',
        },
        connectTimeout: const Duration(seconds: 25),
      );
    } catch (e) {
      _errorLog('WS create failed: $e');
      throw Exception('WebSocket create failed: $e');
    }

    _status('Waiting for handshake...');
    try {
      await _channel!.ready.timeout(const Duration(seconds: 30));
    } catch (e) {
      _errorLog('WS ready failed: $e');
      throw Exception('WebSocket ready failed: $e');
    }

    _connected = true;
    _status('Connected ✓');

    _sub = _channel!.stream.listen(
      (data) => _onMessage(data),
      onDone: () {
        _connected = false;
        _status('Connection closed');
        _scheduleReconnect();
      },
      onError: (e) {
        _connected = false;
        _errorLog('WS error: $e');
        _scheduleReconnect();
      },
    );

    await Future.delayed(const Duration(milliseconds: 500));
  }

  void _onMessage(dynamic data) {
    String text;
    if (data is String) {
      text = data;
    } else if (data is List<int>) {
      try {
        text = utf8.decode(data, allowMalformed: true);
      } catch (_) {
        text = String.fromCharCodes(data);
      }
    } else {
      text = data.toString();
    }

    if (text.isEmpty) return;

    _lastRxTime = DateTime.now();
    TrafficLog.add('RX', text);

    if (text.startsWith('%')) {
      final m = _parseXt(text);
      if (m != null && !_xtCtrl.isClosed) _xtCtrl.add(m);
    }
    if (!_rawCtrl.isClosed) _rawCtrl.add(text);
  }

  XtMessage? _parseXt(String raw) {
    final trimmed = raw.replaceAll(RegExp(r'^%+|%+$'), '');
    final parts = trimmed.split('%');
    if (parts.length < 2 || parts[0] != 'xt') return null;

    int offset = 1;
    if (parts.length > 1 && parts[1].startsWith('EmpireEx_')) {
      offset = 2;
    }
    if (parts.length <= offset) return null;

    final cmd = parts[offset];
    int roomId = -1, result = -1;
    String? payload;
    if (parts.length > offset + 1) {
      roomId = int.tryParse(parts[offset + 1]) ?? -1;
    }
    if (parts.length > offset + 2) {
      result = int.tryParse(parts[offset + 2]) ?? -1;
    }
    if (parts.length > offset + 3) {
      payload = parts.sublist(offset + 3).join('%');
    }

    return XtMessage(cmd, roomId, result, payload, raw);
  }

  void _send(String msg) {
    TrafficLog.add('TX', msg);
    try {
      _channel?.sink.add(msg);
    } catch (e) {
      _errorLog('[TX ERR] $e');
    }
  }

  void _sendXt(String cmd, String payload) =>
      _send('%xt%$_gameServer%$cmd%1%$payload%');

  Future<String> _sendAndWaitRaw(
    String message,
    bool Function(String) predicate, {
    int timeoutMs = 30000,
    String? debugLabel,
    bool isAction = false,
  }) async {
    final completer = Completer<String>();
    late StreamSubscription sub;
    Timer? timer;

    sub = _rawCtrl.stream.listen((m) {
      if (predicate(m) && !completer.isCompleted) {
        timer?.cancel();
        sub.cancel();
        completer.complete(m);
      }
    });

    timer = Timer(Duration(milliseconds: timeoutMs), () {
      if (!completer.isCompleted) {
        sub.cancel();
        _errorLog('Timeout waiting for "${debugLabel ?? "raw"}"');
        completer.completeError(
            TimeoutException('Timeout: ${debugLabel ?? "raw"}'));
      }
    });

    await _throttle(isAction: isAction);
    _send(message);
    return completer.future;
  }

  // ✅✅✅ _sendXtAndWait مع predicate اختياري
  Future<XtMessage> _sendXtAndWait(
    String cmd,
    String payload, {
    required String responseCmd,
    int timeoutMs = 30000,
    bool isAction = false,
    bool Function(XtMessage)? predicate,
  }) async {
    final completer = Completer<XtMessage>();
    late StreamSubscription sub;
    Timer? timer;

    sub = _xtCtrl.stream.listen((m) {
      if (m.command != responseCmd) return;
      // ✅✅✅ فلترة إضافية للردود
      if (predicate != null && !predicate(m)) return;
      if (completer.isCompleted) return;
      timer?.cancel();
      sub.cancel();
      completer.complete(m);
    });

    timer = Timer(Duration(milliseconds: timeoutMs), () {
      if (!completer.isCompleted) {
        sub.cancel();
        _errorLog('Timeout waiting for "$responseCmd"');
        completer.completeError(TimeoutException('Timeout: "$responseCmd"'));
      }
    });

    await _throttle(isAction: isAction);
    _sendXt(cmd, payload);
    return completer.future;
  }

  Future<void> _runInitSequence() async {
    _status('Running init sequence...');

    _sendXt('nch', '');
    await Future.delayed(const Duration(milliseconds: 300));

    _sendXt('gbl', '{}');
    await Future.delayed(const Duration(milliseconds: 300));

    _sendXt('jca', '{"CID":-1,"KID":0}');
    await Future.delayed(const Duration(milliseconds: 800));

    _sendXt('sli', '{}');
    await Future.delayed(const Duration(milliseconds: 200));

    _sendXt('gie', '{}');
    await Future.delayed(const Duration(milliseconds: 200));

    _sendXt('asc', '{}');
    await Future.delayed(const Duration(milliseconds: 200));

    _sendXt('sie', '{}');
    await Future.delayed(const Duration(milliseconds: 200));

    _sendXt('ffi', '{"FIDS":[1]}');

    _status('Init sequence done ✓');
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (!_appForeground && !allowBackgroundReconnect) return;
    if (!isLoggedIn) return;
    if (_networkWaitActive) return;

    Future.delayed(const Duration(seconds: 3), () async {
      if (_disposed || _connected) return;
      if (!_appForeground && !allowBackgroundReconnect) return;
      if (!isLoggedIn) return;

      final hasNet = await _hasInternet();
      if (!hasNet) {
        _status('⚠️ Network lost. Waiting for internet to return...');
        _networkWaitActive = true;
        _waitForNetworkAndReconnect();
      } else {
        _status(
            '🔴 Session conflict detected (are you playing?). Auto-reconnect paused.');
        _status('👉 Tap "Login" to reconnect manually when done.');

        onSessionConflict?.call();
      }
    });
  }

  Future<void> _waitForNetworkAndReconnect() async {
    while (!_disposed && !_connected && isLoggedIn) {
      await Future.delayed(const Duration(seconds: 10));
      if (_disposed || _connected || !isLoggedIn) break;

      final hasNet = await _hasInternet();
      if (!hasNet) continue;

      _status('🔄 Internet restored. Reconnecting...');
      final ok = await autoReconnect();
      if (ok) {
        _networkWaitActive = false;
        _status('✅ Reconnected successfully');
        return;
      } else {
        _networkWaitActive = false;
        _status('❌ Reconnect attempt failed. Please tap "Login" manually.');
        return;
      }
    }
    _networkWaitActive = false;
  }

  void onAppLifecycleChanged(AppLifecycleState state) {
    _appForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      if (!isLoggedIn) return;
      if (!_connected && !_networkWaitActive) {
        _status('App resumed — checking connection...');
        _scheduleReconnect();
      }
    } else {
      _status('App paused');
    }
  }

  Future<void> _closeWebSocket() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _sub = null;
    _connected = false;
  }

  Future<bool> autoReconnect() async {
    if (_reconnecting || _connected || _disposed) return _connected;

    final token = _savedToken ?? await AppStorage.getToken();
    if (token == null || token.isEmpty) {
      _errorLog('Auto-reconnect: no token');
      return false;
    }
    _savedToken = token;

    _reconnecting = true;
    _status('🔄 Auto-reconnecting...');

    for (int attempt = 1; attempt <= 3; attempt++) {
      if (_disposed) {
        _reconnecting = false;
        return false;
      }
      try {
        _status('Reconnect attempt $attempt/3');
        await _closeWebSocket();
        await Future.delayed(const Duration(milliseconds: 500));
        await connect();
        await loginWithToken(token);
        _reconnecting = false;
        _status('✅ Reconnected ✓');
        return true;
      } catch (e) {
        _errorLog('Reconnect $attempt failed: $e');
        if (e.toString().contains('Token expired')) {
          _reconnecting = false;
          _status('❌ Token expired — log in again');
          return false;
        }
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: 2 * attempt));
        }
      }
    }
    _reconnecting = false;
    _errorLog('❌ Auto-reconnect failed after 3 attempts');
    return false;
  }

  Future<void> loginWithToken(String token) async {
    _cachedAllianceId = null;
    _cachedAllianceMembers = null;
    _gbdReceived = false;
    _savedToken = token;

    _status('verChk (token)...');
    await _sendAndWaitRaw(
      '<msg t="sys"><body action="verChk" r="0"><ver v="166" /></body></msg>',
      (m) => m.contains('apiOK'),
      debugLabel: 'apiOK',
    );

    _status('login XML (token)...');
    await _sendAndWaitRaw(
      '<msg t="sys"><body action="login" r="0"><login z="$_gameServer"><nick><![CDATA[]]></nick><pword><![CDATA[undefined%en%0]]></pword></login></body></msg>',
      (m) => m.contains('rlu'),
      debugLabel: 'rlu',
    );

    _status('autoJoin (token)...');
    await _sendAndWaitRaw(
      '<msg t="sys"><body action="autoJoin" r="-1"></body></msg>',
      (m) => m.contains('joinOK'),
      debugLabel: 'joinOK',
    );

    _status('roundTrip + vck (token)...');
    _send('<msg t="sys"><body action="roundTrip" r="1"></body></msg>');
    await Future.delayed(const Duration(milliseconds: 100));
    final rand = Random().nextDouble() * 9e307;
    await _sendXtAndWait(
      'vck',
      'undefined%web-html5%<RoundHouseKick>%${rand.toStringAsExponential(16)}',
      responseCmd: 'vck',
    );

    _status('lli (TOKEN Mode)...');
    final username = await AppStorage.getUsername() ?? '';
    final resp = await _sendXtAndWait(
      'lli',
      jsonEncode({
        'CONM': 350,
        'RTM': 57,
        'ID': 0,
        'PL': 1,
        'NOM': username,
        'LT': token,
        'LANG': 'en',
        'DID': '0',
        'AID': '17254677223212351',
        'KID': '',
        'REF': 'https://empire.goodgamestudios.com',
        'GCI': '',
        'SID': 9,
        'PLFID': 1,
      }),
      responseCmd: 'lli',
      timeoutMs: 30000,
    );

    if (resp.resultCode == 409) {
      _savedToken = null;
      await AppStorage.setToken('');
      throw Exception('Token expired');
    }
    if (resp.resultCode != 0) {
      throw Exception('Token login failed: ${errorName(resp.resultCode)}');
    }
    _status('token login ✓');

    final waitStart = DateTime.now();
    while (!_gbdReceived &&
        DateTime.now().difference(waitStart).inMilliseconds < 3000) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    await _runInitSequence();
    _startBackgroundPolling();
  }

  void _startBackgroundPolling() {
    if (_backgroundPollingActive) return;
    _backgroundPollingActive = true;
    _status('Starting keep-alive (pin only)...');

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_connected) return;
      try {
        _sendXt('pin', '<RoundHouseKick>');
      } catch (_) {}
    });
  }

  Future<void> loginWithPassword(String username, String password) async {
    _cachedAllianceId = null;
    _cachedAllianceMembers = null;
    _gbdReceived = false;

    _status('verChk...');
    await _sendAndWaitRaw(
      '<msg t="sys"><body action="verChk" r="0"><ver v="166" /></body></msg>',
      (m) => m.contains('apiOK'),
      debugLabel: 'apiOK',
    );

    _status('login XML...');
    await _sendAndWaitRaw(
      '<msg t="sys"><body action="login" r="0"><login z="$_gameServer"><nick><![CDATA[]]></nick><pword><![CDATA[undefined%en%0]]></pword></login></body></msg>',
      (m) => m.contains('rlu'),
      debugLabel: 'rlu',
    );

    _status('autoJoin...');
    await _sendAndWaitRaw(
      '<msg t="sys"><body action="autoJoin" r="-1"></body></msg>',
      (m) => m.contains('joinOK'),
      debugLabel: 'joinOK',
    );

    _status('roundTrip + vck...');
    _send('<msg t="sys"><body action="roundTrip" r="1"></body></msg>');
    await Future.delayed(const Duration(milliseconds: 100));

    final rand = Random().nextDouble() * 9e307;
    await _sendXtAndWait(
      'vck',
      'undefined%web-html5%<RoundHouseKick>%${rand.toStringAsExponential(16)}',
      responseCmd: 'vck',
    );

    _status('lli (Password Mode)...');
    final resp = await _sendXtAndWait(
      'lli',
      jsonEncode({
        'CONM': 212,
        'RTM': 25,
        'ID': 0,
        'PL': 1,
        'NOM': username,
        'PW': password,
        'LT': null,
        'LANG': 'en',
        'DID': '0',
        'AID': '1745592024940879420',
        'KID': '',
        'REF': 'https://empire.goodgamestudios.com',
        'GCI': '',
        'SID': 9,
        'PLFID': 1,
      }),
      responseCmd: 'lli',
      timeoutMs: 30000,
    );

    if (resp.resultCode != 0) {
      _errorLog('Login failed: ${errorName(resp.resultCode)}');
      throw Exception('Login failed: ${errorName(resp.resultCode)}');
    }
    _status('login ✓');

    _status('Waiting for gbd...');
    final waitStart = DateTime.now();
    while (!_gbdReceived &&
        DateTime.now().difference(waitStart).inMilliseconds < 3000) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (_gbdReceived) {
      _status('gbd ✓ (PID=$_cachedPlayerId, AID=$_cachedAllianceId, '
          'members=${_cachedAllianceMembers?.length ?? 0})');
    } else {
      _errorLog('gbd did NOT arrive within 3s');
    }

    await _runInitSequence();
    _startBackgroundPolling();
  }

  Future<List<OwnedCastle>> getCastles() => castleService.getCastles();

  Future<List<CastleUnit>> getCastleUnits(
    int kingdomId,
    int areaId,
    Map<int, UnitCatalogEntry> catalog,
  ) =>
      castleService.getCastleUnits(kingdomId, areaId, catalog);

  Future<Map<int, UnitCatalogEntry>> loadCatalog(
      {bool forceReload = false}) async {
    final catalog = await catalogService.load(forceReload: forceReload);
    _cachedCatalog = catalog;
    return catalog;
  }

  Future<List<CommanderInfo>> getCommanders() =>
      commandersService.getCommanders();

  Future<TransferResult> recallMovement(int movementId) =>
      commandersService.recall(movementId);

  Future<TransferResult> transfer({
    required OwnedCastle source,
    required OwnedCastle target,
    required List<List<int>> units,
    int? lordId,
  }) =>
      transferService.transfer(
        source: source,
        target: target,
        units: units,
        lordId: lordId,
      );

  Future<TransferResult> sendToAlly({
    required OwnedCastle source,
    required AllyCastle target,
    required List<List<int>> units,
    int stationTime = 12,
    int? lordId,
  }) =>
      smuggleService.sendToAlly(
        source: source,
        target: target,
        units: units,
        stationTime: stationTime,
        lordId: lordId,
      );

  Future<TransferResult> trainUnits({
    required int areaId,
    required int wodId,
    required int amount,
    int lordId = 0,
  }) =>
      trainingService.train(
        areaId: areaId,
        wodId: wodId,
        amount: amount,
        lordId: lordId,
      );

  Future<List<AllyMember>> getAllianceMembers() =>
      allianceService.getMembers();

  Future<int?> getMyAllianceId() => allianceService.getMyAllianceId();

  Future<void> dispose() async {
    _disposed = true;
    _pollingTimer?.cancel();
    _backgroundPollingActive = false;
    _networkWaitActive = false;
    await _sub?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _connected = false;
    await _xtCtrl.close();
    await _rawCtrl.close();
    await _gamCtrl.close();
    await _attackCtrl.close();
    _instance = null;
    allowBackgroundReconnect = false;
  }
}