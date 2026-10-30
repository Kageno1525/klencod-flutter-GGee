import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════
class OwnedCastle {
  final int kingdomId;
  final int areaType;
  final int x, y, areaId;
  final String name;

  OwnedCastle({
    required this.kingdomId,
    required this.areaType,
    required this.x,
    required this.y,
    required this.areaId,
    required this.name,
  });

  String get typeName => switch (areaType) {
        1 => 'Main Castle',
        4 => 'Outpost',
        12 => 'External Kingdom',
        10 => 'Resource Village',
        _ => 'Type $areaType',
      };

  String get kingdomName => switch (kingdomId) {
        0 => 'Great Empire',
        1 => 'Burning Sands',
        2 => 'Everwinter',
        3 => 'Fire Peaks',
        4 => 'Storm Islands',
        _ => 'K$kingdomId',
      };

  String get displayName => name.isNotEmpty ? name : '$typeName ($x,$y)';
  String get fullLabel => '$displayName · $kingdomName';
}

// ═══════════════════════════════════════════
class UnitCatalogEntry {
  final int wodId;
  final String? type;
  final String? role;
  final String? name;
  final int? fightType;

  UnitCatalogEntry({
    required this.wodId,
    this.type,
    this.role,
    this.name,
    this.fightType,
  });

  bool get isCombat => role == 'melee' || role == 'ranged';

  bool get isDefensive {
    final t = type ?? '';
    return t.contains('Def') ||
        t.contains('Militia') ||
        t.contains('Peasant') ||
        t.contains('Anti') ||
        t.contains('Wall') ||
        t.contains('Gate') ||
        t.contains('Moat');
  }

  bool get isTrainable => isCombat;

  String get displayName {
    final t = (type ?? '').replaceFirst('Barracks_Unit_', '');
    return t.isEmpty ? 'Unit #$wodId' : t;
  }
}

// ═══════════════════════════════════════════
class CastleUnit {
  final int wodId;
  final int amount;
  final UnitCatalogEntry? info;

  CastleUnit({required this.wodId, required this.amount, this.info});

  String get displayName => info?.displayName ?? 'Unit #$wodId';

  IconData get icon {
    if (info?.role == 'ranged') return Icons.gps_fixed;
    if (info?.role == 'melee') return Icons.gavel;
    return Icons.shield;
  }

  Color get roleColor {
    if (info?.role == 'ranged') return const Color(0xFF06B6D4);
    if (info?.role == 'melee') return const Color(0xFFEF4444);
    return const Color(0xFF90A4AE);
  }

  bool get isCombat => info?.isCombat == true;
  bool get isDefensive => info?.isDefensive == true;
}

// ═══════════════════════════════════════════
class Lord {
  final int id;
  final int visibleIndex;
  final int factionId;
  final String? name;
  final int level;

  Lord({
    required this.id,
    required this.visibleIndex,
    required this.factionId,
    this.name,
    this.level = 1,
  });

  String get displayName {
    if (name?.isNotEmpty == true) return name!;
    return 'Lord ${visibleIndex + 1}';
  }
}

// ═══════════════════════════════════════════
class LordMovement {
  final int movementId;
  final int type;
  final int totalTime; // TT — travel time
  final int paidTime; // PT — travel time paid
  final int targetX;
  final int targetY;
  final int targetKid;
  final String? targetPlayerName;
  final String? targetAllianceName;
  final DateTime fetchedAt;

  /// ⚠️ مدة الدعم الكلية في قلعة الحليف (TWD من UM)
  /// null لو الحركة مش support أو مفيش بيانات support
  final int? stationTotalSeconds;

  /// ⚠️ مدة الدعم المدفوعة لحد الآن (PWD من UM)
  final int? stationPaidSeconds;

