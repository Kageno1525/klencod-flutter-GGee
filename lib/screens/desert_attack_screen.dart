import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gge/gge_client.dart';
import 'package:gge/l10n/strings.dart';
import 'package:gge/models.dart';
import 'package:gge/services/desert_attack_service.dart';
import 'package:gge/services/desert_auto_service.dart';
import 'package:gge/services/background_service.dart';
import 'package:gge/theme.dart';
import 'package:gge/widgets/animated_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color kDesertSand = Color(0xFFE8A317);
const Color kDesertDark = Color(0xFF8B5A2B);
const Color kDesertGold = Color(0xFFD4AF37);

class DesertAttackScreen extends StatefulWidget {
  final GgeClient client;
  const DesertAttackScreen({super.key, required this.client});

  @override
  State<DesertAttackScreen> createState() => _DesertAttackScreenState();
}

class _DesertAttackScreenState extends State<DesertAttackScreen>
    with TickerProviderStateMixin {
  late final DesertAttackService _svc;
  late DesertAttackSettings _settings;
  StreamSubscription? _xtSub;

  late TabController _tabCtrl;

  List<OwnedCastle> _castles = [];
  OwnedCastle? _source;
  List<DesertTower> _towers = [];
  bool _scanning = false;
  int _scanDone = 0, _scanTotal = 0;
  bool _loading = true;

  // Auto tab state
  List<CommanderInfo> _allCommanders = [];
  List<CastleUnit> _mainUnits = [];
  Set<int> _selectedCommanderIds = {};
  Set<int> _selectedTransferIds = {};
  bool _loadingAutoData = false;

  // ✅ الأرقام التلاتة اللي هتتحكم فيها (204)
  int _capStart = DesertAutoService.kDefaultCapStart;
  int _capMin = DesertAutoService.kDefaultCapMin;
  int _capMax = DesertAutoService.kDefaultCapMax;

  // Background attack limits
  int _maxAttacksDay = 0;
  int _maxAttacksSession = 0;
  int _breakEvery = 0;
  int _breakMinutes = 15;
  int _attacksToday = 0;
  int _attacksThisSession = 0;

  // Background service status
  String _bgStatus = '—';
  String _bgExtra = '';

  Timer? _bgStatusTimer;

  @override
  void initState() {
    super.initState();
    _svc = DesertAttackService(widget.client);
    _svc.loadCooldowns();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _init();
    _xtSub = widget.client.xtStream.listen(_onXt);
    _startBgStatusPolling();
  }

  void _startBgStatusPolling() {
    _bgStatusTimer?.cancel();
    _bgStatusTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!mounted) return;
      try {
        final status = await BackgroundService.readStatus();
        if (!mounted) return;
        final newStatus = status['status']?.toString() ?? '—';
        final newExtra = status['extra']?.toString() ?? '';
        if (newStatus != _bgStatus || newExtra != _bgExtra) {
          setState(() {
            _bgStatus = newStatus;
            _bgExtra = newExtra;
          });
        }
      } catch (_) {}
    });
  }

  void _onXt(XtMessage msg) {
    if (msg.command != 'sne' || msg.payload == null) return;
    try {
      final data = jsonDecode(msg.payload!) as Map<String, dynamic>;
      final msgs = data['MSG'] as List?;
      if (msgs == null) return;
      for (final m in msgs) {
        if (m is! List || m.length < 2) continue;
        final msgId = m[0] as int?;
        final type = m[1] as int?;
        if (msgId == null || type != 4) continue;
        _svc.captureSneReport(msgId);
      }
    } catch (_) {}
  }

  Future<void> _init() async {
    _settings = await DesertAttackSettings.load();

    // Load background limits + caps
    final p = await SharedPreferences.getInstance();
    _maxAttacksDay = p.getInt('desert_bg_max_attacks_day') ?? 0;
    _maxAttacksSession = p.getInt('desert_bg_max_attacks_session') ?? 0;
    _breakEvery = p.getInt('desert_bg_break_every') ?? 0;
    _breakMinutes = p.getInt('desert_bg_break_minutes') ?? 15;
    _attacksToday = p.getInt('desert_bg_attacks_today') ?? 0;
    _attacksThisSession = 0;

    // ✅ تحميل الأرقام التلاتة
    _capStart = p.getInt(DesertAutoService.kCapStartKey) ?? DesertAutoService.kDefaultCapStart;
    _capMin = p.getInt(DesertAutoService.kCapMinKey) ?? DesertAutoService.kDefaultCapMin;
    _capMax = p.getInt(DesertAutoService.kCapMaxKey) ?? DesertAutoService.kDefaultCapMax;

    try {
      final castles = await widget.client.getCastles();
      final preferred = castles
          .where((c) => c.kingdomId == 1 || c.areaType == 12)
          .toList();
      if (!mounted) return;
      setState(() {
        _castles = preferred.isNotEmpty ? preferred : castles;
        if (_castles.isNotEmpty) {
          try {
            _source =
                _castles.firstWhere((c) => c.areaId == _settings.sourceAreaId);
          } catch (_) {
            try {
              _source = _castles.firstWhere((c) => c.kingdomId == 1);
            } catch (_) {
              _source = _castles.first;
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

  @override
  void dispose() {
    _xtSub?.cancel();
    _bgStatusTimer?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════
  //  Manual scan
  // ═══════════════════════════════════════════════════════
  Future<void> _scan() async {
    if (_source == null) {
      _snack('اختر قلعة مصدر أولاً', color: AppTheme.red);
      return;
    }
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _towers = [];
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
        _towers = found;
        _scanning = false;
      });
      if (found.isEmpty) {
        _snack('مفيش أبراج صحراء في النطاق ده', color: AppTheme.orange);
      } else {
        _snack('تم العثور على ${found.length} برج', color: AppTheme.green);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _snack('$e', color: AppTheme.red);
    }
  }

  List<DesertTower> get _filteredTowers {
    final list = _towers.toList()
      ..sort((a, b) => a.distanceFromSource.compareTo(b.distanceFromSource));
    return list;
  }

  // ═══════════════════════════════════════════════════════
  //  Auto: load commanders + main units
  // ═══════════════════════════════════════════════════════
  Future<void> _loadAutoData() async {
    if (_loadingAutoData) return;
    setState(() => _loadingAutoData = true);
    try {
      final cmds = await widget.client.getCommanders();
      OwnedCastle? main;
      for (final c in _castles) {
        if (c.areaType == 1) {
          main = c;
          break;
        }
      }
      main ??= _castles.isNotEmpty ? _castles.first : null;

      List<CastleUnit> mainUnits = [];
      if (main != null) {
        final catalog = await widget.client.loadCatalog();
        try {
          final catMap = <String, Map<String, dynamic>>{};
          for (final e in catalog.entries) {
            catMap[e.key.toString()] = {'displayName': e.value.displayName};
          }
          final p = await SharedPreferences.getInstance();
          await p.setString('desert_bg_catalog_json', jsonEncode(catMap));
        } catch (_) {}

        mainUnits = await widget.client.getCastleUnits(
            main.kingdomId, main.areaId, catalog);
      }

      final savedCmds = await DesertAutoService.instance.getCommanderIds();
      final savedUnits = await DesertAutoService.instance.getTransferUnitIds();

      if (!mounted) return;
      setState(() {
        _allCommanders = cmds;
        _mainUnits = mainUnits
            .where((u) => u.isCombat && !u.isDefensive && u.amount > 0)
            .toList();
        _selectedCommanderIds = savedCmds.toSet();
        _selectedTransferIds = savedUnits.toSet();
        _loadingAutoData = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAutoData = false);
        _snack('Load error: $e', color: AppTheme.red);
      }
    }
  }

  Future<void> _openCommandersPicker() async {
    if (_allCommanders.isEmpty) await _loadAutoData();
    if (!mounted) return;

    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MultiSelectSheet(
        title: 'اختر القواد',
        items: _allCommanders
            .map((c) => _SelectItem(
                  id: c.lord.id,
                  label: c.lord.id == 0
                      ? 'اللورد الرئيسي'
                      : c.lord.displayName,
                  subtitle: c.isBusy ? 'مشغول' : 'متاح',
                ))
            .toList(),
        selected: _selectedCommanderIds,
        allowEmpty: true,
        emptyMeansAll: true,
      ),
    );
    if (result == null) return;
    await DesertAutoService.instance.setCommanderIds(result.toList());
    if (mounted) setState(() => _selectedCommanderIds = result);
  }

  Future<void> _openTransferUnitsPicker() async {
    if (_mainUnits.isEmpty) await _loadAutoData();
    if (!mounted) return;

    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MultiSelectSheet(
        title: 'وحدات النقل من القلعة الرئيسية',
        items: _mainUnits
            .map((u) => _SelectItem(
                  id: u.wodId,
                  label: u.displayName,
                  subtitle: 'متاح: ${u.amount}',
                ))
            .toList(),
        selected: _selectedTransferIds,
        allowEmpty: true,
        emptyMeansAll: true,
      ),
    );
    if (result == null) return;
    await DesertAutoService.instance.setTransferUnitIds(result.toList());
    if (mounted) setState(() => _selectedTransferIds = result);
  }

  // ═══════════════════════════════════════════════════════
  //  Tower sheet
  // ═══════════════════════════════════════════════════════
  Future<void> _openTowerSheet(DesertTower tower) async {
    if (_source == null) {
      _snack('اختر قلعة مصدر', color: AppTheme.red);
      return;
    }
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DesertAttackSheet(
        client: widget.client,
        source: _source!,
        tower: tower,
        svc: _svc,
        onSpySent: (mid) {
          if (!mounted) return;
          setState(() {
            final idx = _towers.indexWhere(
                (x) => x.x == tower.x && x.y == tower.y);
            if (idx >= 0) {
              _towers[idx] = _towers[idx].copyWith(
                lastSpyAt: DateTime.now(),
                lastSpyMid: mid,
              );
            }
          });
        },
      ),
    );
    if (result == true && mounted) {
      setState(() {});
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
                _header(context),
                _tabBar(context),
                if (_loading)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: kDesertSand),
                    ),
                  )
                else
                  Expanded(
                    child: _tabCtrl.index == 0 ? _manualTab() : _autoTab(),
                  ),
              ],
            ),
          ),
          if (_tabCtrl.index == 0 && _source != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: GradientButton(
                label: _scanning
                    ? 'جارٍ المسح ($_scanDone/$_scanTotal)'
                    : 'مسح الصحراء (${_settings.radiusTiles} tile)',
                icon: Icons.landscape_rounded,
                gradient:
                    const LinearGradient(colors: [kDesertSand, kDesertDark]),
                loading: _scanning,
                onPressed: _scanning ? null : _scan,
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  Header + tabs
  // ═══════════════════════════════════════════════════════
  Widget _header(BuildContext context) {
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
                Text('برج الصحراء',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textColor(context),
                        letterSpacing: -0.3,
                        decoration: TextDecoration.none)),
                Text('${_towers.length} برج',
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

  Widget _tabBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          _tabBtn(context, 'يدوي', 0, Icons.touch_app_rounded),
          _tabBtn(context, 'تلقائي', 1, Icons.auto_awesome_rounded),
        ]),
      ),
    );
  }

  Widget _tabBtn(BuildContext context, String label, int index, IconData icon) {
    final sel = _tabCtrl.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabCtrl.animateTo(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: sel
                ? const LinearGradient(colors: [kDesertSand, kDesertDark])
                : null,
            color: sel ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: sel ? Colors.white : AppTheme.subTextColor(context)),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color:
                          sel ? Colors.white : AppTheme.subTextColor(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      decoration: TextDecoration.none)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  Manual Tab
  // ═══════════════════════════════════════════════════════
  Widget _manualTab() {
    final filtered = _filteredTowers;
    return Column(
      children: [
        _sourcePicker(context),
        _filterBar(context),
        if (_scanning) _progressBar(context),
        Expanded(
          child: filtered.isEmpty
              ? _emptyView(context)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => FadeSlideIn(
                    delay: Duration(milliseconds: 30 + i * 30),
                    child: _towerCard(context, filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  Auto Tab
  // ═══════════════════════════════════════════════════════
  Widget _autoTab() {
    final svc = DesertAutoService.instance;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _sourcePicker(context),
        const SizedBox(height: 10),
        _bigStatusCard(context, svc),
        const SizedBox(height: 10),
        _bgServiceCard(context, svc),
        const SizedBox(height: 10),
        _autoControlsCard(context, svc),
        const SizedBox(height: 10),
        _autoSettingsCard(context),
        const SizedBox(height: 10),
        _autoFilterCard(context, svc),
      ],
    );
  }

  Widget _bigStatusCard(BuildContext context, DesertAutoService svc) {
    return ValueListenableBuilder<String>(
      valueListenable: svc.statusNotifier,
      builder: (_, status, __) {
        final running = svc.isRunning;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: running
                  ? [const Color(0xFF16A34A), const Color(0xFF15803D)]
                  : [const Color(0xFF37474F), const Color(0xFF546E7A)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (running ? Colors.green : Colors.grey)
                    .withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                      running ? Icons.bolt_rounded : Icons.pause_rounded,
                      color: Colors.white,
                      size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Auto Attack (Foreground)',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.none)),
                      Text(
                          running
                              ? 'يعمل · ${svc.attacksThisSession} هجمة'
                              : 'متوقف',
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              decoration: TextDecoration.none)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(running ? 'ON' : 'OFF',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none)),
                ),
              ]),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('آخر status',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none)),
                    const SizedBox(height: 4),
                    Text(status,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _miniStat('أبراج', svc.towersScanned.toString())),
                Expanded(
                    child: _miniStat(
                        'هجمات', svc.attacksThisSession.toString())),
                Expanded(
                    child: _miniStat('سجل', svc.statusHistory.length.toString())),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(children: [
      Text(value,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              decoration: TextDecoration.none)),
      Text(label,
          style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              decoration: TextDecoration.none)),
    ]);
  }

  Widget _bgServiceCard(BuildContext context, DesertAutoService svc) {
    final running = BackgroundService.isRunning;
    final statusColor = _bgStatusColor(_bgStatus);

    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kDesertGold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.nightlight_round,
                  color: kDesertGold, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الخلفية (Background)',
                      style: TextStyle(
                          color: AppTheme.textColor(context),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          decoration: TextDecoration.none)),
                  Text(running ? 'يعمل في الخلفية' : 'متوقف',
                      style: TextStyle(
                          color: running ? Colors.green : AppTheme.subTextColor(context),
                          fontSize: 11,
                          decoration: TextDecoration.none)),
                ],
              ),
            ),
            Switch(
              value: running,
              activeColor: kDesertGold,
              onChanged: (v) async {
                if (v) {
                  final ok = await BackgroundService.start();
                  if (mounted) {
                    _snack(ok ? '✅ الخلفية شغالة' : '❌ فشل التشغيل',
                        color: ok ? AppTheme.green : AppTheme.red);
                    setState(() {});
                  }
                } else {
                  await BackgroundService.stop();
                  if (mounted) setState(() {});
                }
              },
            ),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.circle, color: statusColor, size: 8),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_bgStatus,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none)),
                  ),
                ]),
                if (_bgExtra.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Text(_bgExtra,
                        style: TextStyle(
                            color: AppTheme.subTextColor(context),
                            fontSize: 10,
                            decoration: TextDecoration.none)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _counterChip(
                context,
                label: 'اليومي',
                value: '$_attacksToday${_maxAttacksDay > 0 ? "/$_maxAttacksDay" : ""}',
                color: kDesertSand,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _counterChip(
                context,
                label: 'الجلسة',
                value: '$_attacksThisSession${_maxAttacksSession > 0 ? "/$_maxAttacksSession" : ""}',
                color: kDesertGold,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Color _bgStatusColor(String s) {
    if (s.contains('LIMIT') || s.contains('REACHED')) return Colors.red;
    if (s.contains('BREAK')) return Colors.orange;
    if (s.contains('ATTACK')) return Colors.green;
    if (s.contains('ONLINE')) return Colors.green;
    if (s.contains('LOGIN_FAILED') || s.contains('DESTROYED')) return Colors.red;
    if (s.contains('SCAN')) return kDesertGold;
    if (s.contains('SPY')) return Colors.orange;
    return Colors.grey;
  }

  Widget _counterChip(BuildContext context,
      {required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: AppTheme.subTextColor(context),
                  fontSize: 9,
                  decoration: TextDecoration.none)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none)),
        ],
      ),
    );
  }

  Widget _autoControlsCard(BuildContext context, DesertAutoService svc) {
    return ValueListenableBuilder<String>(
      valueListenable: svc.statusNotifier,
      builder: (_, __, ___) {
        final running = svc.isRunning;
        return AppTheme.glassCard(
          context: context,
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () async {
                  if (_source == null) {
                    _snack('اختر قلعة مصدر أولاً', color: AppTheme.red);
                    return;
                  }
                  if (running) {
                    svc.stop();
                    await svc.setEnabled(false);
                  } else {
                    await svc.setEnabled(true);
                    await svc.start(widget.client,
                        sourceAreaId: _source!.areaId);
                  }
                  if (mounted) setState(() {});
                },
                icon: Icon(
                    running ? Icons.stop_rounded : Icons.play_arrow_rounded),
                label: Text(running ? 'إيقاف Auto' : 'تشغيل Auto',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        decoration: TextDecoration.none)),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      running ? AppTheme.red : const Color(0xFF16A34A),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () => _showStatusHistory(context, svc),
                icon: const Icon(Icons.history_rounded, size: 16),
                label: Text(
                    'عرض كل الـ status (${svc.statusHistory.length})',
                    style: const TextStyle(
                        fontSize: 12, decoration: TextDecoration.none)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kDesertSand,
                  side: const BorderSide(color: kDesertSand),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }

  void _showStatusHistory(BuildContext context, DesertAutoService svc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFF0B0B14),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(children: [
            Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(3))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Icon(Icons.history_rounded, color: kDesertSand, size: 20),
                SizedBox(width: 8),
                Text('Status History',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none)),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.08))),
                child: svc.statusHistory.isEmpty
                    ? const Center(
                        child: Text('لا يوجد سجل بعد',
                            style: TextStyle(
                                color: Colors.grey,
                                fontFamily: 'monospace',
                                fontSize: 11,
                                decoration: TextDecoration.none)))
                    : ListView.builder(
                        itemCount: svc.statusHistory.length,
                        itemBuilder: (_, i) {
                          final e = svc.statusHistory[i];
                          final t =
                              '${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}:${e.at.second.toString().padLeft(2, '0')}';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(children: [
                              Text(t,
                                  style: const TextStyle(
                                      color: Colors.white38,
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      decoration: TextDecoration.none)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(e.message,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          decoration:
                                              TextDecoration.none))),
                            ]),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }

  // ✅ تعديل كارت الإعدادات عشان يشمل الأرقام التلاتة (204)
  Widget _autoSettingsCard(BuildContext context) {
    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.settings_rounded, color: kDesertSand, size: 18),
            const SizedBox(width: 8),
            Text('إعدادات الهجوم التلقائي',
                style: TextStyle(
                    color: AppTheme.textColor(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    decoration: TextDecoration.none)),
          ]),
          const SizedBox(height: 10),
          
          // ✅ الخانات التلاتة
          Row(children: [
            Expanded(
              child: _numberField(
                context,
                label: 'البداية',
                hint: '204',
                value: _capStart,
                onChanged: (v) async {
                  setState(() => _capStart = v);
                  final p = await SharedPreferences.getInstance();
                  await p.setInt(DesertAutoService.kCapStartKey, v);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _numberField(
                context,
                label: 'أقل عدد',
                hint: '204',
                value: _capMin,
                onChanged: (v) async {
                  setState(() => _capMin = v);
                  final p = await SharedPreferences.getInstance();
                  await p.setInt(DesertAutoService.kCapMinKey, v);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _numberField(
                context,
                label: 'أقصى عدد',
                hint: '204',
                value: _capMax,
                onChanged: (v) async {
                  setState(() => _capMax = v);
                  final p = await SharedPreferences.getInstance();
                  await p.setInt(DesertAutoService.kCapMaxKey, v);
                },
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text('البوت بيهجم فوراً بدون تجسس بالعدد اللي تحدده (مثلاً 160-165 عشان ميجيبش cpa).',
              style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.subTextColor(context),
                  decoration: TextDecoration.none)),

          const SizedBox(height: 12),
          Divider(color: AppTheme.subTextColor(context).withOpacity(0.15)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text('النطاق: ${_settings.radiusTiles} tile',
                  style: TextStyle(
                      color: AppTheme.textColor(context),
                      fontSize: 13,
                      decoration: TextDecoration.none)),
            ),
            TextButton(
              onPressed: () => _openRadiusSheet(context),
              child: const Text('تعديل', style: TextStyle(color: kDesertSand)),
            ),
          ]),
          
          const SizedBox(height: 8),
          Divider(color: AppTheme.subTextColor(context).withOpacity(0.15)),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.speed_rounded, color: kDesertGold, size: 18),
            const SizedBox(width: 8),
            Text('حدود الهجمات (خلفية)',
                style: TextStyle(
                    color: AppTheme.textColor(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    decoration: TextDecoration.none)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _numberField(
                context,
                label: 'حد يومي',
                hint: '0 = ∞',
                value: _maxAttacksDay,
                onChanged: (v) async {
                  setState(() => _maxAttacksDay = v);
                  final p = await SharedPreferences.getInstance();
                  await p.setInt('desert_bg_max_attacks_day', v);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _numberField(
                context,
                label: 'حد جلسة',
                hint: '0 = ∞',
                value: _maxAttacksSession,
                onChanged: (v) async {
                  setState(() => _maxAttacksSession = v);
                  final p = await SharedPreferences.getInstance();
                  await p.setInt('desert_bg_max_attacks_session', v);
                },
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _resetCounters() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('desert_bg_attacks_today', 0);
    final d = DateTime.now();
    final today = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await p.setString('desert_bg_attacks_date', today);
    if (mounted) {
      setState(() {
        _attacksToday = 0;
        _attacksThisSession = 0;
      });
      _snack('تم تصفير العدادات', color: AppTheme.green);
    }
  }

  Widget _numberField(
    BuildContext context, {
    required String label,
    required String hint,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return TextField(
      controller: TextEditingController(text: value.toString())
        ..selection = TextSelection.collapsed(offset: value.toString().length),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: TextStyle(
          color: AppTheme.textColor(context),
          fontSize: 13,
          fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
            color: AppTheme.subTextColor(context), fontSize: 10),
        hintStyle: TextStyle(
            color: AppTheme.subTextColor(context).withOpacity(0.5),
            fontSize: 10),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                BorderSide(color: kDesertGold.withOpacity(0.3))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kDesertGold)),
      ),
      onChanged: (s) {
        final v = int.tryParse(s) ?? 0;
        onChanged(v.clamp(0, 9999));
      },
    );
  }

  Widget _autoFilterCard(BuildContext context, DesertAutoService svc) {
    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.tune_rounded, color: AppTheme.orange, size: 18),
            const SizedBox(width: 8),
            Text('فلاتر البوت',
                style: TextStyle(
                    color: AppTheme.textColor(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    decoration: TextDecoration.none)),
          ]),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.people_alt_rounded,
                color: kDesertGold, size: 22),
            title: const Text('القواد المسموحين',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none)),
            subtitle: Text(
                _selectedCommanderIds.isEmpty
                    ? 'الكل (بدون فلتر)'
                    : '${_selectedCommanderIds.length} قائد مختار',
                style: const TextStyle(
                    fontSize: 11, decoration: TextDecoration.none)),
            trailing: const Icon(Icons.edit_rounded,
                color: kDesertGold, size: 18),
            onTap: _openCommandersPicker,
          ),
          Divider(color: AppTheme.subTextColor(context).withOpacity(0.1)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.local_shipping_rounded,
                color: AppTheme.teal, size: 22),
            title: const Text('وحدات النقل من الرئيسية',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none)),
            subtitle: Text(
                _selectedTransferIds.isEmpty
                    ? 'الكل (كل الوحدات الهجومية)'
                    : '${_selectedTransferIds.length} نوع مختار',
                style: const TextStyle(
                    fontSize: 11, decoration: TextDecoration.none)),
            trailing: const Icon(Icons.edit_rounded,
                color: AppTheme.teal, size: 18),
            onTap: _openTransferUnitsPicker,
          ),
          const SizedBox(height: 4),
          Text(
              'الفلتر الفاضي = يسمح بالكل',
              style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.subTextColor(context),
                  decoration: TextDecoration.none)),
        ],
      ),
    );
  }

  Widget _sourcePicker(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: AppTheme.glassCard(
        context: context,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: kDesertSand.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.castle_rounded,
                  color: kDesertSand, size: 18),
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
                    DesertAutoService.instance.setSource(v.areaId);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Row(
        children: [
          _chip(context,
              icon: Icons.place_rounded,
              label: '${_settings.radiusTiles} tile',
              color: AppTheme.orange,
              onTap: () => _openRadiusSheet(context)),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none)),
        ]),
      ),
    );
  }

  Widget _progressBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: _scanning && _scanTotal > 0 ? _scanDone / _scanTotal : null,
          minHeight: 4,
          backgroundColor: kDesertSand.withOpacity(0.1),
          valueColor: const AlwaysStoppedAnimation(kDesertSand),
        ),
      ),
    );
  }

  Widget _emptyView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kDesertSand.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: kDesertSand.withOpacity(0.3)),
              ),
              child: Icon(Icons.landscape_rounded,
                  size: 48, color: kDesertSand.withOpacity(0.7)),
            ),
            const SizedBox(height: 16),
            Text('مفيش أبراج لسه',
                style: TextStyle(
                    color: AppTheme.textColor(context),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none)),
            const SizedBox(height: 4),
            Text('دوس "مسح الصحراء" عشان تبدأ',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.subTextColor(context),
                    fontSize: 11,
                    decoration: TextDecoration.none)),
          ],
        ),
      ),
    );
  }

  Widget _towerCard(BuildContext context, DesertTower t) {
    final spied = t.isSpied;
    final inCooldown = _svc.isTowerInCooldown(t);
    final cooldownRemaining = _svc.towerCooldownRemaining(t);
    final borderColor = inCooldown
        ? Colors.orange
        : (spied
            ? kDesertGold
            : AppTheme.subTextColor(context).withOpacity(0.2));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: inCooldown ? null : () => _openTowerSheet(t),
        child: Opacity(
          opacity: inCooldown ? 0.6 : 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.isDark(context)
                  ? Colors.white.withOpacity(0.04)
                  : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: borderColor, width: (spied || inCooldown) ? 1.6 : 1.2),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: inCooldown
                        ? Colors.orange.withOpacity(0.15)
                        : kDesertSand.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                      inCooldown
                          ? Icons.hourglass_top_rounded
                          : Icons.landscape_rounded,
                      color: inCooldown ? Colors.orange : kDesertSand,
                      size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(t.coordsLabel,
                              style: TextStyle(
                                  color: AppTheme.textColor(context),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  decoration: TextDecoration.none)),
                          const SizedBox(width: 8),
                          if (inCooldown)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.orange.withOpacity(0.6)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.timer_rounded,
                                      size: 10, color: Colors.orange),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${cooldownRemaining.inMinutes}:${(cooldownRemaining.inSeconds % 60).toString().padLeft(2, "0")}',
                                    style: const TextStyle(
                                        color: Colors.orange,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.none),
                                  ),
                                ],
                              ),
                            )
                          else if (spied)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.green.withOpacity(0.6)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.visibility_rounded,
                                      size: 10, color: Colors.green),
                                  const SizedBox(width: 3),
                                  Text('تجسس ${t.spyTimeLabel}',
                                      style: const TextStyle(
                                          color: Colors.green,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.none)),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.straighten_rounded,
                              size: 11,
                              color: AppTheme.subTextColor(context)),
                          const SizedBox(width: 3),
                          Text(
                              '${t.distanceFromSource.toStringAsFixed(0)} tile',
                              style: TextStyle(
                                  color: AppTheme.subTextColor(context),
                                  fontSize: 10.5,
                                  decoration: TextDecoration.none)),
                        ],
                      ),
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

  void _openRadiusSheet(BuildContext context) {
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
              min: kDesertRadiusMin.toDouble(),
              max: kDesertRadiusMax.toDouble(),
              divisions:
                  (kDesertRadiusMax - kDesertRadiusMin) ~/ kDesertRadiusStep,
              activeColor: kDesertSand,
              label: '${temp.toInt()}',
              onChanged: (v) => setSt(() => temp =
                  (v / kDesertRadiusStep).round() *
                      kDesertRadiusStep.toDouble()),
            ),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$kDesertRadiusMin',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.subTextColor(ctx),
                          decoration: TextDecoration.none)),
                  Text('$kDesertRadiusMax',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.subTextColor(ctx),
                          decoration: TextDecoration.none)),
                ]),
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

