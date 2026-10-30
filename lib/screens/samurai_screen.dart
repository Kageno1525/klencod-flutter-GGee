import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gge/gge_client.dart';
import 'package:gge/models.dart';
import 'package:gge/services/samurai_service.dart';
import 'package:gge/theme.dart';
import 'package:gge/widgets/animated_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color kSamuraiRed = Color(0xFFDC2626);
const Color kSamuraiDark = Color(0xFF7F1D1D);
const Color kSamuraiGold = Color(0xFFD4AF37);

class SamuraiScreen extends StatefulWidget {
  final GgeClient client;
  const SamuraiScreen({super.key, required this.client});

  @override
  State<SamuraiScreen> createState() => _SamuraiScreenState();
}

class _SamuraiScreenState extends State<SamuraiScreen> {
  late final SamuraiService _svc;
  late SamuraiSettings _settings;

  List<OwnedCastle> _castles = [];
  OwnedCastle? _source;
  List<SamuraiCamp> _camps = [];
  bool _scanning = false;
  int _scanDone = 0, _scanTotal = 0;
  bool _loading = true;

  // ⚙️ إعدادات الهجوم الافتراضية (تُحفظ في SharedPreferences)
  SamuraiAttackConfig _defaultConfig = const SamuraiAttackConfig();
  static const _kDefaultWaves = 'samurai_default_waves';
  static const _kDefaultToolId = 'samurai_default_tool_id';
  static const _kDefaultToolL = 'samurai_default_tool_l';
  static const _kDefaultToolR = 'samurai_default_tool_r';
  static const _kDefaultToolM = 'samurai_default_tool_m';

  @override
  void initState() {
    super.initState();
    _svc = SamuraiService(widget.client);
    _svc.loadCooldowns();
    _init();
  }

