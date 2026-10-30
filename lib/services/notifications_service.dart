import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../gge_client.dart';
import '../l10n/strings.dart';
import '../models.dart';

class NotificationsService {
  NotificationsService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'gge_attacks';
  static const _soundKey = 'notif_sound_enabled';
  static const _enabledKey = 'notif_enabled';
  static const _allianceKey = 'notif_alliance_attacks';
  static const _permissionAskedKey = 'notif_permission_asked';

  static StreamSubscription<AttackAlert>? _sub;
  static GgeClient? _subscribedClient;

  static final List<AttackAlert> _history = [];
  static final StreamController<List<AttackAlert>> _listCtrl =
      StreamController.broadcast();
  static Stream<List<AttackAlert>> get historyStream => _listCtrl.stream;
  static List<AttackAlert> get history => List.unmodifiable(_history);

  static bool _soundEnabled = true;
  static bool _enabled = true;
  static bool _allianceAttacksEnabled = false;
  static bool _permissionGranted = false;
  static bool _ready = false;

  static bool get soundEnabled => _soundEnabled;
  static bool get enabled => _enabled;
  static bool get allianceAttacksEnabled => _allianceAttacksEnabled;
  static bool get permissionGranted => _permissionGranted;
  static bool get ready => _ready;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      _soundEnabled = prefs.getBool(_soundKey) ?? true;
      _enabled = prefs.getBool(_enabledKey) ?? true;
      _allianceAttacksEnabled = prefs.getBool(_allianceKey) ?? false;
    } catch (e) {
      TrafficLog.add('ER', '[Notif] prefs load failed: $e');
    }

    const icons = <String>[
      '@drawable/ic_launcher',
      '@mipmap/ic_launcher',
      '@android:drawable/sym_def_app_icon',
    ];

    var initOk = false;
    for (final icon in icons) {
      try {
        final androidInit = AndroidInitializationSettings(icon);
        final init = InitializationSettings(android: androidInit);
        await _plugin.initialize(init).timeout(const Duration(seconds: 3));
        TrafficLog.add('ST', '[Notif] plugin initialized with $icon');
        initOk = true;
        break;
      } catch (e) {
        TrafficLog.add('ER', '[Notif] init failed with $icon: $e');
      }
    }

    if (!initOk) {
      TrafficLog.add('ER', '[Notif] ALL icon attempts failed');
      return;
    }

    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        try {
          await android
              .createNotificationChannel(const AndroidNotificationChannel(
                _channelId,
                'Attack Alerts',
                description: 'Incoming attacks notifications',
                importance: Importance.max,
                playSound: true,
                enableVibration: true,
              ))
              .timeout(const Duration(seconds: 2));
        } catch (_) {}

        _permissionGranted =
            await android.areNotificationsEnabled() ?? false;
      }
      _ready = true;
    } catch (e) {
      TrafficLog.add('ER', '[Notif] init post-step error: $e');
      _ready = true;
    }
  }

  static Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return false;

      final granted = await android
          .requestNotificationsPermission()
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
      _permissionGranted = granted ?? false;

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_permissionAskedKey, true);
      } catch (_) {}

      if (_permissionGranted && !_ready) await init();
      return _permissionGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasAskedBefore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_permissionAskedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> checkPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return false;
      _permissionGranted =
          await android.areNotificationsEnabled() ?? false;
      return _permissionGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setSound(bool v) async {
    _soundEnabled = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_soundKey, v);
    } catch (_) {}
  }

  static Future<void> setEnabled(bool v) async {
    _enabled = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, v);
    } catch (_) {}
  }

  static Future<void> setAllianceAttacksEnabled(bool v) async {
    _allianceAttacksEnabled = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_allianceKey, v);
    } catch (_) {}
  }

  static void startListening() {
    final client = GgeClient();
    if (identical(_subscribedClient, client) && _sub != null) return;
    _sub?.cancel();
    _subscribedClient = client;
    _sub = client.attackStream.listen(_onAttack);
    TrafficLog.add('ST', '[Notif] listening');
    if (!_ready) unawaited(init());
  }

  static void stopListening() {
    _sub?.cancel();
    _sub = null;
    _subscribedClient = null;
  }

  static void clearHistory() {
    _history.clear();
    if (!_listCtrl.isClosed) _listCtrl.add([]);
  }

  static void removeAlert(int movementId) {
    _history.removeWhere((a) => a.movementId == movementId);
    if (!_listCtrl.isClosed) _listCtrl.add(List.unmodifiable(_history));
  }

  static Future<void> _onAttack(AttackAlert alert) async {
    if (!_enabled) return;
    if (alert.isAllianceAttack && !_allianceAttacksEnabled) return;

    final existingIdx = _history.indexWhere(
      (a) => a.movementId == alert.movementId,
    );
    final isUpdate = existingIdx >= 0;

    if (isUpdate) {
      _history[existingIdx] = alert;
    } else {
      _history.insert(0, alert);
      if (_history.length > 100) {
        _history.removeRange(100, _history.length);
      }
    }

    if (!_listCtrl.isClosed) _listCtrl.add(List.unmodifiable(_history));

    if (isUpdate) {
      TrafficLog.add('ST',
          '[Notif] alert UPDATED mid=${alert.movementId} (cancelled=${alert.isCancelled})');
      return;
    }

    if (!_ready) return;

    final allianceStr = (alert.attackerAlliance != null &&
            alert.attackerAlliance!.isNotEmpty)
        ? ' [${alert.attackerAlliance}]'
        : '';

    final targetName = alert.targetPlayerName;
    final hasTarget = alert.isAllianceAttack &&
        targetName != null &&
        targetName.isNotEmpty;

    final unitsLine = alert.units.isEmpty
        ? (S.isAr ? 'حركة مرصودة' : 'Movement detected')
        : alert.units
            .map((u) => '${S.unitName(u.displayName)}: ${u.amount}')
            .take(5)
            .join(' · ');

    final bigText = '${alert.remainingLabel} · ${alert.kingdomName}\n'
        '${S.isAr ? "من" : "From"}: ${alert.attackerName}$allianceStr'
        '${hasTarget ? "\n${S.isAr ? "على" : "To"}: $targetName" : ""}\n'
        '${S.isAr ? "إجمالي الجنود" : "Total units"}: ${alert.totalUnits}\n'
        '$unitsLine';

    final title = alert.isAllianceAttack
        ? '🛡️ ${alert.attackerName}${hasTarget ? " → $targetName" : ""}'
        : '⚔️ ${alert.attackerName}$allianceStr';

    final body = '${alert.remainingLabel} · '
        '${alert.totalUnits > 0 ? "${alert.totalUnits} ${S.units}" : "movement"}';

    try {
      await _plugin.show(
        alert.movementId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Attack Alerts',
            importance: Importance.max,
            priority: Priority.high,
            playSound: _soundEnabled,
            enableVibration: _soundEnabled,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            styleInformation: BigTextStyleInformation(bigText),
            fullScreenIntent: false,
            autoCancel: true,
          ),
        ),
        payload: '${alert.movementId}',
      );
    } catch (e) {
      TrafficLog.add('ER', '[Notif] show failed: $e');
    }
  }

  static Future<void> dispose() async {
    stopListening();
    await _listCtrl.close();
  }
}