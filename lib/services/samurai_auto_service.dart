import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../gge_client.dart';

class SamuraiAutoService {
  static final SamuraiAutoService instance = SamuraiAutoService._();
  SamuraiAutoService._();

  // ═══ مفاتيح SharedPreferences ═══
  static const kEnabled = 'samurai_auto_enabled';
  static const kSourceArea = 'samurai_auto_source_area';
  static const kSourceKid = 'samurai_auto_source_kid';
  static const kSourceX = 'samurai_auto_source_x';
  static const kSourceY = 'samurai_auto_source_y';
  static const kMinUnits = 'samurai_auto_min_units';
  static const kCommanderIds = 'samurai_auto_commander_ids';
  static const kToolId = 'samurai_auto_tool_id';
  static const kToolL = 'samurai_auto_tool_l';
  static const kToolR = 'samurai_auto_tool_r';
  static const kToolM = 'samurai_auto_tool_m';
  static const kWaves = 'samurai_auto_waves';
  static const kMaxLevel = 'samurai_auto_max_level';
  static const kSkipDaimyo = 'samurai_auto_skip_daimyo';
  static const kDelayMin = 'samurai_auto_delay_min';
  static const kDelayMax = 'samurai_auto_delay_max';
  static const kMaxAttacksDay = 'samurai_auto_max_attacks_day';
  static const kAttacksToday = 'samurai_auto_attacks_today';
  static const kAttacksDate = 'samurai_auto_attacks_date';

  // ═══ Defaults ═══
  static const int kDefaultMinUnits = 30;
  static const int kDefaultToolId = 166;
  static const int kDefaultToolL = 20;
  static const int kDefaultToolR = 20;
  static const int kDefaultToolM = 30;
  static const int kDefaultWaves = 3;
  static const int kDefaultMaxLevel = 60;
  static const int kDefaultDelayMin = 10;
  static const int kDefaultDelayMax = 15;
  static const int kDefaultMaxAttacksDay = 0; // 0 = unlimited

  final ValueNotifier<String> statusNotifier = ValueNotifier('Idle');

  // ═══ Getters ═══
  Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(kEnabled) ?? false;

  Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kEnabled, v);
    TrafficLog.add('ST', '[Samurai-Auto] enabled=$v');
  }

  Future<int> getSourceArea() async =>
      (await SharedPreferences.getInstance()).getInt(kSourceArea) ?? 0;

  Future<void> setSource({
    required int areaId, required int kid,
    required int x, required int y,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(kSourceArea, areaId);
    await p.setInt(kSourceKid, kid);
    await p.setInt(kSourceX, x);
    await p.setInt(kSourceY, y);
    TrafficLog.add('ST', '[Samurai-Auto] source: area=$areaId kid=$kid ($x,$y)');
  }

  Future<int> getMinUnits() async =>
      (await SharedPreferences.getInstance()).getInt(kMinUnits) ?? kDefaultMinUnits;

  Future<void> setMinUnits(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(kMinUnits, v);
  }

  Future<List<int>> getCommanderIds() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(kCommanderIds) ?? [];
    return raw.map((s) => int.tryParse(s) ?? 0).where((i) => i > 0).toList();
  }

  Future<void> setCommanderIds(List<int> ids) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(kCommanderIds, ids.map((e) => e.toString()).toList());
    TrafficLog.add('ST', '[Samurai-Auto] commanders: $ids');
  }

  Future<int> getToolId() async =>
      (await SharedPreferences.getInstance()).getInt(kToolId) ?? kDefaultToolId;

  Future<void> setToolId(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(kToolId, v);
  }

  Future<int> getToolL() async =>
      (await SharedPreferences.getInstance()).getInt(kToolL) ?? kDefaultToolL;

  Future<int> getToolR() async =>
      (await SharedPreferences.getInstance()).getInt(kToolR) ?? kDefaultToolR;

  Future<int> getToolM() async =>
      (await SharedPreferences.getInstance()).getInt(kToolM) ?? kDefaultToolM;

  Future<void> setToolAmounts({int? l, int? r, int? m}) async {
    final p = await SharedPreferences.getInstance();
    if (l != null) await p.setInt(kToolL, l);
    if (r != null) await p.setInt(kToolR, r);
    if (m != null) await p.setInt(kToolM, m);
  }

  Future<int> getWaves() async =>
      (await SharedPreferences.getInstance()).getInt(kWaves) ?? kDefaultWaves;

  Future<void> setWaves(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(kWaves, v.clamp(1, 3));
  }

  Future<int> getMaxLevel() async =>
      (await SharedPreferences.getInstance()).getInt(kMaxLevel) ?? kDefaultMaxLevel;

  Future<void> setMaxLevel(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(kMaxLevel, v.clamp(1, 100));
  }

  Future<bool> getSkipDaimyo() async =>
      (await SharedPreferences.getInstance()).getBool(kSkipDaimyo) ?? true;

  Future<void> setSkipDaimyo(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kSkipDaimyo, v);
  }

  Future<int> getDelayMin() async =>
      (await SharedPreferences.getInstance()).getInt(kDelayMin) ?? kDefaultDelayMin;

  Future<int> getDelayMax() async =>
      (await SharedPreferences.getInstance()).getInt(kDelayMax) ?? kDefaultDelayMax;

  Future<void> setDelay({int? min, int? max}) async {
    final p = await SharedPreferences.getInstance();
    if (min != null) await p.setInt(kDelayMin, min.clamp(5, 120));
    if (max != null) await p.setInt(kDelayMax, max.clamp(5, 120));
  }

  Future<int> getMaxAttacksDay() async =>
      (await SharedPreferences.getInstance()).getInt(kMaxAttacksDay) ?? kDefaultMaxAttacksDay;

  Future<void> setMaxAttacksDay(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(kMaxAttacksDay, v.clamp(0, 9999));
  }

  Future<int> getAttacksToday() async {
    final p = await SharedPreferences.getInstance();
    final today = _todayStr();
    final savedDate = p.getString(kAttacksDate) ?? '';
    if (savedDate != today) {
      await p.setInt(kAttacksToday, 0);
      await p.setString(kAttacksDate, today);
      return 0;
    }
    return p.getInt(kAttacksToday) ?? 0;
  }

  String _todayStr() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}