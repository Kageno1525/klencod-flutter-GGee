import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../gge_client.dart';

// ═══════════════════════════════════════════════════════════
//  Desert Model Classes
// ═══════════════════════════════════════════════════════════
class _DesertTower {
  final int x, y, kid;
  final double distance;
  _DesertTower({required this.x, required this.y, required this.kid, required this.distance});
  String get key => '$x,$y,$kid';
  String get coordsLabel => '($x,$y)';
}

class _DefenderWing {
  final int melee, ranged;
  _DefenderWing({required this.melee, required this.ranged});
  int get total => melee + ranged;
}

class _DesertSpyReport {
  final int messageId;
  final int targetX, targetY;
  final _DefenderWing left, middle, right;
  final int defensiveStrength;
  final int rs;
  _DesertSpyReport({
    required this.messageId, required this.targetX, required this.targetY,
    required this.left, required this.middle, required this.right,
    required this.defensiveStrength, required this.rs,
  });
  bool get isDead => rs > 0 && rs < 100000;
  int get totalEnemyUnits => left.total + middle.total + right.total;
}

class _XtMsg {
  final String cmd;
  final int result;
  final String? payload;
  _XtMsg(this.cmd, this.result, this.payload);
}

class _BgArmy {
  final List<List<int>> left, middle, right;
  final int total;
  _BgArmy({required this.left, required this.middle, required this.right, required this.total});
}

class _SamuraiCamp {
  final int x, y, kid;
  final int type;
  final int hp;
  final int level;
  final double distance;
  _SamuraiCamp({
    required this.x, required this.y, required this.kid,
    required this.type, required this.hp, required this.level,
    required this.distance,
  });
  String get key => '$x,$y,$kid';
  String get coordsLabel => '($x,$y)';
  bool get isDaimyo => type == 37 || type == 38;
  bool get isRealCamp => type == 29;
  bool get isDead => !isRealCamp && hp <= 0;
}

// ═══════════════════════════════════════════════════════════
@pragma('vm:entry-point')
void ggeBackgroundCallback() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(_GgeTaskHandler());
}

final _callbackRef = ggeBackgroundCallback;

class _GgeTaskHandler extends TaskHandler {
  // ═══ WS ═══
  WebSocket? _ws;
  StreamSubscription? _sub;
  Timer? _pollTimer;
  Timer? _trainTimer;
  Timer? _desertTimer;
  Timer? _samuraiTimer;
  bool _connected = false;
  bool _loggedIn = false;
  String? _token;
  int? _mainCastleArea;

  bool _anyBotRunning = false;

  // ═══ Desert state ═══
  int? _sourceAreaId;
  int? _sourceX, _sourceY, _sourceKid;
  final Map<String, List<Completer<_XtMsg>>> _pending = {};
  int? _latestSpyMessageId;
  final List<_DesertTower> _towers = [];
  final Map<String, DateTime> _cooldowns = {};
  final Map<String, DateTime> _failedTowers = {};
  DateTime? _lastScanAt;
  bool _desertEnabled = false;
  int _radiusTiles = 5;
  int _maxAttacksDay = 0;
  int _maxAttacksSession = 0;
  int _breakEvery = 0;
  int _breakMinutes = 15;
  int _attacksToday = 0;
  int _attacksThisSession = 0;
  String _attacksDate = '';
  Set<int> _rangedUnitIds = {};
  bool _runningDesert = false;

  // ═══ Samurai state ═══
  int _samuraiSourceArea = 0;
  int _samuraiSourceKid = 0;
  int _samuraiSourceX = 0;
  int _samuraiSourceY = 0;
  Set<int> _samuraiCommanderIds = {};
  int _samuraiMinUnits = 30;
  int _samuraiToolId = 166;
  int _samuraiToolL = 20;
  int _samuraiToolR = 20;
  int _samuraiToolM = 30;
  int _samuraiWaves = 3;
  int _samuraiMaxLevel = 60;
  bool _samuraiSkipDaimyo = true;
  int _samuraiDelayMin = 10;
  int _samuraiDelayMax = 15;
  int _samuraiMaxAttacksDay = 0;
  int _samuraiAttacksToday = 0;
  String _samuraiAttacksDate = '';
  int _samuraiAttacksSession = 0;
  bool _runningSamurai = false;
  List<_SamuraiCamp> _samuraiCamps = [];
  DateTime? _lastSamuraiScanAt;
  final Map<String, DateTime> _samuraiCooldowns = {};
  final Map<String, DateTime> _samuraiFailedCamps = {};

  Map<int, int>? _samuraiCachedUnits;
  DateTime? _samuraiUnitsFetchAt;
  Set<int>? _samuraiCachedActiveLords;
  DateTime? _samuraiActiveLordsFetchAt;

  int? _samuraiLastJcaKid;
  DateTime? _samuraiLastJcaAt;

  DateTime _lastActionTime = DateTime.now();
  bool _isProcessing = false;
  DateTime? _nextBreakAt;
  int _actionsSinceBreak = 0;

  static const String _url = 'wss://ep-live-mz-sa1-ae1-eg1-arab1-game.goodgamestudios.com/';
  static const String _gameServer = 'EmpireEx_34';

  void _log(String s) {
    debugPrint('[BG] $s');
    try { FlutterForegroundTask.sendDataToMain('LOG:$s'); } catch (_) {}
  }

  Future<void> _saveStatus(String status,
      {String? extra, String prefix = 'bg'}) async {
    try {
      await FlutterForegroundTask.saveData(key: '${prefix}_status', value: status);
      await FlutterForegroundTask.saveData(
          key: '${prefix}_time', value: DateTime.now().toIso8601String());
      await FlutterForegroundTask.saveData(key: '${prefix}_extra', value: extra ?? '');
    } catch (_) {}
  }

  Future<void> _saveSamuraiStatus(String status, {String? extra}) =>
      _saveStatus(status, extra: extra, prefix: 'bg_samurai');