  LordMovement({
    required this.movementId,
    required this.type,
    required this.totalTime,
    required this.paidTime,
    required this.targetX,
    required this.targetY,
    required this.targetKid,
    this.targetPlayerName,
    this.targetAllianceName,
    DateTime? fetchedAt,
    this.stationTotalSeconds,
    this.stationPaidSeconds,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  // ─── حركة السفر ─────────────────────────────
  int get timeRemaining => totalTime - paidTime;

  int get liveRemainingSeconds {
    final elapsed = DateTime.now().difference(fetchedAt).inSeconds;
    return (timeRemaining - elapsed).clamp(0, 999999);
  }

  bool get isArrived => liveRemainingSeconds <= 0;

  /// عدد الثواني المتبقية من الدعم في قلعة الحليف.
  /// القيمة 0 لو الحركة مش stationed أو معلومات الدعم مش متوفرة.
  int get stationRemainingSeconds {
    if (stationTotalSeconds == null || stationPaidSeconds == null) return 0;
    final elapsed = DateTime.now().difference(fetchedAt).inSeconds;
    return (stationTotalSeconds! - stationPaidSeconds! - elapsed)
        .clamp(0, 999999);
  }

  /// الوقت المطلق اللي القائد هيرجع فيه من الدعم.
  DateTime? get stationReturnAt {
    if (stationTotalSeconds == null || stationPaidSeconds == null) return null;
    return fetchedAt
        .add(Duration(seconds: stationTotalSeconds! - stationPaidSeconds!));
  }

  /// نوع support + وصل + لسه في الدعم
  bool get isStationed =>
      type == 1 && isArrived && stationRemainingSeconds > 0;

  bool get isReturning => type == 2;

  /// حركة لسه "شغالة" فعلياً (تستحق العداد والتحديث)
  bool get isActive => !isArrived || isStationed;

  DateTime get startedAt => fetchedAt.subtract(Duration(seconds: paidTime));
  DateTime get arrivalAt => fetchedAt.add(Duration(seconds: timeRemaining));

  static String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  String get startedAtLabel => _fmt(startedAt);
  String get arrivalAtLabel => _fmt(arrivalAt);
  String? get stationReturnAtLabel =>
      stationReturnAt == null ? null : _fmt(stationReturnAt!);

  /// العداد الحي — بيتحدث كل ثانية في الـ UI.
  /// لو stationed → عدّاد الدعم، غير كده → عدّاد السفر.
  String get timeLabel {
    if (isStationed) {
      final s = stationRemainingSeconds;
      if (s <= 0) return 'Expiring...';
      final h = s ~/ 3600;
      final m = (s % 3600) ~/ 60;
      final sec = s % 60;
      if (h > 0) return '${h}h ${m}m';
      if (m > 0) return '${m}m ${sec}s';
      return '${sec}s';
    }
    final s = liveRemainingSeconds;
    if (s <= 0) return type == 1 ? 'Stationed' : 'Arrived';
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${sec}s';
    return '${sec}s';
  }

  String get actionWithTimeLabel => '${actionLabel} · $timeLabel';

  String get actionLabel {
    switch (type) {
      case 0:
        return 'Attacking';
      case 1:
        return 'Supporting / Smuggling';
      case 2:
        return 'Returning';
      case 3:
        return 'Transporting';
      default:
        return 'Moving';
    }
  }

  String get scheduleLabel => '$startedAtLabel → $arrivalAtLabel';
}

// ═══════════════════════════════════════════
class CommanderInfo {
  final Lord lord;
  final LordMovement? movement;

  CommanderInfo({required this.lord, this.movement});

  /// القائد "مشغول" فقط لو:
  ///   • لسه بيسافر (مش وصل) ، أو
  ///   • متمركز في قلعة حليف ووقت الدعم لسه ما خلصش
  ///
  /// بعد السفر + انتهاء الدعم → القائد متاح فوراً بدون refresh.
  bool get isBusy => movement != null && movement!.isActive;
}

// ═══════════════════════════════════════════
class XtMessage {
  final String command;
  final int roomId;
  final int resultCode;
  final String? payload;
  final String raw;

  XtMessage(this.command, this.roomId, this.resultCode, this.payload, this.raw);
}

// ═══════════════════════════════════════════
class AllyCastle {
  final int kingdomId;
  final int areaId;
  final int x, y;
  final int areaType;

  AllyCastle({
    required this.kingdomId,
    required this.areaId,
    required this.x,
    required this.y,
    required this.areaType,
  });

  String get kingdomName => switch (kingdomId) {
        0 => 'Great Empire',
        1 => 'Burning Sands',
        2 => 'Everwinter',
        3 => 'Fire Peaks',
        4 => 'Storm Islands',
        _ => 'K$kingdomId',
      };

  String get typeName => switch (areaType) {
        1 => 'Main',
        4 => 'Outpost',
        12 => 'External',
        10 => 'Village',
        _ => 'T$areaType',
      };

  String get displayLabel => '$typeName · $kingdomName ($x,$y)';
}

// ═══════════════════════════════════════════
class AllyMember {
  final int playerId;
  final String name;
  final int level;
  final int peaceTimeSeconds;
  final List<AllyCastle> castles;

  AllyMember({
    required this.playerId,
    required this.name,
    required this.level,
    required this.peaceTimeSeconds,
    required this.castles,
  });

  bool get hasPeace => peaceTimeSeconds > 0;

  String get peaceLabel {
    if (!hasPeace) return 'No peace';
    final s = peaceTimeSeconds;
    final d = s ~/ 86400;
    final h = (s % 86400) ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  double closestDistance(int refKid, int refX, int refY) {
    if (castles.isEmpty) return double.infinity;
    double best = double.infinity;
    for (final c in castles) {
      if (c.kingdomId != refKid) continue;
      final dx = (c.x - refX).toDouble();
      final dy = (c.y - refY).toDouble();
      final d = (dx * dx + dy * dy);
      if (d < best) best = d;
    }
    return best == double.infinity ? double.infinity : _sqrt(best);
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double g = x / 2;
    for (int i = 0; i < 15; i++) {
      g = (g + x / g) / 2;
    }
    return g;
  }

  AllyCastle? castleIn(int kingdomId) {
    try {
      return castles.firstWhere((c) => c.kingdomId == kingdomId);
    } catch (_) {
      return null;
    }
  }
}

// ═══════════════════════════════════════════
const Map<int, String> ggeErrors = {
  0: 'Success',
  1: 'General error',
  2: 'Invalid parameter',
  5: 'Invalid object',
  6: 'Commander not available at source',
  7: 'Target not in same kingdom',
  13: 'Not enough troops',
  27: 'Account is banned',
  50: 'Wrong mode',
  55: 'Not enough resources',
  87: 'Missing required building',
  88: 'Too much units',
  91: 'Unit not sendable from this castle',
  93: 'Exceeds max count',
  95: 'Cooling down',
  101: 'Missing units',
  108: 'Unknown movement',
  114: 'Alliance not found',
  120: 'Level too low',
  121: 'Travel time too long',
  148: 'Already transferring',
  175: 'Invalid kingdom',
  178: 'Kingdom not available',
  180: 'Max kingdom goods movements',
  181: 'Max kingdom army movements',
  182: 'Kingdom movements not available',
  203: 'Invalid area',
  212: 'Castle has movements',
  218: 'Lord unavailable (busy)',
  219: 'Invalid lord id',
  222: 'Lord in movement',
  233: 'Target not owned',
  256: 'Lord is used',
  404: 'Lord needed',
  409: 'Invalid login token',
  414: 'Minuteskip blocked',
  453: 'Retry wait',
};

String errorName(int code) => ggeErrors[code] ?? 'Error $code';

// ═══════════════════════════════════════════
class AppStorage {
  static const _kUser = 'username';
  static const _kPass = 'password';
  static const _kToken = 'login_token';
  static const _kDark = 'darkMode';
  static const _kLang = 'languageCode';
  static const _kLoggedIn = 'is_logged_in';

  static Future<String?> getUsername() async =>
      (await SharedPreferences.getInstance()).getString(_kUser);
  static Future<void> setUsername(String v) async =>
      (await SharedPreferences.getInstance()).setString(_kUser, v);

  static Future<String?> getPassword() async =>
      (await SharedPreferences.getInstance()).getString(_kPass);
  static Future<void> setPassword(String v) async =>
      (await SharedPreferences.getInstance()).setString(_kPass, v);

  static Future<String?> getToken() async =>
      (await SharedPreferences.getInstance()).getString(_kToken);
  static Future<void> setToken(String v) async =>
      (await SharedPreferences.getInstance()).setString(_kToken, v);

  static Future<bool> getDarkMode() async =>
      (await SharedPreferences.getInstance()).getBool(_kDark) ?? true;
  static Future<void> setDarkMode(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kDark, v);

  static Future<String> getLanguageCode() async =>
      (await SharedPreferences.getInstance()).getString(_kLang) ?? 'ar';
  static Future<void> setLanguageCode(String v) async =>
      (await SharedPreferences.getInstance()).setString(_kLang, v);

  static Future<bool> getLoggedIn() async =>
      (await SharedPreferences.getInstance()).getBool(_kLoggedIn) ?? false;
  static Future<void> setLoggedIn(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kLoggedIn, v);

  static Future<void> clearCredentials() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kUser);
    await p.remove(_kPass);
    await p.remove(_kToken);
    await p.remove(_kLoggedIn);
  }
}

// ═══════════════════════════════════════════
class CastleStats {
  final int areaId;
  final int kingdomId;
  final String? name;
  final int wood, stone, food, coal, oil, glass, iron, honey, mead, aqua;
  final double deltaWood, deltaStone, deltaFood, deltaCoal, deltaOil,
      deltaGlass, deltaIron, deltaHoney, deltaMead, deltaAqua;
  final int maxWood, maxStone, maxFood, maxCoal, maxOil, maxGlass,
      maxIron, maxHoney, maxMead, maxAqua;
  final List<CastleUnit> units;
  final List<CastleUnit> strongholdUnits;
  final List<CastleUnit> hospitalUnits;
  final List<CastleUnit> travelingUnits;
  final int defense;
  final int marketCarriages;
  final bool hasBarracks, hasSiegeWorkshop, hasDefenseWorkshop, hasHospital;