  Future<void> _init() async {
    _settings = await SamuraiSettings.load();
    await _loadDefaultConfig();
    try {
      final castles = await widget.client.getCastles();
      if (!mounted) return;
      setState(() {
        _castles = castles;
        if (castles.isNotEmpty) {
          try {
            _source = castles
                .firstWhere((c) => c.areaId == _settings.sourceAreaId);
          } catch (_) {
            try {
              _source = castles.firstWhere((c) => c.areaType == 1);
            } catch (_) {
              _source = castles.first;
            }
          }
          _settings.sourceAreaId = _source!.areaId;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDefaultConfig() async {
    final p = await SharedPreferences.getInstance();
    final waves = p.getInt(_kDefaultWaves) ?? 3;
    final toolId = p.getInt(_kDefaultToolId) ?? 166;
    final toolL = p.getInt(_kDefaultToolL) ?? 20;
    final toolR = p.getInt(_kDefaultToolR) ?? 20;
    final toolM = p.getInt(_kDefaultToolM) ?? 30;
    _defaultConfig = SamuraiAttackConfig(
      waves: waves,
      toolId: toolId > 0 ? toolId : null,
      toolL: toolL, toolR: toolR, toolM: toolM,
    );
  }

  Future<void> _saveDefaultConfig(SamuraiAttackConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kDefaultWaves, c.waves);
    await p.setInt(_kDefaultToolId, c.toolId ?? 0);
    await p.setInt(_kDefaultToolL, c.toolL);
    await p.setInt(_kDefaultToolR, c.toolR);
    await p.setInt(_kDefaultToolM, c.toolM);
  }

  Future<void> _scan() async {
    if (_source == null) {
      _snack('اختر قلعة مصدر أولاً', color: AppTheme.red);
      return;
    }
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _camps = [];
      _scanDone = 0;
      _scanTotal = 0;
    });
    try {
      final found = await _svc.scanArea(
        source: _source!,
        radiusTiles: _settings.radiusTiles,
        onProgress: (d, t) {
          if (!mounted) return;
          setState(() {
            _scanDone = d;
            _scanTotal = t;
          });
        },
      );
      if (!mounted) return;
      found.sort((a, b) =>
          a.distanceFromSource.compareTo(b.distanceFromSource));
      setState(() {
        _camps = found;
        _scanning = false;
      });
      _snack('تم العثور على ${found.length} معسكر ساموراي',
          color: found.isEmpty ? AppTheme.orange : AppTheme.green);
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _snack('$e', color: AppTheme.red);
    }
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(decoration: TextDecoration.none),
            maxLines: 5),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AppTheme.background(context),
          SafeArea(
            child: Column(
              children: [
                _header(),
                if (_loading)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: kSamuraiRed),
                    ),
                  )
                else
                  Expanded(child: _content()),
              ],
            ),
          ),
          if (_source != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: GradientButton(
                label: _scanning
                    ? 'جارٍ المسح ($_scanDone/$_scanTotal)'
                    : 'مسح معسكرات الساموراي (${_settings.radiusTiles} tile)',
                icon: Icons.shield_rounded,
                gradient: const LinearGradient(
                    colors: [kSamuraiRed, kSamuraiDark]),
                loading: _scanning,
                onPressed: _scanning ? null : _scan,
              ),
            ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          AppIconBtn(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.pop(context),
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('معسكرات الساموراي',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textColor(context),
                        decoration: TextDecoration.none)),
                Text('${_camps.length} معسكر',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.subTextColor(context),
                        decoration: TextDecoration.none)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    return Column(
      children: [
        _sourcePicker(),
        _filterBar(),
        if (_scanning) _progressBar(),
        Expanded(
          child: _camps.isEmpty
              ? _emptyView()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: _camps.length,
                  itemBuilder: (_, i) => FadeSlideIn(
                    delay: Duration(milliseconds: 30 + i * 30),
                    child: _campCard(_camps[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _sourcePicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AppTheme.glassCard(
        context: context,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: kSamuraiRed.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.castle_rounded,
                  color: kSamuraiRed, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<OwnedCastle>(
                  value: _source,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textColor(context)),
                  items: _castles
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.fullLabel,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: AppTheme.textColor(context),
                                    fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _source = v;
                      _settings.sourceAreaId = v.areaId;
                      _settings.save();
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: _openRadiusDialog,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kSamuraiGold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: kSamuraiGold.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.place_rounded,
                    color: kSamuraiGold, size: 14),
                const SizedBox(width: 6),
                Text('${_settings.radiusTiles} tile',
                    style: const TextStyle(
                        color: kSamuraiGold,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: _scanning && _scanTotal > 0 ? _scanDone / _scanTotal : null,
          minHeight: 4,
          backgroundColor: kSamuraiRed.withOpacity(0.1),
          valueColor: const AlwaysStoppedAnimation(kSamuraiRed),
        ),
      ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kSamuraiRed.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: kSamuraiRed.withOpacity(0.3)),
              ),
              child: Icon(Icons.shield_rounded,
                  size: 48, color: kSamuraiRed.withOpacity(0.7)),
            ),
            const SizedBox(height: 16),
            Text('مفيش معسكرات لسه',
                style: TextStyle(
                    color: AppTheme.textColor(context),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none)),
            const SizedBox(height: 4),
            Text('دوس "مسح" عشان تبدأ',
                style: TextStyle(
                    color: AppTheme.subTextColor(context),
                    fontSize: 11,
                    decoration: TextDecoration.none)),
          ],
        ),
      ),
    );
  }

  Widget _campCard(SamuraiCamp c) {
    final inCooldown = _svc.isCampInCooldown(c);
    final cd = _svc.campCooldownRemaining(c);
    final dead = c.isDead;
    final levelOk = c.level > 0 || c.level2 > 0;

    final borderColor = dead
        ? Colors.grey
        : (inCooldown ? Colors.orange : kSamuraiRed);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: (inCooldown || dead) ? null : () => _openCampSheet(c),
        child: Opacity(
          opacity: (inCooldown || dead) ? 0.55 : 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.isDark(context)
                  ? Colors.white.withOpacity(0.04)
                  : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.3),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: (dead
                            ? Colors.grey
                            : inCooldown
                                ? Colors.orange
                                : kSamuraiRed)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                      dead
                          ? Icons.dangerous_rounded
                          : inCooldown
                              ? Icons.hourglass_top_rounded
                              : Icons.shield_rounded,
                      color: dead
                          ? Colors.grey
                          : inCooldown
                              ? Colors.orange
                              : kSamuraiRed,
                      size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(c.coordsLabel,
                            style: TextStyle(
                                color: AppTheme.textColor(context),
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                decoration: TextDecoration.none)),
                        const SizedBox(width: 8),
                        if (dead)
                          _pill('مدمر', Colors.grey)
                        else if (inCooldown)
                          _pill(
                              '${cd.inMinutes}:${(cd.inSeconds % 60).toString().padLeft(2, "0")}',
                              Colors.orange)
                        else if (c.type != 29)
                          _pill('HP ${c.hp}', kSamuraiRed)
                        else if (!levelOk)
                          _pill('Lv ؟', Colors.amber),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        Text(
                            '${c.typeName} · Lv ${c.level > 0 ? c.level : c.level2}',
                            style: TextStyle(
                                color: AppTheme.subTextColor(context),
                                fontSize: 10.5,
                                decoration: TextDecoration.none)),
                        const SizedBox(width: 8),
                        Icon(Icons.straighten_rounded,
                            size: 11,
                            color: AppTheme.subTextColor(context)),
                        const SizedBox(width: 2),
                        Text('${c.distanceFromSource.toStringAsFixed(0)}t',
                            style: TextStyle(
                                color: AppTheme.subTextColor(context),
                                fontSize: 10.5,
                                decoration: TextDecoration.none)),
                      ]),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: AppTheme.subTextColor(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Text(text,
            style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none)),
      );

  Future<void> _openCampSheet(SamuraiCamp c) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SamuraiAttackSheet(
        client: widget.client,
        source: _source!,
        camp: c,
        svc: _svc,
        defaultConfig: _defaultConfig,
        onConfigChanged: (cfg) {
          _defaultConfig = cfg;
          _saveDefaultConfig(cfg);
        },
      ),
    );
    if (result == true && mounted) {
      setState(() {
        final i = _camps.indexWhere((x) => x.key == c.key);
        if (i >= 0) {
          _camps[i] = _camps[i].copyWith(
            lastAttackAt: DateTime.now(),
          );
        }
      });
    }
  }

  void _openRadiusDialog() {
    double temp = _settings.radiusTiles.toDouble();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          title: const Text('نطاق البحث',
              style: TextStyle(decoration: TextDecoration.none)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${temp.toInt()} tile',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none)),
            Slider(
              value: temp,
              min: kSamuraiRadiusMin.toDouble(),
              max: kSamuraiRadiusMax.toDouble(),
              divisions:
                  (kSamuraiRadiusMax - kSamuraiRadiusMin) ~/
                      kSamuraiRadiusStep,
              activeColor: kSamuraiRed,
              label: '${temp.toInt()}',
              onChanged: (v) => setSt(() => temp =
                  (v / kSamuraiRadiusStep).round() *
                      kSamuraiRadiusStep.toDouble()),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _settings.radiusTiles = temp.toInt();
                  _settings.save();
                });
                Navigator.pop(ctx);
              },
              child: const Text('موافق'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  Attack sheet
// ═══════════════════════════════════════════════════════
class _SamuraiAttackSheet extends StatefulWidget {
  final GgeClient client;
  final OwnedCastle source;
  final SamuraiCamp camp;
  final SamuraiService svc;
  final SamuraiAttackConfig defaultConfig;
  final ValueChanged<SamuraiAttackConfig> onConfigChanged;

  const _SamuraiAttackSheet({
    required this.client,
    required this.source,
    required this.camp,
    required this.svc,
    required this.defaultConfig,
    required this.onConfigChanged,
  });

  @override
  State<_SamuraiAttackSheet> createState() => _SamuraiAttackSheetState();
}

class _SamuraiAttackSheetState extends State<_SamuraiAttackSheet> {
  List<CastleUnit> _units = [];
  List<CommanderInfo> _commanders = [];
  Lord? _selectedLord;

  late SamuraiAttackConfig _config;
  int? _manualLevel;

  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _config = widget.defaultConfig;
    _manualLevel =
        widget.camp.level > 0 ? widget.camp.level : null;
    _load();
  }

  Future<void> _load() async {
    try {
      final catalog = await widget.client.loadCatalog();
      final units = await widget.client.getCastleUnits(
          widget.source.kingdomId, widget.source.areaId, catalog);
      final sendable =
          units.where((u) => u.isCombat && u.amount > 0).toList();
      final cmds = await widget.client.getCommanders();

      if (!mounted) return;
      setState(() {
        _units = sendable;
        _commanders = cmds;
        final free = cmds.where((c) => !c.isBusy).toList();
        if (free.isNotEmpty) {
          try {
            _selectedLord = free.firstWhere((c) => c.lord.id != 0).lord;
          } catch (_) {
            _selectedLord = free.first.lord;
          }
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _totalUnits =>
      _units.fold<int>(0, (s, u) => s + u.amount);

  int get _effectiveLevel {
    final m = _manualLevel ?? 0;
    if (m > 0) return m;
    if (widget.camp.level > 0) return widget.camp.level;
    if (widget.camp.level2 > 0) return widget.camp.level2;
    return 0;
  }

  Future<void> _attack() async {
    if (_selectedLord == null) {
      _snack('اختر قائد', color: AppTheme.red);
      return;
    }
    if (_units.isEmpty) {
      _snack('مفيش وحدات قتالية في القلعة', color: AppTheme.orange);
      return;
    }
    if (_effectiveLevel <= 0) {
      _snack('محتاج تحدد Level المعسكر يدويًا', color: AppTheme.orange);
      return;
    }

    widget.onConfigChanged(_config);

    setState(() => _sending = true);
    final res = await widget.svc.attack(
      camp: widget.camp,
      source: widget.source,
      lordId: _selectedLord!.id,
      availableUnits: _units,
      config: _config,
      manualLevel: _manualLevel,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (res.success) {
      if (mounted) {
        _snack(
          '✅ ${res.wavesSent} waves · ${res.totalUnits} وحدة'
          '${res.usedTools ? " · ${res.toolsUsed} أداة" : " · بدون أدوات"}',
          color: AppTheme.green,
        );
      }
      Navigator.pop(context, true);
    } else {
      _snack(res.error ?? 'فشل الهجوم', color: AppTheme.red);
    }
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(decoration: TextDecoration.none),
            maxLines: 5),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.camp;
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0B0B14),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 44, height: 5,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [kSamuraiRed, kSamuraiDark]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shield_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${c.typeName} ${c.coordsLabel}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.none)),
                      Text(
                          'Lv ${_effectiveLevel}'
                          '${c.type != 29 ? " · HP ${c.hp}" : ""}'
                          ' · ${_totalUnits} وحدة متاحة',
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              decoration: TextDecoration.none)),
                    ],
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const Divider(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: kSamuraiRed))
                  : ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      children: [
                        _levelCard(),
                        const SizedBox(height: 12),
                        _lordSection(),
                        const SizedBox(height: 12),
                        _configCard(),
                        const SizedBox(height: 12),
                        _previewCard(),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _sending || _loading ? null : _attack,
                    icon: _sending
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.gavel_rounded),
                    label: Text(
                        _sending ? 'جارٍ الإرسال...' : 'هجوم',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            decoration: TextDecoration.none)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kSamuraiRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── كارت الـ level ─────────────────────────────
  Widget _levelCard() {
    final autoLevel = widget.camp.level > 0 ? widget.camp.level : 0;
    final needManual = autoLevel <= 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: (needManual ? Colors.amber : Colors.green)
                .withOpacity(0.4)),
      ),
      child: Row(children: [
        Icon(needManual ? Icons.warning_amber : Icons.info_outline,
            color: needManual ? Colors.amber : Colors.green, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  needManual
                      ? 'Level غير معروف — أدخله يدويًا'
                      : 'Level تلقائي: $autoLevel',
                  style: TextStyle(
                      color: needManual ? Colors.amber : Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none)),
              if (needManual)
                const Text(
                    'الحد الأقصى للوحدات والأدوات يعتمد على Level',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        decoration: TextDecoration.none)),
            ],
          ),
        ),
        SizedBox(
          width: 70,
          child: TextFormField(
            key: ValueKey('level_${_manualLevel ?? 0}'),
            initialValue:
                _manualLevel == null ? '' : _manualLevel.toString(),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: kSamuraiGold,
                fontSize: 14,
                fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'Lv',
              hintStyle: const TextStyle(
                  color: Colors.white30, fontSize: 11),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: kSamuraiGold)),
            ),
            onChanged: (s) {
              final v = int.tryParse(s);
              setState(() => _manualLevel = (v != null && v > 0) ? v : null);
            },
          ),
        ),
      ]),
    );
  }

  // ─── كارت الإعدادات ─────────────────────────────
  Widget _configCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSamuraiGold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.settings_rounded, color: kSamuraiGold, size: 16),
            SizedBox(width: 6),
            Text('⚙️ إعدادات الأمر',
                style: TextStyle(
                    color: kSamuraiGold,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none)),
          ]),
          const SizedBox(height: 8),

          // عدد الـ waves
          Row(children: [
            const Text('Waves:',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    decoration: TextDecoration.none)),
            Expanded(
              child: Slider(
                value: _config.waves.toDouble(),
                min: 1, max: 3, divisions: 2,
                activeColor: kSamuraiRed,
                label: '${_config.waves}',
                onChanged: (v) => setState(() {
                  _config = _config.copyWith(waves: v.round());
                }),
              ),
            ),
            Text('${_config.waves}',
                style: const TextStyle(
                    color: kSamuraiRed,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none)),
          ]),

          // تفعيل الأدوات
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('استخدام أدوات الساموراي (166)',
                style: TextStyle(
                    fontSize: 12, decoration: TextDecoration.none)),
            subtitle: Text(
                'كل wave: ${_config.toolsPerWave} أداة',
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white54,
                    decoration: TextDecoration.none)),
            value: _config.useTools,
            activeColor: kSamuraiGold,
            onChanged: (v) => setState(() {
              _config = _config.copyWith(
                  toolId: v ? 166 : null);
            }),
          ),

          if (_config.useTools) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: _toolField('L', _config.toolL, (v) {
                setState(() => _config = _config.copyWith(toolL: v));
              })),
              const SizedBox(width: 6),
              Expanded(child: _toolField('M', _config.toolM, (v) {
                setState(() => _config = _config.copyWith(toolM: v));
              })),
              const SizedBox(width: 6),
              Expanded(child: _toolField('R', _config.toolR, (v) {
                setState(() => _config = _config.copyWith(toolR: v));
              })),
            ]),
            const SizedBox(height: 6),
            const Text(
                'الحد الأقصى بيتظبط تلقائيًا حسب Level المعسكر',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.white38,
                    decoration: TextDecoration.none)),
          ],
        ],
      ),
    );
  }

  Widget _toolField(String label, int val, ValueChanged<int> onCh) {
    return TextFormField(
      key: ValueKey('tool_${label}_$val'),
      initialValue: val.toString(),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: const TextStyle(
          color: kSamuraiGold,
          fontWeight: FontWeight.bold,
          fontSize: 13),
      decoration: InputDecoration(
        labelText: 'T-$label',
        labelStyle:
            const TextStyle(color: Colors.white54, fontSize: 10),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: kSamuraiGold),
        ),
      ),
      onChanged: (s) {
        final v = int.tryParse(s) ?? 0;
        onCh(v.clamp(0, 999));
      },
    );
  }

  // ─── Preview ────────────────────────────────────
  Widget _previewCard() {
    final lvl = _effectiveLevel;
    if (lvl <= 0) {
      return const SizedBox.shrink();
    }
    final maxFlank = SamuraiMath.flankMax(lvl);
    final maxMiddle = SamuraiMath.middleMax(lvl);
    final maxWave = maxFlank * 2 + maxMiddle;
    final maxFlankTools = SamuraiMath.toolCapFlank(lvl);
    final maxMiddleTools = SamuraiMath.toolCapMiddle(lvl);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSamuraiGold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kSamuraiGold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📊 ملخص متوقع',
              style: TextStyle(
                  color: kSamuraiGold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none)),
          const SizedBox(height: 6),
          Text('• كل wave أقصى: $maxWave وحدة ($maxFlank L + $maxMiddle M + $maxFlank R)',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  decoration: TextDecoration.none)),
          Text('• أدوات: أقصى $maxFlankTools للجناح · $maxMiddleTools للأمام',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  decoration: TextDecoration.none)),
          Text('• Waves: ${_config.waves} · إجمالي وحدة: $_totalUnits',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  decoration: TextDecoration.none)),
        ],
      ),
    );
  }

  // ─── Lord ───────────────────────────────────────
  Widget _lordSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('القائد',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none)),
        const SizedBox(height: 6),
        DropdownButtonHideUnderline(
          child: DropdownButton<Lord>(
            value: _selectedLord,
            isExpanded: true,
            dropdownColor: Theme.of(context).colorScheme.surface,
            items: _commanders
                .where((c) => !c.isBusy)
                .map((c) => DropdownMenuItem(
                      value: c.lord,
                      child: Text(
                          c.lord.id == 0
                              ? 'اللورد الرئيسي'
                              : c.lord.displayName,
                          style: const TextStyle(
                              decoration: TextDecoration.none,
                              fontSize: 13)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _selectedLord = v),
          ),
        ),
      ],
    );
  }
}