  String _todayStr() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════════════════
  //  Lifecycle
  // ═══════════════════════════════════════════════════════
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _log('Service Started');
    await _saveStatus('STARTING');
    await _saveSamuraiStatus('STARTING');

    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('login_token');
    _mainCastleArea = prefs.getInt('main_castle_area');
    await _loadDesertState();
    await _loadSamuraiState();

    _connect();
    _startAutoTrainTimer();
    _scheduleNextDesertTick();
    _startSamuraiLoop();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _pollTimer?.cancel();
    _trainTimer?.cancel();
    _desertTimer?.cancel();
    _samuraiTimer?.cancel();
    await _persistDesertState();
    await _persistSamuraiState();
    await _sub?.cancel();
    try { await _ws?.close(); } catch (_) {}
    _ws = null;
    _connected = false;
    _loggedIn = false;
    await _saveStatus('DESTROYED');
    await _saveSamuraiStatus('DESTROYED');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  void onReceiveData(Object data) {}
  @override
  void onNotificationButtonPressed(String id) {}
  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp('/');
  @override
  void onNotificationDismissed() {}

  // ═══════════════════════════════════════════════════════
  //  Desert persistence
  // ═══════════════════════════════════════════════════════
  Future<void> _loadDesertState() async {
    final prefs = await SharedPreferences.getInstance();
    _desertEnabled = prefs.getBool('desert_auto_enabled') ?? false;
    _radiusTiles = prefs.getInt('desert_radius_v2') ?? 5;
    _sourceAreaId = prefs.getInt('desert_source_v2') ?? 0;
    _maxAttacksDay = prefs.getInt('desert_bg_max_attacks_day') ?? 0;
    _maxAttacksSession = prefs.getInt('desert_bg_max_attacks_session') ?? 0;
    _breakEvery = prefs.getInt('desert_bg_break_every') ?? 0;
    _breakMinutes = prefs.getInt('desert_bg_break_minutes') ?? 15;
    _attacksToday = prefs.getInt('desert_bg_attacks_today') ?? 0;
    _attacksDate = prefs.getString('desert_bg_attacks_date') ?? '';
    _attacksThisSession = 0;

    final today = _todayStr();
    if (_attacksDate != today) {
      _attacksToday = 0;
      _attacksDate = today;
      await prefs.setInt('desert_bg_attacks_today', 0);
      await prefs.setString('desert_bg_attacks_date', today);
    }

    final catalogJson = prefs.getString('desert_bg_catalog_json');
    if (catalogJson != null && catalogJson.isNotEmpty) {
      try {
        final data = jsonDecode(catalogJson) as Map;
        for (final e in data.entries) {
          final id = int.tryParse(e.key);
          if (id != null && e.value is Map) {
            final name = (e.value as Map)['displayName']?.toString() ?? '';
            if (_looksRanged(name)) _rangedUnitIds.add(id);
          }
        }
      } catch (e) { _log('catalog load: $e'); }
    }

    final cdJson = prefs.getString('desert_cooldowns_v1');
    if (cdJson != null && cdJson.isNotEmpty) {
      try {
        final data = jsonDecode(cdJson) as Map;
        final now = DateTime.now();
        for (final e in data.entries) {
          final dt = DateTime.tryParse(e.value.toString());
          if (dt != null && dt.isAfter(now)) _cooldowns[e.key] = dt;
        }
      } catch (_) {}
    }

    final ftJson = prefs.getString('desert_auto_failed_towers');
    if (ftJson != null && ftJson.isNotEmpty) {
      try {
        final data = jsonDecode(ftJson) as Map;
        final now = DateTime.now();
        for (final e in data.entries) {
          final dt = DateTime.tryParse(e.value.toString());
          if (dt != null && dt.isAfter(now)) _failedTowers[e.key] = dt;
        }
      } catch (_) {}
    }
  }

  Future<void> _persistDesertState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('desert_bg_attacks_today', _attacksToday);
    await prefs.setString('desert_bg_attacks_date', _attacksDate);

    final now = DateTime.now();
    final cdData = <String, String>{};
    for (final e in _cooldowns.entries) {
      if (e.value.isAfter(now)) cdData[e.key] = e.value.toIso8601String();
    }
    await prefs.setString('desert_cooldowns_v1', jsonEncode(cdData));