  CastleStats({
    required this.areaId,
    required this.kingdomId,
    this.name,
    required this.wood, required this.stone, required this.food,
    required this.coal, required this.oil, required this.glass,
    required this.iron, required this.honey, required this.mead,
    required this.aqua,
    required this.deltaWood, required this.deltaStone, required this.deltaFood,
    required this.deltaCoal, required this.deltaOil, required this.deltaGlass,
    required this.deltaIron, required this.deltaHoney, required this.deltaMead,
    required this.deltaAqua,
    required this.maxWood, required this.maxStone, required this.maxFood,
    required this.maxCoal, required this.maxOil, required this.maxGlass,
    required this.maxIron, required this.maxHoney, required this.maxMead,
    required this.maxAqua,
    required this.units,
    required this.strongholdUnits,
    required this.hospitalUnits,
    required this.travelingUnits,
    required this.defense,
    required this.marketCarriages,
    required this.hasBarracks,
    required this.hasSiegeWorkshop,
    required this.hasDefenseWorkshop,
    required this.hasHospital,
  });

  int get totalUnits => units.fold<int>(0, (s, u) => s + u.amount);
  int get totalTraveling => travelingUnits.fold<int>(0, (s, u) => s + u.amount);

  String get kingdomName => switch (kingdomId) {
        0 => 'Great Empire',
        1 => 'Burning Sands',
        2 => 'Everwinter',
        3 => 'Fire Peaks',
        4 => 'Storm Islands',
        _ => 'K$kingdomId',
      };
}

// ═══════════════════════════════════════════
class AttackUnit {
  final int wodId;
  final int amount;
  final String position;
  final String? name;