// ═══════════════════════════════════════════════════════════
//  Multi-select sheet
// ═══════════════════════════════════════════════════════════
class _SelectItem {
  final int id;
  final String label;
  final String? subtitle;
  _SelectItem({required this.id, required this.label, this.subtitle});
}

class _MultiSelectSheet extends StatefulWidget {
  final String title;
  final List<_SelectItem> items;
  final Set<int> selected;
  final bool allowEmpty;
  final bool emptyMeansAll;

  const _MultiSelectSheet({
    required this.title,
    required this.items,
    required this.selected,
    this.allowEmpty = true,
    this.emptyMeansAll = false,
  });

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late Set<int> _sel;

  @override
  void initState() {
    super.initState();
    _sel = Set.from(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Color(0xFF0B0B14),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(children: [
          Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Icon(Icons.checklist_rounded, color: kDesertSand, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none))),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_sel.length == widget.items.length) {
                      _sel.clear();
                    } else {
                      _sel = widget.items.map((e) => e.id).toSet();
                    }
                  });
                },
                child: Text(_sel.length == widget.items.length
                    ? 'إلغاء الكل'
                    : 'تحديد الكل',
                    style: const TextStyle(color: kDesertSand, fontSize: 11)),
              ),
            ]),
          ),
          if (widget.emptyMeansAll)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                  _sel.isEmpty ? '⚠️ فاضي = السماح للكل' : '${_sel.length} مختار',
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      decoration: TextDecoration.none)),
            ),
          const Divider(color: Colors.white12),
          Expanded(
            child: ListView.builder(
              itemCount: widget.items.length,
              itemBuilder: (_, i) {
                final it = widget.items[i];
                final sel = _sel.contains(it.id);
                return CheckboxListTile(
                  value: sel,
                  activeColor: kDesertSand,
                  title: Text(it.label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          decoration: TextDecoration.none)),
                  subtitle: it.subtitle != null
                      ? Text(it.subtitle!,
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              decoration: TextDecoration.none))
                      : null,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _sel.add(it.id);
                      } else {
                        _sel.remove(it.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Text('إلغاء'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _sel),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kDesertSand,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Text('حفظ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Manual attack sheet
// ═══════════════════════════════════════════════════════════
class _DesertAttackSheet extends StatefulWidget {
  final GgeClient client;
  final OwnedCastle source;
  final DesertTower tower;
  final DesertAttackService svc;
  final void Function(int? mid) onSpySent;

  const _DesertAttackSheet({
    required this.client,
    required this.source,
    required this.tower,
    required this.svc,
    required this.onSpySent,
  });

  @override
  State<_DesertAttackSheet> createState() => _DesertAttackSheetState();
}

class _DesertAttackSheetState extends State<_DesertAttackSheet> {
  static const int _maxTypes = 10;

  List<CastleUnit> _units = [];
  Map<int, UnitCatalogEntry> _catalog = {};
  List<CommanderInfo> _commanders = [];
  Lord? _selectedLord;

  Map<int, int> _leftAmt = {};
  Map<int, int> _middleAmt = {};
  Map<int, int> _rightAmt = {};

  final _lmCtrl = TextEditingController(text: '0');
  final _lrCtrl = TextEditingController(text: '0');
  final _mmCtrl = TextEditingController(text: '0');
  final _mrCtrl = TextEditingController(text: '0');
  final _rmCtrl = TextEditingController(text: '0');
  final _rrCtrl = TextEditingController(text: '0');

  DesertSpyReport? _lastReport;

  bool _loading = true;
  bool _sending = false;
  bool _spying = false;
  bool _fetching = false;
  bool _recalling = false;
  bool _autoAttackInProgress = false;

  DateTime? _lastSpyLocalAt;

  @override
  void initState() {
    super.initState();
    _lastSpyLocalAt = widget.tower.lastSpyAt;
    _setupDefenseListeners();
    _load();
  }

  void _setupDefenseListeners() {
    for (final c in [_lmCtrl, _lrCtrl, _mmCtrl, _mrCtrl, _rmCtrl, _rrCtrl]) {
      c.addListener(_saveDefenders);
    }
  }

  Future<void> _saveDefenders() async {
    await widget.svc.saveCachedDefenders(
        widget.tower, _buildDefenderSummary());
  }

  DefenderSummary _buildDefenderSummary() => DefenderSummary(
        leftMelee: int.tryParse(_lmCtrl.text) ?? 0,
        leftRanged: int.tryParse(_lrCtrl.text) ?? 0,
        middleMelee: int.tryParse(_mmCtrl.text) ?? 0,
        middleRanged: int.tryParse(_mrCtrl.text) ?? 0,
        rightMelee: int.tryParse(_rmCtrl.text) ?? 0,
        rightRanged: int.tryParse(_rrCtrl.text) ?? 0,
      );

  Future<void> _load() async {
    try {
      _catalog = await widget.client.loadCatalog();
      final units = await widget.client.getCastleUnits(
          widget.source.kingdomId, widget.source.areaId, _catalog);
      final sendable = units
          .where((u) => u.isCombat && u.amount > 0)
          .toList();
      final cmds = await widget.client.getCommanders();

      final cached = await widget.svc.loadCachedDefenders(widget.tower);
      if (cached != null) {
        _lmCtrl.text = cached.leftMelee.toString();
        _lrCtrl.text = cached.leftRanged.toString();
        _mmCtrl.text = cached.middleMelee.toString();
        _mrCtrl.text = cached.middleRanged.toString();
        _rmCtrl.text = cached.rightMelee.toString();
        _rrCtrl.text = cached.rightRanged.toString();
      }

      _lastReport = widget.svc.getCachedReport(widget.tower);

      if (!mounted) return;
      setState(() {
        _units = sendable;
        for (final u in sendable) {
          _leftAmt[u.wodId] = 0;
          _middleAmt[u.wodId] = 0;
          _rightAmt[u.wodId] = 0;
        }
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

  @override
  void dispose() {
    for (final c in [_lmCtrl, _lrCtrl, _mmCtrl, _mrCtrl, _rmCtrl, _rrCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _leftTotal => _leftAmt.values.fold(0, (s, e) => s + e);
  int get _middleTotal => _middleAmt.values.fold(0, (s, e) => s + e);
  int get _rightTotal => _rightAmt.values.fold(0, (s, e) => s + e);
  int get _grandTotal => _leftTotal + _middleTotal + _rightTotal;

  int get _selectedTypes {
    final set = <int>{};
    for (final e in _leftAmt.entries) {
      if (e.value > 0) set.add(e.key);
    }
    for (final e in _middleAmt.entries) {
      if (e.value > 0) set.add(e.key);
    }
    for (final e in _rightAmt.entries) {
      if (e.value > 0) set.add(e.key);
    }
    return set.length;
  }

  void _clearAll() {
    for (final k in _leftAmt.keys) {
      _leftAmt[k] = 0;
    }
    for (final k in _middleAmt.keys) {
      _middleAmt[k] = 0;
    }
    for (final k in _rightAmt.keys) {
      _rightAmt[k] = 0;
    }
    setState(() {});
  }

  void _applySuggestion(UnitSuggestion s) {
    _clearAll();
    for (final u in s.left) {
      if (u[0] > 0) _leftAmt[u[0]] = u[1];
    }
    for (final u in s.middle) {
      if (u[0] > 0) _middleAmt[u[0]] = u[1];
    }
    for (final u in s.right) {
      if (u[0] > 0) _rightAmt[u[0]] = u[1];
    }
    setState(() {});
  }

  void _autoSuggest() {
    final defs = _buildDefenderSummary();
    if (defs.isEmpty) {
      _snack('ادخل الدفاعات من تقرير التجسس الأول', color: AppTheme.orange);
      return;
    }
    final s = widget.svc.suggestCounter(
      available: _units,
      defenders: defs,
      maxTypes: _maxTypes,
    );
    _applySuggestion(s);
    _snack(s.reason, color: kDesertSand);
  }

  Future<void> _autoAttack() async {
    if (_selectedLord == null) {
      _snack('اختر قائد', color: AppTheme.red);
      return;
    }
    final defs = _buildDefenderSummary();
    if (defs.isEmpty) {
      _snack('ادخل الدفاعات من تقرير التجسس الأول', color: AppTheme.orange);
      return;
    }
    if (_autoAttackInProgress) return;

    if (_lastReport != null) {
      final totalAvail = _units.fold<int>(0, (s, u) => s + u.amount);
      final v = widget.svc.analyzeAttack(
        report: _lastReport!,
        myUnitCount: totalAvail,
        myUnits: _units.map((u) => [u.wodId, u.amount]).toList(),
      );
      if (!v.likelyWin) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(ctx).colorScheme.surface,
            title: const Text('تحذير',
                style: TextStyle(decoration: TextDecoration.none)),
            content: Text('${v.message}\n${v.hint}\n\nعايز تكمل؟',
                style: const TextStyle(decoration: TextDecoration.none)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('هجوم')),
            ],
          ),
        );
        if (confirm != true) return;
      }
    }

    setState(() => _autoAttackInProgress = true);
    final s = widget.svc.suggestCounter(
      available: _units,
      defenders: defs,
      maxTypes: _maxTypes,
    );
    _applySuggestion(s);
    await Future.delayed(const Duration(milliseconds: 300));
    await _attack();
    if (mounted) setState(() => _autoAttackInProgress = false);
  }

  Future<void> _fetchReport() async {
    final msgId = widget.svc.latestSpyMessageId;
    if (msgId == null) {
      _snack(
        'مفيش تقرير مستلم. اعمل تجسس أولاً واستنى ~30 ثانية',
        color: AppTheme.orange,
      );
      return;
    }
    setState(() => _fetching = true);

    final report = await widget.svc.fetchSpyReport(
      messageId: msgId,
      tower: widget.tower,
      catalog: _catalog,
    );

    if (!mounted) return;
    setState(() => _fetching = false);

    if (report == null) {
      _snack('فشل جلب التقرير — شوف اللوج', color: AppTheme.red);
      return;
    }

    if (!report.matches(widget.tower)) {
      _snack(
        'التقرير لبرج تاني (${report.targetX},${report.targetY})',
        color: AppTheme.orange,
      );
      return;
    }

    final d = report.toDefenderSummary();
    setState(() {
      _lastReport = report;
      _lmCtrl.text = d.leftMelee.toString();
      _lrCtrl.text = d.leftRanged.toString();
      _mmCtrl.text = d.middleMelee.toString();
      _mrCtrl.text = d.middleRanged.toString();
      _rmCtrl.text = d.rightMelee.toString();
      _rrCtrl.text = d.rightRanged.toString();
    });
    await _saveDefenders();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text('تم جلب التقرير',
              style: TextStyle(decoration: TextDecoration.none)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _reportRow('الجناح اليسار', d.leftMelee, d.leftRanged),
            const SizedBox(height: 6),
            _reportRow('الأمام', d.middleMelee, d.middleRanged),
            const SizedBox(height: 6),
            _reportRow('الجناح اليمين', d.rightMelee, d.rightRanged),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('تمام')),
        ],
      ),
    );
  }

  Widget _reportRow(String label, int melee, int ranged) {
    return Row(children: [
      SizedBox(
          width: 100,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  decoration: TextDecoration.none))),
      Text('$melee melee',
          style: const TextStyle(
              color: kDesertSand,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none)),
      const Text('  ·  ',
          style:
              TextStyle(color: Colors.white38, decoration: TextDecoration.none)),
      Text('$ranged ranged',
          style: const TextStyle(
              color: kDesertGold,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none)),
    ]);
  }

  bool get _canSpy {
    if (_spying) return false;
    if (_lastSpyLocalAt == null) return true;
    return DateTime.now().difference(_lastSpyLocalAt!).inSeconds >= 30;
  }

  Future<void> _spy() async {
    if (!_canSpy) {
      final remaining =
          30 - DateTime.now().difference(_lastSpyLocalAt!).inSeconds;
      _snack('انتظر $remaining ثانية قبل تجسس جديد',
          color: AppTheme.orange);
      return;
    }
    setState(() => _spying = true);
    final res = await widget.svc.spy(
      tower: widget.tower,
      source: widget.source,
      scoutCount: 11,
    );
    if (!mounted) return;
    setState(() {
      _spying = false;
      if (res.success) _lastSpyLocalAt = DateTime.now();
    });

    if (res.success) {
      widget.onSpySent(res.movementId);
      if (!mounted) return;
      _snack(
        'تم إرسال الجواسيس (MID=${res.movementId ?? "?"})',
        color: AppTheme.green,
      );
    } else {
      _snack(res.error ?? 'فشل التجسس', color: AppTheme.red);
    }
  }

  Future<void> _attack() async {
    if (_selectedLord == null) {
      _snack('اختر قائد', color: AppTheme.red);
      return;
    }
    if (_grandTotal == 0) {
      _snack('اختر وحدات', color: AppTheme.orange);
      return;
    }
    if (_selectedTypes > _maxTypes) {
      _snack('الحد الأقصى $_maxTypes أنواع', color: AppTheme.red);
      return;
    }

    final leftUnits = <List<int>>[];
    final middleUnits = <List<int>>[];
    final rightUnits = <List<int>>[];
    for (final u in _units) {
      final l = _leftAmt[u.wodId] ?? 0;
      final m = _middleAmt[u.wodId] ?? 0;
      final r = _rightAmt[u.wodId] ?? 0;
      final total = l + m + r;
      if (total <= 0) continue;
      final available = u.amount;
      final sum = total > available ? available : total;
      if (l > 0) leftUnits.add([u.wodId, (l * sum ~/ total).clamp(0, l)]);
      if (m > 0) middleUnits.add([u.wodId, (m * sum ~/ total).clamp(0, m)]);
      if (r > 0) rightUnits.add([u.wodId, (r * sum ~/ total).clamp(0, r)]);
    }

    setState(() => _sending = true);
    final res = await widget.svc.attack(
      tower: widget.tower,
      source: widget.source,
      lordId: _selectedLord!.id,
      leftUnits: leftUnits,
      middleUnits: middleUnits,
      rightUnits: rightUnits,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.success) {
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
        duration: const Duration(seconds: 3),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tower;
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
                    gradient:
                        const LinearGradient(colors: [kDesertSand, kDesertDark]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.landscape_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('برج صحراء ${t.coordsLabel}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none)),
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
                      child: CircularProgressIndicator(color: kDesertSand))
                  : ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      children: [
                        _actionRow(t),
                        const SizedBox(height: 16),
                        _defendersSection(),
                        const SizedBox(height: 8),
                        _powerAnalysisCard(),
                        const SizedBox(height: 8),
                        _lordSection(),
                        const SizedBox(height: 16),
                        _unitsSection(),
                        const SizedBox(height: 16),
                        _summarySection(),
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
                        _sending ? 'جارٍ الإرسال...' : 'هجوم ($_grandTotal)',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            decoration: TextDecoration.none)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kDesertSand,
                      foregroundColor: Colors.black,
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

  Widget _actionRow(DesertTower t) {
    final spyLabel = _spying
        ? 'جارٍ الإرسال...'
        : (_canSpy ? 'تجسس على ${t.coordsLabel}' : 'انتظر قبل تجسس');
    final hasMsg = widget.svc.latestSpyMessageId != null;

    return Column(children: [
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _canSpy ? _spy : null,
          icon: _spying
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: kDesertSand))
              : const Icon(Icons.visibility_rounded, size: 18),
          label: Text(spyLabel,
              style: const TextStyle(
                  decoration: TextDecoration.none, fontSize: 13)),
          style: OutlinedButton.styleFrom(
            foregroundColor: kDesertSand,
            side: const BorderSide(color: kDesertSand),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      if (hasMsg) ...[
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _fetching ? null : _fetchReport,
            icon: _fetching
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kDesertGold))
                : const Icon(Icons.download_rounded, size: 18),
            label: Text(
                _fetching
                    ? 'جارٍ الجلب...'
                    : '📥 جلب التقرير وملء الدفاعات',
                style: const TextStyle(
                    decoration: TextDecoration.none, fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: kDesertGold,
              side: const BorderSide(color: kDesertGold),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
      if (t.hasActiveAttack) ...[
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _recalling ? null : _recall,
            icon: _recalling
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.red))
                : const Icon(Icons.replay_rounded, size: 18),
            label: Text(_recalling ? '...' : 'انسحاب',
                style: const TextStyle(
                    decoration: TextDecoration.none, fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.red,
              side: const BorderSide(color: AppTheme.red),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    ]);
  }

  Future<void> _recall() async {
    final mid = widget.tower.lastAttackMid;
    if (mid == null || mid <= 0) {
      _snack('مفيش هجوم نشط للانسحاب', color: AppTheme.orange);
      return;
    }
    setState(() => _recalling = true);
    final ok = await widget.svc.recall(mid);
    if (!mounted) return;
    setState(() => _recalling = false);
    if (ok) {
      _snack('تم الانسحاب ✓', color: AppTheme.green);
      Navigator.pop(context, true);
    } else {
      _snack('فشل الانسحاب', color: AppTheme.red);
    }
  }

  Widget _defendersSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kDesertSand.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.security_rounded,
                color: kDesertSand, size: 18),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('دفاعات العدو',
                  style: TextStyle(
                      color: kDesertSand,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none)),
            ),
            if (_lastReport != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('من التقرير ✓',
                    style: TextStyle(
                        color: Colors.green,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none)),
              ),
          ]),
          const SizedBox(height: 8),
          _defenderRow('يسار', _lmCtrl, _lrCtrl),
          const SizedBox(height: 6),
          _defenderRow('أمام', _mmCtrl, _mrCtrl),
          const SizedBox(height: 6),
          _defenderRow('يمين', _rmCtrl, _rrCtrl),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _autoSuggest,
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('توزيع ذكي',
                    style: TextStyle(
                        decoration: TextDecoration.none, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kDesertSand,
                  side: const BorderSide(color: kDesertSand),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _autoAttackInProgress ? null : _autoAttack,
                icon: _autoAttackInProgress
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.flash_on_rounded, size: 16),
                label: Text(
                    _autoAttackInProgress ? '...' : 'هجوم تلقائي',
                    style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                        fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDesertGold,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _powerAnalysisCard() {
    if (_lastReport == null) return const SizedBox.shrink();
    final totalSelected = _grandTotal;
    if (totalSelected == 0) return const SizedBox.shrink();

    final unitsSelected = _units
        .where((u) =>
            (_leftAmt[u.wodId] ?? 0) +
                (_middleAmt[u.wodId] ?? 0) +
                (_rightAmt[u.wodId] ?? 0) >
            0)
        .map((u) => [
              u.wodId,
              (_leftAmt[u.wodId] ?? 0) +
                  (_middleAmt[u.wodId] ?? 0) +
                  (_rightAmt[u.wodId] ?? 0),
            ])
        .toList();

    final v = widget.svc.analyzeAttack(
      report: _lastReport!,
      myUnitCount: totalSelected,
      myUnits: unitsSelected,
    );

    final color = v.guaranteed
        ? Colors.green
        : v.likelyWin
            ? Colors.orange
            : Colors.red;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
                v.guaranteed
                    ? Icons.check_circle
                    : v.likelyWin
                        ? Icons.warning
                        : Icons.cancel,
                color: color,
                size: 18),
            const SizedBox(width: 6),
            Text(v.message,
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none)),
          ]),
          const SizedBox(height: 6),
          Text(v.hint,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  decoration: TextDecoration.none)),
        ],
      ),
    );
  }

  Widget _defenderRow(String label, TextEditingController meleeCtrl,
      TextEditingController rangedCtrl) {
    return Row(children: [
      SizedBox(
          width: 60,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  decoration: TextDecoration.none))),
      Expanded(
        child: TextField(
          controller: meleeCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: 'melee',
            labelStyle:
                const TextStyle(color: Colors.white54, fontSize: 10),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: kDesertSand)),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: TextField(
          controller: rangedCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: 'ranged',
            labelStyle:
                const TextStyle(color: Colors.white54, fontSize: 10),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: kDesertGold)),
          ),
        ),
      ),
    ]);
  }

  Widget _lordSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('القائد'),
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

  Widget _unitsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _sectionLabel(
              'الوحدات ($_selectedTypes/$_maxTypes · $_grandTotal)'),
          const Spacer(),
          TextButton(
              onPressed: _clearAll,
              child: const Text('مسح',
                  style:
                      TextStyle(fontSize: 11, color: AppTheme.red))),
        ]),
        const SizedBox(height: 4),
        ..._units.map((u) => _unitRow(u)),
      ],
    );
  }

  Widget _unitRow(CastleUnit u) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: u.roleColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(u.icon, color: u.roleColor, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(u.displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none)),
            ),
            Text('متاح: ${u.amount}',
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    decoration: TextDecoration.none)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            _wingField('L', _leftAmt[u.wodId] ?? 0, u.amount, (v) {
              setState(() => _leftAmt[u.wodId] = v);
            }, kDesertSand),
            const SizedBox(width: 6),
            _wingField('M', _middleAmt[u.wodId] ?? 0, u.amount, (v) {
              setState(() => _middleAmt[u.wodId] = v);
            }, kDesertGold),
            const SizedBox(width: 6),
            _wingField('R', _rightAmt[u.wodId] ?? 0, u.amount, (v) {
              setState(() => _rightAmt[u.wodId] = v);
            }, kDesertSand),
          ]),
        ],
      ),
    );
  }

  Widget _wingField(String label, int value, int max,
      ValueChanged<int> onChange, Color color) {
    return Expanded(
      child: SizedBox(
        height: 34,
        child: TextFormField(
          key: ValueKey('${label}_${value}_${color.value}'),
          initialValue: value.toString(),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: TextStyle(
              color: value > 0 ? color : Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: label,
            hintStyle:
                const TextStyle(color: Colors.white30, fontSize: 10),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    BorderSide(color: value > 0 ? color : Colors.white12)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: color)),
          ),
          onChanged: (v) {
            final n = int.tryParse(v) ?? 0;
            onChange(n.clamp(0, max));
          },
        ),
      ),
    );
  }

  Widget _summarySection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        _summaryItem('يسار', _leftTotal, kDesertSand),
        _summaryItem('أمام', _middleTotal, kDesertGold),
        _summaryItem('يمين', _rightTotal, kDesertSand),
        _summaryItem('إجمالي', _grandTotal, Colors.white),
      ]),
    );
  }

  Widget _summaryItem(String label, int value, Color color) {
    return Expanded(
      child: Column(children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                decoration: TextDecoration.none)),
        const SizedBox(height: 2),
        Text(value.toString(),
            style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none)),
      ]),
    );
  }

  Widget _sectionLabel(String s) => Text(s,
      style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.none));
}