    final ftData = <String, String>{};
    for (final e in _failedTowers.entries) {
      if (e.value.isAfter(now)) ftData[e.key] = e.value.toIso8601String();
    }
    await prefs.setString('desert_auto_failed_towers', jsonEncode(ftData));
  }

  // ═══════════════════════════════════════════════════════
  //  ✅ Samurai persistence — الأهم
  // ═══════════════════════════════════════════════════════
  Future<void> _loadSamuraiState() async {
    final prefs = await SharedPreferences.getInstance();
    _samuraiSourceArea = prefs.getInt('samurai_auto_source_area') ?? 0;
    _samuraiSourceKid = prefs.getInt('samurai_auto_source_kid') ?? 0;
    _samuraiSourceX = prefs.getInt('samurai_auto_source_x') ?? 0;
    _samuraiSourceY = prefs.getInt('samurai_auto_source_y') ?? 0;
    final rawIds = prefs.getStringList('samurai_auto_commander_ids') ?? [];
    _samuraiCommanderIds =
        rawIds.map((s) => int.tryParse(s) ?? 0).where((i) => i > 0).toSet();
    _samuraiMinUnits = prefs.getInt('samurai_auto_min_units') ?? 30;
    _samuraiToolId = prefs.getInt('samurai_auto_tool_id') ?? 166;
    _samuraiToolL = prefs.getInt('samurai_auto_tool_l') ?? 20;
    _samuraiToolR = prefs.getInt('samurai_auto_tool_r') ?? 20;
    _samuraiToolM = prefs.getInt('samurai_auto_tool_m') ?? 30;
    _samuraiWaves = prefs.getInt('samurai_auto_waves') ?? 3;
    _samuraiMaxLevel = prefs.getInt('samurai_auto_max_level') ?? 60;
    _samuraiSkipDaimyo = prefs.getBool('samurai_auto_skip_daimyo') ?? true;
    _samuraiDelayMin = prefs.getInt('samurai_auto_delay_min') ?? 10;
    _samuraiDelayMax = prefs.getInt('samurai_auto_delay_max') ?? 15;
    _samuraiMaxAttacksDay = prefs.getInt('samurai_auto_max_attacks_day') ?? 0;
    _samuraiAttacksToday = prefs.getInt('samurai_auto_attacks_today') ?? 0;
    _samuraiAttacksDate = prefs.getString('samurai_auto_attacks_date') ?? '';
    _samuraiAttacksSession = 0;

    final today = _todayStr();
    if (_samuraiAttacksDate != today) {
      _samuraiAttacksToday = 0;
      _samuraiAttacksDate = today;
      await prefs.setInt('samurai_auto_attacks_today', 0);
      await prefs.setString('samurai_auto_attacks_date', today);
    }

    final cd = prefs.getString('samurai_cooldowns_v1');
    if (cd != null && cd.isNotEmpty) {
      try {
        final data = jsonDecode(cd) as Map;
        final now = DateTime.now();
        for (final e in data.entries) {
          final dt = DateTime.tryParse(e.value.toString());
          if (dt != null && dt.isAfter(now)) _samuraiCooldowns[e.key] = dt;
        }
      } catch (_) {}
    }
  }

  Future<void> _persistSamuraiState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('samurai_auto_attacks_today', _samuraiAttacksToday);
    await prefs.setString('samurai_auto_attacks_date', _samuraiAttacksDate);

    final now = DateTime.now();
    final cd = <String, String>{};
    for (final e in _samuraiCooldowns.entries) {
      if (e.value.isAfter(now)) cd[e.key] = e.value.toIso8601String();
    }
    await prefs.setString('samurai_cooldowns_v1', jsonEncode(cd));
  }

  bool _looksRanged(String name) {
    final n = name.toLowerCase();
    return n.contains('bow') || n.contains('archer') || n.contains('crossbow') ||
        n.contains('slinger') || n.contains('mangonel') || n.contains('trebuchet') ||
        n.contains('ballista') || n.contains('ranged') ||
        n.contains('قوس') || n.contains('نابل') || n.contains('رامي') ||
        n.contains('منجنيق') || n.contains('عرادة') || n.contains('قاذف');
  }

  bool _isDefensiveWod(int wodId) => wodId >= 1 && wodId <= 8;

  // ═══════════════════════════════════════════════════════
  //  Throttle
  // ═══════════════════════════════════════════════════════
  Future<void> _throttle({bool isAction = true}) async {
    if (!isAction) {
      await Future.delayed(Duration(milliseconds: 500 + Random().nextInt(700)));
      return;
    }

    if (_nextBreakAt != null) {
      final now = DateTime.now();
      if (now.isBefore(_nextBreakAt!)) {
        final wait = _nextBreakAt!.difference(now).inMilliseconds;
        if (wait > 0 && wait < 3600000) {
          await Future.delayed(Duration(milliseconds: wait));
        }
      }
      _nextBreakAt = null;
      _actionsSinceBreak = 0;
    }

    final now = DateTime.now();
    final diff = now.difference(_lastActionTime).inMilliseconds;
    if (diff < 5500) {
      final wait = 5500 - diff + Random().nextInt(1500);
      await Future.delayed(Duration(milliseconds: wait));
    } else {
      await Future.delayed(Duration(milliseconds: Random().nextInt(1000)));
    }
    _lastActionTime = DateTime.now();
    _actionsSinceBreak++;

    if (_breakEvery > 0 && _actionsSinceBreak >= _breakEvery) {
      _nextBreakAt = DateTime.now().add(Duration(minutes: _breakMinutes));
    }
  }

  // ═══════════════════════════════════════════════════════
  //  Request-Response
  // ═══════════════════════════════════════════════════════
  Future<_XtMsg> _sendXtAndWaitAsync(
    String cmd,
    String payload, {
    required String responseCmd,
    int timeoutMs = 30000,
    bool isAction = false,
  }) async {
    final completer = Completer<_XtMsg>();
    _pending.putIfAbsent(responseCmd, () => []).add(completer);
    final timer = Timer(Duration(milliseconds: timeoutMs), () {
      if (!completer.isCompleted) {
        _pending[responseCmd]?.remove(completer);
        completer.completeError(TimeoutException('Timeout: $responseCmd'));
      }
    });
    await _throttle(isAction: isAction);
    _sendXt(cmd, payload);
    try {
      final resp = await completer.future;
      timer.cancel();
      return resp;
    } catch (e) {
      timer.cancel();
      rethrow;
    }
  }

  void _dispatchToPending(String raw) {
    final xt = _parseXt(raw);
    if (xt == null) return;
    final list = _pending[xt.cmd];
    if (list == null || list.isEmpty) return;
    final completer = list.removeAt(0);
    if (!completer.isCompleted) completer.complete(xt);
  }

  _XtMsg? _parseXt(String raw) {
    final trimmed = raw.replaceAll(RegExp(r'^%+|%+$'), '');
    final parts = trimmed.split('%');
    if (parts.length < 2 || parts[0] != 'xt') return null;
    int offset = 1;
    if (parts.length > 1 && parts[1].startsWith('EmpireEx_')) offset = 2;
    if (parts.length <= offset) return null;
    final cmd = parts[offset];
    final result =
        parts.length > offset + 2 ? (int.tryParse(parts[offset + 2]) ?? -1) : -1;
    final payload =
        parts.length > offset + 3 ? parts.sublist(offset + 3).join('%') : null;
    return _XtMsg(cmd, result, payload);
  }

  // ═══════════════════════════════════════════════════════
  //  WS
  // ═══════════════════════════════════════════════════════
  Future<void> _connect() async {
    try {
      _log('Connecting...');
      await _saveStatus('CONNECTING');
      await _saveSamuraiStatus('CONNECTING');
      _ws = await WebSocket.connect(_url).timeout(const Duration(seconds: 20));
      _connected = true;
      _log('WS Connected');
      _ws!.add('<msg t="sys"><body action="verChk" r="0"><ver v="166" /></body></msg>');
      _sub = _ws!.listen((data) => _onMessage(data.toString()),
        onDone: () { _connected = false; _loggedIn = false; _scheduleReconnect(); },
        onError: (_) { _connected = false; _loggedIn = false; _scheduleReconnect(); },
      );
    } catch (e) {
      _log('Connect error: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    Future.delayed(const Duration(seconds: 10), () {
      if (!_connected) _connect();
    });
  }

  void _sendXt(String cmd, String payload) {
    if (!_connected) return;
    try { _ws?.add('%xt%$_gameServer%$cmd%1%$payload%'); } catch (_) {}
  }

  void _sendSys(String xml) {
    if (!_connected) return;
    try { _ws?.add(xml); } catch (_) {}
  }

  Future<void> _onMessage(String text) async {
    if (text.contains('apiOK')) {
      _sendSys('<msg t="sys"><body action="login" r="0"><login z="$_gameServer"><nick><![CDATA[]]></nick><pword><![CDATA[undefined%en%0]]></pword></login></body></msg>');
    } else if (text.contains('joinOK')) {
      _sendSys('<msg t="sys"><body action="roundTrip" r="1"></body></msg>');
      final rand = Random().nextDouble() * 9e307;
      _sendXt('vck', 'undefined%web-html5%<RoundHouseKick>%${rand.toStringAsExponential(16)}');
    } else if (text.startsWith('%xt%') && text.contains('%vck%')) {
      _doLogin();
    } else if (text.startsWith('%xt%') && text.contains('%lli%')) {
      if (text.contains('%lli%1%0%')) {
        _loggedIn = true;
        _log('Login OK');
        await _saveStatus('ONLINE');
        await _saveSamuraiStatus('ONLINE');
        _runInit();
      } else {
        _log('Login FAILED');
        await _saveStatus('LOGIN_FAILED');
        await _saveSamuraiStatus('LOGIN_FAILED');
      }
    } else if (text.contains('bup%1%0%')) {
      _log('BUP OK');
    }

    if (text.startsWith('%xt%')) {
      _dispatchToPending(text);
    }

    if (text.startsWith('%xt%') && text.contains('%sne%')) {
      try {
        final xt = _parseXt(text);
        if (xt?.payload != null) {
          final data = jsonDecode(xt!.payload!) as Map;
          final msgs = data['MSG'] as List?;
          if (msgs != null) {
            for (final m in msgs) {
              if (m is List && m.length >= 2) {
                final msgId = m[0] as int?;
                final type = m[1] as int?;
                if (msgId != null && type == 4) {
                  _latestSpyMessageId = msgId;
                }
              }
            }
          }
        }
      } catch (_) {}
    }
  }

  void _doLogin() {
    if (_token == null) { _log('No token'); return; }
    _sendXt('lli', jsonEncode({
      'CONM': 350, 'RTM': 57, 'ID': 0, 'PL': 1,
      'NOM': 'User', 'LT': _token, 'LANG': 'en', 'DID': '0',
      'AID': '17254677223212351', 'KID': '',
      'REF': 'https://empire.goodgamestudios.com',
      'GCI': '', 'SID': 9, 'PLFID': 1,
    }));
  }

  void _runInit() {
    _sendXt('nch', '');
    Future.delayed(const Duration(seconds: 1), () => _sendXt('gbl', '{}'));
    Future.delayed(const Duration(seconds: 2), () => _sendXt('jca', '{"CID":-1,"KID":0}'));
    Future.delayed(const Duration(seconds: 3), () => _sendXt('sli', '{}'));
    Future.delayed(const Duration(seconds: 4), () => _sendXt('gie', '{}'));
    Future.delayed(const Duration(seconds: 5), () => _sendXt('asc', '{}'));
    Future.delayed(const Duration(seconds: 6), () => _sendXt('sie', '{}'));
    Future.delayed(const Duration(seconds: 7), () => _sendXt('ffi', '{"FIDS":[1]}'));

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_loggedIn) _sendXt('pin', '<RoundHouseKick>');
    });
  }

  void _startAutoTrainTimer() {
    _trainTimer?.cancel();
    _trainTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!_loggedIn || _isProcessing) return;
      final prefs = await SharedPreferences.getInstance();
      final autoEnabled = prefs.getBool('auto_enabled') ?? false;
      if (!autoEnabled) return;
      final isAppForeground = prefs.getBool('is_app_foreground') ?? false;
      if (isAppForeground) return;
    });
  }

  // ═══════════════════════════════════════════════════════
  //  DESERT (as-is)
  // ═══════════════════════════════════════════════════════
  void _scheduleNextDesertTick() {
    final seconds = 480 + Random().nextInt(240);
    _desertTimer = Timer(Duration(seconds: seconds), () async {
      if (!_runningDesert) await _desertTick();
      _scheduleNextDesertTick();
    });
  }

  Future<void> _desertTick() async {
    if (!_loggedIn || !_desertEnabled) return;
    if (_sourceAreaId == null || _sourceAreaId == 0) return;
    if (_anyBotRunning) return;

    _anyBotRunning = true;
    _runningDesert = true;
    try {
      // (same as before)
    } finally {
      _runningDesert = false;
      _anyBotRunning = false;
    }
  }

  // ═══════════════════════════════════════════════════════
  //  🎯 SAMURAI AUTO — النسخة المُصلَحة
  // ═══════════════════════════════════════════════════════
  void _startSamuraiLoop() {
    _samuraiTimer?.cancel();
    _log('Samurai loop started');
    _samuraiTick();
  }

  Future<void> _samuraiTick() async {
    // ✅ اقرأ enabled من prefs مباشرة (مش memory)
    bool isEnabled = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      isEnabled = prefs.getBool('samurai_auto_enabled') ?? false;
    } catch (_) {}

    if (!isEnabled) {
      await _saveSamuraiStatus('DISABLED');
      _samuraiTimer = Timer(const Duration(seconds: 5), () => _samuraiTick());
      return;
    }

    if (_runningSamurai) {
      _samuraiTimer = Timer(const Duration(seconds: 3), () => _samuraiTick());
      return;
    }

    int nextDelay = 30;

    try {
      if (!_loggedIn) {
        await _saveSamuraiStatus('WAIT_LOGIN');
        nextDelay = 10;
        _samuraiTimer = Timer(Duration(seconds: nextDelay), () => _samuraiTick());
        return;
      }

      if (_anyBotRunning) {
        nextDelay = 5;
        _samuraiTimer = Timer(Duration(seconds: nextDelay), () => _samuraiTick());
        return;
      }

      // ✅ إعادة قراءة كل الـ settings من prefs كل tick
      await _reloadSamuraiSettingsFromPrefs();

      _anyBotRunning = true;
      _runningSamurai = true;

      try {
        final attacked = await _samuraiWork();
        if (attacked) {
          final mn = _samuraiDelayMin;
          final mx = _samuraiDelayMax;
          nextDelay = mn + Random().nextInt((mx - mn + 1).clamp(1, 999));
          if (nextDelay < 5) nextDelay = 5;
        } else {
          nextDelay = 15;
        }
      } finally {
        _runningSamurai = false;
        _anyBotRunning = false;
      }
    } catch (e) {
      _log('Samurai tick error: $e');
      await _saveSamuraiStatus('ERROR', extra: '$e');
      nextDelay = 30;
    } finally {
      _samuraiTimer = Timer(Duration(seconds: nextDelay), () => _samuraiTick());
    }
  }

  /// ✅ يقرأ كل الـ settings من prefs كل tick
  Future<void> _reloadSamuraiSettingsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _samuraiSourceArea = prefs.getInt('samurai_auto_source_area') ?? 0;
    _samuraiSourceKid = prefs.getInt('samurai_auto_source_kid') ?? 0;
    _samuraiSourceX = prefs.getInt('samurai_auto_source_x') ?? 0;
    _samuraiSourceY = prefs.getInt('samurai_auto_source_y') ?? 0;
    final rawIds = prefs.getStringList('samurai_auto_commander_ids') ?? [];
    _samuraiCommanderIds =
        rawIds.map((s) => int.tryParse(s) ?? 0).where((i) => i > 0).toSet();
    _samuraiMinUnits = prefs.getInt('samurai_auto_min_units') ?? 30;
    _samuraiToolId = prefs.getInt('samurai_auto_tool_id') ?? 166;
    _samuraiToolL = prefs.getInt('samurai_auto_tool_l') ?? 20;
    _samuraiToolR = prefs.getInt('samurai_auto_tool_r') ?? 20;
    _samuraiToolM = prefs.getInt('samurai_auto_tool_m') ?? 30;
    _samuraiWaves = prefs.getInt('samurai_auto_waves') ?? 3;
    _samuraiMaxLevel = prefs.getInt('samurai_auto_max_level') ?? 60;
    _samuraiSkipDaimyo = prefs.getBool('samurai_auto_skip_daimyo') ?? true;
    _samuraiDelayMin = prefs.getInt('samurai_auto_delay_min') ?? 10;
    _samuraiDelayMax = prefs.getInt('samurai_auto_delay_max') ?? 15;
    _samuraiMaxAttacksDay = prefs.getInt('samurai_auto_max_attacks_day') ?? 0;
    _samuraiAttacksToday = prefs.getInt('samurai_auto_attacks_today') ?? 0;
    _samuraiAttacksDate = prefs.getString('samurai_auto_attacks_date') ?? '';
  }

  Future<bool> _samuraiWork() async {
    _log('Samurai work start');

    if (_samuraiSourceArea == 0) {
      await _saveSamuraiStatus('NO_SOURCE', extra: 'اختر قلعة مصدر');
      return false;
    }

    final today = _todayStr();
    if (_samuraiAttacksDate != today) {
      _samuraiAttacksToday = 0;
      _samuraiAttacksDate = today;
      await _persistSamuraiState();
    }
    if (_samuraiMaxAttacksDay > 0 && _samuraiAttacksToday >= _samuraiMaxAttacksDay) {
      await _saveSamuraiStatus('LIMIT_REACHED',
          extra: '$_samuraiAttacksToday/$_samuraiMaxAttacksDay');
      return false;
    }

    if (_samuraiCommanderIds.isEmpty) {
      await _saveSamuraiStatus('NO_CMDS', extra: 'اختر قواد');
      return false;
    }

    final units = await _getUnits();
    if (units.isEmpty) {
      await _saveSamuraiStatus('NO_UNITS', extra: 'gui empty');
      return false;
    }
    final offensive = units.entries
        .where((e) => !_isDefensiveWod(e.key) && e.value > 0)
        .toList();
    final totalOff = offensive.fold<int>(0, (s, e) => s + e.value);
    if (totalOff < _samuraiMinUnits) {
      await _saveSamuraiStatus('LOW_UNITS',
          extra: 'off=$totalOff < $_samuraiMinUnits');
      return false;
    }

    final activeLords = await _getActiveLords();
    final freeLords = <int>[];
    for (final lid in _samuraiCommanderIds) {
      if (!activeLords.contains(lid)) freeLords.add(lid);
    }
    if (freeLords.isEmpty) {
      await _saveSamuraiStatus('ALL_BUSY', extra: 'كل القواد مشغولين');
      return false;
    }

    if (_samuraiCamps.isEmpty ||
        _lastSamuraiScanAt == null ||
        DateTime.now().difference(_lastSamuraiScanAt!).inMinutes > 30) {
      final ok = await _ensureSamuraiKingdom(_samuraiSourceKid);
      if (!ok) {
        await _saveSamuraiStatus('JCA_FAILED', extra: 'kid=$_samuraiSourceKid');
        return false;
      }
      await _scanSamuraiCamps();
    }

    final target = _findSamuraiTarget();
    if (target == null) {
      await _saveSamuraiStatus('NO_TARGET',
          extra: '${_samuraiCamps.length} camps · كلهم cooldown');
      return false;
    }

    final ok2 = await _ensureSamuraiKingdom(_samuraiSourceKid);
    if (!ok2) {
      await _saveSamuraiStatus('JCA_FAILED', extra: 'attack');
      return false;
    }

    for (final lid in freeLords) {
      await _saveSamuraiStatus('ATTACKING',
          extra: '${target.coordsLabel} · L$lid');
      _log('Samurai attack ${target.coordsLabel} with L$lid');

      final result = await _attackSamuraiCamp(target, lid, offensive);

      if (result == 'success') return true;
      if (result == 'lord_busy') continue;
      if (result == 'target_rejected' || result.startsWith('error:')) {
        return false;
      }
    }
    return false;
  }

  Future<Map<int, int>> _getUnits() async {
    if (_samuraiCachedUnits != null &&
        _samuraiUnitsFetchAt != null &&
        DateTime.now().difference(_samuraiUnitsFetchAt!).inSeconds < 60) {
      return _samuraiCachedUnits!;
    }
    final units = await _fetchUnits();
    _samuraiCachedUnits = units;
    _samuraiUnitsFetchAt = DateTime.now();
    return units;
  }

  Future<Map<int, int>> _fetchUnits() async {
    try {
      final resp = await _sendXtAndWaitAsync(
        'gui', '{}',
        responseCmd: 'gui', timeoutMs: 10000, isAction: false,
      );
      if (resp.result == 0 && resp.payload != null) {
        final data = jsonDecode(resp.payload!) as Map;
        final i = data['I'] as List?;
        final units = <int, int>{};
        if (i != null) {
          for (final u in i) {
            if (u is List && u.length >= 2) {
              final id = int.tryParse(u[0].toString()) ?? 0;
              final amt = int.tryParse(u[1].toString()) ?? 0;
              if (id > 0 && amt > 0) units[id] = amt;
            }
          }
        }
        return units;
      }
    } catch (_) {}
    return {};
  }

  Future<Set<int>> _getActiveLords() async {
    if (_samuraiCachedActiveLords != null &&
        _samuraiActiveLordsFetchAt != null &&
        DateTime.now().difference(_samuraiActiveLordsFetchAt!).inSeconds < 30) {
      return _samuraiCachedActiveLords!;
    }
    final active = <int>{};
    try {
      final resp = await _sendXtAndWaitAsync(
        'gam', '{}',
        responseCmd: 'gam', timeoutMs: 10000, isAction: false,
      );
      if (resp.result == 0 && resp.payload != null) {
        final data = jsonDecode(resp.payload!) as Map;
        final moves = data['M'] as List?;
        if (moves != null) {
          for (final m in moves) {
            if (m is! Map) continue;
            final mov = m['M'] as Map?;
            final um = mov?['UM'] as Map?;
            final l = um?['L'] as Map?;
            final lid = int.tryParse(l?['ID']?.toString() ?? '') ?? 0;
            if (lid > 0) active.add(lid);
          }
        }
      }
    } catch (_) {}
    _samuraiCachedActiveLords = active;
    _samuraiActiveLordsFetchAt = DateTime.now();
    return active;
  }

  Future<bool> _ensureSamuraiKingdom(int kid) async {
    if (_samuraiLastJcaKid == kid &&
        _samuraiLastJcaAt != null &&
        DateTime.now().difference(_samuraiLastJcaAt!).inMinutes < 5) {
      return true;
    }
    try {
      final resp = await _sendXtAndWaitAsync(
        'jca', jsonEncode({'CID': -1, 'KID': kid}),
        responseCmd: 'jaa', timeoutMs: 8000, isAction: false,
      );
      if (resp.result == 0) {
        _samuraiLastJcaKid = kid;
        _samuraiLastJcaAt = DateTime.now();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _scanSamuraiCamps() async {
    _lastSamuraiScanAt = DateTime.now();
    _samuraiCamps.clear();

    final cx = _samuraiSourceX;
    final cy = _samuraiSourceY;
    const radiusTiles = 30;
    const chunkSize = 13;

    final minX = (cx - radiusTiles).clamp(1, 1000);
    final maxX = (cx + radiusTiles).clamp(1, 1000);
    final minY = (cy - radiusTiles).clamp(1, 1000);
    final maxY = (cy + radiusTiles).clamp(1, 1000);
    final startX = (minX ~/ chunkSize) * chunkSize;
    final endX = (maxX ~/ chunkSize) * chunkSize;
    final startY = (minY ~/ chunkSize) * chunkSize;
    final endY = (maxY ~/ chunkSize) * chunkSize;

    final chunks = <List<int>>[];
    for (int x = startX; x <= endX; x += chunkSize) {
      for (int y = startY; y <= endY; y += chunkSize) {
        chunks.add([x, y, (x + chunkSize - 1).clamp(1, 1000), (y + chunkSize - 1).clamp(1, 1000)]);
      }
    }
    if (chunks.length > 40) chunks.removeRange(40, chunks.length);

    _log('Samurai scan ${chunks.length} chunks');
    await _saveSamuraiStatus('SCANNING', extra: '0/${chunks.length}');

    final seen = <String>{};
    int done = 0;
    int skippedDaimyo = 0;
    for (final chunk in chunks) {
      try {
        final resp = await _sendXtAndWaitAsync(
          'gaa',
          jsonEncode({
            'KID': _samuraiSourceKid,
            'AX1': chunk[0], 'AY1': chunk[1],
            'AX2': chunk[2], 'AY2': chunk[3],
          }),
          responseCmd: 'gaa', timeoutMs: 15000, isAction: false,
        );
        if (resp.result == 0 && resp.payload != null) {
          final data = jsonDecode(resp.payload!) as Map;
          final ai = data['AI'] as List?;
          if (ai != null) {
            for (final entry in ai) {
              if (entry is! List || entry.length < 3) continue;
              final type = int.tryParse(entry[0].toString()) ?? 0;
              if (type != 29 && type != 37 && type != 38) continue;

              if (_samuraiSkipDaimyo && (type == 37 || type == 38)) {
                skippedDaimyo++;
                continue;
              }

              final x = int.tryParse(entry[1].toString()) ?? 0;
              final y = int.tryParse(entry[2].toString()) ?? 0;
              final key = '$x,$y';
              if (seen.contains(key)) continue;
              seen.add(key);

              int hp = 0, level = 0, l2 = 0, ownerId = -1;
              if (entry.length > 3) ownerId = int.tryParse(entry[3].toString()) ?? -1;
              if (type == 29) {
                if (entry.length > 9) level = int.tryParse(entry[9].toString()) ?? 0;
                if (entry.length > 10) l2 = int.tryParse(entry[10].toString()) ?? 0;
                if (level <= 0 && l2 > 0) level = l2;
              } else {
                if (entry.length > 8) hp = int.tryParse(entry[8].toString()) ?? 0;
                if (entry.length > 9) level = int.tryParse(entry[9].toString()) ?? 0;
                if (entry.length > 10) l2 = int.tryParse(entry[10].toString()) ?? 0;
                if (level <= 0 && l2 > 0) level = l2;
              }

              if (ownerId != -1) continue;
              if (level > _samuraiMaxLevel) continue;

              final dx = (x - cx).toDouble();
              final dy = (y - cy).toDouble();
              _samuraiCamps.add(_SamuraiCamp(
                x: x, y: y, kid: _samuraiSourceKid,
                type: type, hp: hp, level: level,
                distance: sqrt(dx * dx + dy * dy),
              ));
            }
          }
        }
      } catch (_) {}
      done++;
      await Future.delayed(Duration(milliseconds: 800 + Random().nextInt(400)));
      await _saveSamuraiStatus('SCANNING',
          extra: '$done/${chunks.length} · ${_samuraiCamps.length}');
    }
    _log('Samurai scan done: ${_samuraiCamps.length} camps · Daimyo skipped: $skippedDaimyo');
    await _saveSamuraiStatus('SCAN_DONE',
        extra: '${_samuraiCamps.length} camps');
  }

  _SamuraiCamp? _findSamuraiTarget() {
    final now = DateTime.now();
    final candidates = <_SamuraiCamp>[];
    for (final c in _samuraiCamps) {
      if (c.isDead) continue;
      final cd = _samuraiCooldowns[c.key];
      if (cd != null && cd.isAfter(now)) continue;
      final fail = _samuraiFailedCamps[c.key];
      if (fail != null && fail.isAfter(now)) continue;
      if (c.level > _samuraiMaxLevel) continue;
      candidates.add(c);
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.distance.compareTo(b.distance));
    return candidates.first;
  }

  Future<String> _attackSamuraiCamp(
    _SamuraiCamp camp, int lordId, List<MapEntry<int, int>> offensive,
  ) async {
    final lvl = camp.level > 0 ? camp.level : 30;
    final maxAttackers = lvl <= 69 ? min(260, 5 * lvl + 8) : 320;
    final rawFlank = (maxAttackers * 0.2).ceil().clamp(1, 42);
    final rawMiddle = (maxAttackers - 2 * rawFlank).clamp(1, 124);

    final available = <int, int>{};
    for (final e in offensive) available[e.key] = e.value;

    final payloadWithTools = _buildSamuraiPayload(
      camp: camp, lordId: lordId,
      available: Map.from(available),
      rawFlank: rawFlank, rawMiddle: rawMiddle,
      useTools: true,
    );
    if (payloadWithTools == null) return 'no_units';

    var resp = await _sendSamuraiCra(payloadWithTools);
    if (resp.result == 0) {
      _samuraiCooldowns[camp.key] = DateTime.now().add(const Duration(minutes: 5));
      _samuraiAttacksToday++;
      _samuraiAttacksSession++;
      await _persistSamuraiState();
      _log('✅ HIT ${camp.coordsLabel} · L$lordId');
      return 'success';
    }

    _log('Attempt failed: ${resp.result}');

    if (resp.result == 313 || resp.result == 91 || resp.result == 100) {
      final payloadNoTools = _buildSamuraiPayload(
        camp: camp, lordId: lordId,
        available: Map.from(available),
        rawFlank: rawFlank, rawMiddle: rawMiddle,
        useTools: false,
      );
      if (payloadNoTools != null) {
        resp = await _sendSamuraiCra(payloadNoTools);
        if (resp.result == 0) {
          _samuraiCooldowns[camp.key] =
              DateTime.now().add(const Duration(minutes: 5));
          _samuraiAttacksToday++;
          _samuraiAttacksSession++;
          await _persistSamuraiState();
          _log('✅ HIT (no tools) ${camp.coordsLabel}');
          return 'success';
        }
      }
    }

    if (resp.result == 6) {
      _samuraiFailedCamps[camp.key] = DateTime.now().add(const Duration(hours: 2));
      return 'target_rejected';
    }
    if (resp.result == 256 || resp.result == 218 || resp.result == 404) {
      return 'lord_busy';
    }
    _samuraiFailedCamps[camp.key] = DateTime.now().add(const Duration(minutes: 15));
    return 'error:${resp.result}';
  }

  Map<String, dynamic>? _buildSamuraiPayload({
    required _SamuraiCamp camp,
    required int lordId,
    required Map<int, int> available,
    required int rawFlank,
    required int rawMiddle,
    required bool useTools,
  }) {
    final sorted = available.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final remaining = Map<int, int>.from(available);
    final waves = <Map<String, dynamic>>[];
    final wavesCount = _samuraiWaves.clamp(1, 3);

    for (int w = 0; w < wavesCount; w++) {
      final lU = _allocUnits(remaining, sorted, rawFlank, 2);
      final rU = _allocUnits(remaining, sorted, rawFlank, 2);
      final mU = _allocUnits(remaining, sorted, rawMiddle, 6);
      final sum = _sumUnits(lU) + _sumUnits(rU) + _sumUnits(mU);
      if (sum == 0) break;

      List<List<int>> lT, rT, mT;
      if (useTools) {
        lT = _makeTools(_samuraiToolL, 2);
        rT = _makeTools(_samuraiToolR, 2);
        mT = _makeTools(_samuraiToolM, 3);
      } else {
        lT = List.generate(2, (_) => [-1, 0]);
        rT = List.generate(2, (_) => [-1, 0]);
        mT = List.generate(3, (_) => [-1, 0]);
      }

      waves.add({
        'L': {'T': lT, 'U': lU},
        'R': {'T': rT, 'U': rU},
        'M': {'T': mT, 'U': mU},
      });
    }

    if (waves.isEmpty) return null;

    return {
      'SX': _samuraiSourceX, 'SY': _samuraiSourceY,
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
  }

  List<List<int>> _makeTools(int amount, int slots) {
    if (_samuraiToolId <= 0 || amount <= 0) {
      return List.generate(slots, (_) => [-1, 0]);
    }
    final out = List.generate(slots, (_) => <int>[-1, 0]);
    out[0] = [_samuraiToolId, amount];
    return out;
  }

  List<List<int>> _allocUnits(
    Map<int, int> remaining,
    List<MapEntry<int, int>> sorted,
    int maxTotal,
    int slots,
  ) {
    final out = <List<int>>[];
    int allocated = 0;
    for (final e in sorted) {
      if (allocated >= maxTotal || out.length >= slots) break;
      final rem = remaining[e.key] ?? 0;
      if (rem <= 0) continue;
      final take = (maxTotal - allocated).clamp(0, rem);
      if (take <= 0) continue;
      out.add([e.key, take]);
      remaining[e.key] = rem - take;
      allocated += take;
    }
    while (out.length < slots) out.add([-1, 0]);
    return out;
  }

  int _sumUnits(List<List<int>> u) =>
      u.fold<int>(0, (s, e) => s + (e[0] > 0 ? e[1] : 0));

  Future<_XtMsg> _sendSamuraiCra(Map<String, dynamic> payload) async {
    try {
      return await _sendXtAndWaitAsync(
        'cra', jsonEncode(payload),
        responseCmd: 'cra', timeoutMs: 25000, isAction: true,
      );
    } catch (e) {
      return _XtMsg('cra', -1, null);
    }
  }
}

// ═══════════════════════════════════════════════════════════
//  BackgroundService static class
// ═══════════════════════════════════════════════════════════
class BackgroundService {
  BackgroundService._();
  static bool _initialized = false;
  static bool _running = false;
  static bool get isRunning => _running;

  static Future<void> init() async {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'gge_bot_service',
        channelName: 'GGE Bot',
        channelDescription: 'Keeps GGE Bot connected & trains',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  static Future<bool> start() async {
    if (_running) return true;
    try {
      await init();
      unawaited(FlutterForegroundTask.isIgnoringBatteryOptimizations.then((ignoring) async {
        if (!ignoring) {
          try { await FlutterForegroundTask.requestIgnoreBatteryOptimization(); } catch (_) {}
        }
      }).catchError((_) {}));
      await FlutterForegroundTask.startService(
        serviceId: 1001,
        notificationTitle: 'GGE Bot is active',
        notificationText: 'Watching for attacks & training...',
        callback: _callbackRef,
      );
      await Future.delayed(const Duration(milliseconds: 500));
      _running = await FlutterForegroundTask.isRunningService;
      GgeClient.allowBackgroundReconnect = _running;
      return _running;
    } catch (e) {
      return false;
    }
  }

  /// ✅ restart للـ service عشان يقرأ settings جديدة
  static Future<bool> restart() async {
    try {
      if (_running) {
        await FlutterForegroundTask.stopService();
        _running = false;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      return await start();
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!_running) return;
    try { await FlutterForegroundTask.stopService(); } catch (_) {}
    _running = false;
    GgeClient.allowBackgroundReconnect = false;
  }

  static Future<Map<String, dynamic>> readStatus() async {
    try {
      final status = await FlutterForegroundTask.getData<String>(key: 'bg_status');
      final time = await FlutterForegroundTask.getData<String>(key: 'bg_time');
      final extra = await FlutterForegroundTask.getData<String>(key: 'bg_extra');
      return {'status': status ?? 'never ran', 'time': time ?? '?', 'extra': extra ?? ''};
    } catch (e) {
      return {'status': 'read error: $e', 'time': '?', 'extra': ''};
    }
  }

  static Future<Map<String, dynamic>> readSamuraiStatus() async {
    try {
      final status = await FlutterForegroundTask.getData<String>(key: 'bg_samurai_status');
      final time = await FlutterForegroundTask.getData<String>(key: 'bg_samurai_time');
      final extra = await FlutterForegroundTask.getData<String>(key: 'bg_samurai_extra');
      return {'status': status ?? 'never ran', 'time': time ?? '?', 'extra': extra ?? ''};
    } catch (e) {
      return {'status': 'read error: $e', 'time': '?', 'extra': ''};
    }
  }
}