  AttackUnit({
    required this.wodId,
    required this.amount,
    required this.position,
    this.name,
  });

  String get displayName => name ?? 'Unit #$wodId';

  IconData get icon {
    switch (position) {
      case 'courtyard':
        return Icons.castle_rounded;
      default:
        return Icons.shield_rounded;
    }
  }
}

// ═══════════════════════════════════════════
class AttackAlert {
  final int movementId;
  final int attackerId;
  final String attackerName;
  final String? attackerAlliance;
  final String? attackerCastleName;
  final int attackerAreaId;
  final int attackerX, attackerY;
  final int targetX, targetY;
  final String? targetCastleName;
  final int targetAreaId;
  final String? targetPlayerName;
  final int kingdomId;
  final int totalTime;
  final int paidTime;
  final List<AttackUnit> units;
  final DateTime receivedAt;
  final bool isAllianceAttack;
  final DateTime? cancelledAt;

  AttackAlert({
    required this.movementId,
    required this.attackerId,
    required this.attackerName,
    this.attackerAlliance,
    this.attackerCastleName,
    this.attackerAreaId = 0,
    this.attackerX = 0,
    this.attackerY = 0,
    required this.targetX,
    required this.targetY,
    this.targetCastleName,
    this.targetAreaId = 0,
    this.targetPlayerName,
    required this.kingdomId,
    required this.totalTime,
    required this.paidTime,
    required this.units,
    required this.receivedAt,
    this.isAllianceAttack = false,
    this.cancelledAt,
  });

  String? get attackerAlly => attackerAlliance;

  DateTime get startedAt => receivedAt.subtract(Duration(seconds: paidTime));
  DateTime get arrivalAt => receivedAt.add(Duration(seconds: remainingSeconds));

  bool get isCancelled => cancelledAt != null;
  bool get isArrived => !isCancelled && DateTime.now().isAfter(arrivalAt);

  int get remainingSeconds => (totalTime - paidTime).clamp(0, 999999);

  Duration get remainingNow {
    if (isCancelled) return Duration.zero;
    final diff = arrivalAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String get liveRemainingLabel {
    if (isCancelled) return 'Recalled';
    if (isArrived) return 'Arrived';
    final d = remainingNow;
    if (d.inSeconds <= 0) return 'Arrived';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String get statusKey {
    if (isCancelled) return 'cancelled';
    if (isArrived) return 'arrived';
    return 'incoming';
  }

  static String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  String get startedAtLabel => _fmt(startedAt);
  String get arrivalAtLabel => _fmt(arrivalAt);
  String? get cancelledAtLabel => cancelledAt == null ? null : _fmt(cancelledAt!);

  String get remainingLabel {
    final s = remainingSeconds;
    if (s <= 0) return 'Arrived';
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${sec}s';
    return '${sec}s';
  }

  int get totalUnits => units.fold(0, (s, u) => s + u.amount);
  bool get hasUnits => units.isNotEmpty;
  bool get isCritical => remainingSeconds > 0 && remainingSeconds < 300;

  String get kingdomName => switch (kingdomId) {
        0 => 'Great Empire',
        1 => 'Burning Sands',
        2 => 'Everwinter',
        3 => 'Fire Peaks',
        4 => 'Storm Islands',
        _ => 'K$kingdomId',
      };

  String get shortSummary {
    final unitsPart = hasUnits ? ' · $totalUnits units' : '';
    return '$attackerName → $liveRemainingLabel$unitsPart';
  }

  Map<String, int> get groupedUnits {
    final map = <String, int>{};
    for (final u in units) {
      map[u.displayName] = (map[u.displayName] ?? 0) + u.amount;
    }
    return map;
  }
}