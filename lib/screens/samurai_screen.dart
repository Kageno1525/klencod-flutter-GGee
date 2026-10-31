import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:gge/gge_client.dart';
import 'package:gge/models.dart';
import 'package:gge/services/samurai_service.dart';
import 'package:gge/services/samurai_auto_service.dart';
import 'package:gge/theme.dart';
import 'package:gge/widgets/animated_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color kSamuraiRed = Color(0xFFDC2626);
const Color kSamuraiDark = Color(0xFF7F1D1D);
const Color kSamuraiGold = Color(0xFFD4AF37);

// ⚠️ المفاتيح دي لازم تطابق اللي في background_service.dart
const String kBgMaxLevelKey = 'samurai_max_level_v1';
const String kBgSkipDaimyoKey = 'samurai_skip_daimyo_v1';
const String kBgRadiusKey = 'samurai_radius_v1';

class SamuraiScreen extends StatefulWidget {
  final GgeClient client;
  const SamuraiScreen({super.key, required this.client});

  @override
  State<SamuraiScreen> createState() => _SamuraiScreenState();
}

class _SamuraiScreenState extends State<SamuraiScreen>
    with TickerProviderStateMixin {
  late final SamuraiService _svc;
  late final SamuraiAutoService _auto;
  late SamuraiSettings _settings;
  late TabController _tabCtrl;

  List<OwnedCastle> _castles = [];
  OwnedCastle? _source;
  List<SamuraiCamp> _camps = [];
  bool _scanning = false;
  int _scanDone = 0, _scanTotal = 0;
  bool _loading = true;

  // Auto data
  List<CommanderInfo> _allCommanders = [];
  Set<int> _selectedCommanderIds = {};
  bool _loadingAutoData = false;

  // Auto settings
  bool _autoEnabled = false;
  int _minUnits = 30;
  int _delayMin = 10;
  int _delayMax = 15;
  int _maxLevel = 60;
  bool _skipDaimyo = true;
  int _maxAttacksDay = 0;
  int _waves = 3;
  int _toolId = 166;
  int _toolL = 20;
  int _toolR = 20;
  int _toolM = 30;

  // ✅ حالة الـ Background Service
  bool _bgRunning = false;
  String _bgStatusText = '';
  String _bgStatusExtra = '';

  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _svc = SamuraiService(widget.client);
    _auto = SamuraiAutoService.instance;
    _svc.loadCooldowns();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _init();
    _startStatusPolling();
  }

  Future<void> _init() async {
    _settings = await SamuraiSettings.load();
    await _loadAutoSettings();

    try {
      final castles = await widget.client.getCastles();
      if (!mounted) return;
      setState(() {
        _castles = castles;
        if (castles.isNotEmpty) {
          try {
            _source = castles.firstWhere(
                (c) => c.areaId == _settings.sourceAreaId);
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

  // ✅ تحميل الإعدادات من المفاتيح الصح (اللي الـ background بيقرا منها)
  Future<void> _loadAutoSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = await _auto.isEnabled();
    final minUnits = await _auto.getMinUnits();
    final delayMin = await _auto.getDelayMin();
    final delayMax = await _auto.getDelayMax();

    // ⚠️ المفاتيح اللي الـ background بيستخدمها
    final maxLevel = prefs.getInt(kBgMaxLevelKey) ?? 60;
    final skipDaimyo = prefs.getBool(kBgSkipDaimyoKey) ?? true;

    final maxAttacksDay = await _auto.getMaxAttacksDay();
    final waves = await _auto.getWaves();
    final toolId = await _auto.getToolId();
    final toolL = await _auto.getToolL();
    final toolR = await _auto.getToolR();
    final toolM = await _auto.getToolM();
    final commanders = await _auto.getCommanderIds();

    if (!mounted) return;
    setState(() {
      _autoEnabled = enabled;
      _minUnits = minUnits;
      _delayMin = delayMin;
      _delayMax = delayMax;
      _maxLevel = maxLevel;
      _skipDaimyo = skipDaimyo;
      _maxAttacksDay = maxAttacksDay;
      _waves = waves;
      _toolId = toolId;
      _toolL = toolL;
      _toolR = toolR;
      _toolM = toolM;
      _selectedCommanderIds = commanders.toSet();
    });
  }

  // ✅ حفظ Max Level في المفاتيح الصح (bg + auto)
  Future<void> _saveMaxLevel(int v) async {
    setState(() => _maxLevel = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kBgMaxLevelKey, v);       // ← background
    await prefs.setInt('samurai_auto_max_level', v); // ← auto service
    await _settings.save();
  }

  // ✅ حفظ Skip Daimyo في المفاتيح الصح
  Future<void> _saveSkipDaimyo(bool v) async {
    setState(() => _skipDaimyo = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kBgSkipDaimyoKey, v);        // ← background
    await prefs.setBool('samurai_auto_skip_daimyo', v); // ← auto service
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      try {
        final bgRunning = await FlutterForegroundTask.isRunningService;
        final status = await FlutterForegroundTask.getData<String>(
                key: 'bg_status') ??
            '';
        final extra = await FlutterForegroundTask.getData<String>(
                key: 'bg_extra') ??
            '';
        if (!mounted) return;
        setState(() {
          _bgRunning = bgRunning;
          _bgStatusText = status;
          _bgStatusExtra = extra;
        });
      } catch (_) {
        if (mounted) setState(() => _bgRunning = false);
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
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
      _camps = [];
      _scanDone = 0;
      _scanTotal = 0;
    });
    try {
      final found = await _svc.scanArea(
        source: _source!,
        radiusTiles: _settings.radiusTiles,
        maxLevel: _settings.maxLevel,
        skipPlayerCamps: _settings.skipPlayerCamps,
        includeDaimyo: _settings.includeDaimyoInScan,
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
    if (!mounted) return;
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

  // ═══════════════════════════════════════════════════════
  //  ✅ Auto toggle — يتعامل مع background + foreground
  // ═══════════════════════════════════════════════════════
  Future<void> _toggleAuto() async {
    if (_source == null) {
      _snack('اختر قلعة مصدر أولاً', color: AppTheme.red);
      return;
    }
    if (!_autoEnabled && _selectedCommanderIds.isEmpty) {
      _snack('اختر قواد أولاً (من الفلاتر تحت)',
          color: AppTheme.orange);
      return;
    }

    if (_autoEnabled) {
      // ═══ إيقاف ═══
      _auto.stop();
      await _auto.setEnabled(false);
      if (mounted) {
        setState(() => _autoEnabled = false);
        _snack('⏸️ Auto متوقف', color: AppTheme.orange);
      }
      return;
    }

    // ═══ تشغيل ═══
    // 1. حفظ المصدر
    await _auto.setSource(
      areaId: _source!.areaId,
      kid: _source!.kingdomId,
      x: _source!.x,
      y: _source!.y,
    );

    // 2. حفظ كل الإعدادات في المفاتيح الصح
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kBgMaxLevelKey, _maxLevel);
    await prefs.setBool(kBgSkipDaimyoKey, _skipDaimyo);
    await prefs.setInt(kBgRadiusKey, _settings.radiusTiles);

    // 3. تفعيل الـ flag
    await _auto.setEnabled(true);

    // 4. تشغيل الـ foreground auto (هيتخطى نفسه تلقائيًا لو background شغال)
    await _auto.start(widget.client, sourceAreaId: _source!.areaId);

    if (mounted) {
      setState(() => _autoEnabled = true);
      final bgRunning = await FlutterForegroundTask.isRunningService;
      if (bgRunning) {
        _snack('✅ Auto شغال في الخلفية (Background Service)',
            color: AppTheme.green);
      } else {
        _snack('✅ Auto شغال في المقدمة (Foreground)',
            color: AppTheme.green);
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  //  Auto: load commanders
  // ═══════════════════════════════════════════════════════
  Future<void> _loadAutoData() async {
    if (_loadingAutoData) return;
    setState(() => _loadingAutoData = true);
    try {
      final cmds = await widget.client.getCommanders();
      if (!mounted) return;
      setState(() {
        _allCommanders = cmds;
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
        emptyMeansAll: false,
      ),
    );
    if (result == null) return;
    await _auto.setCommanderIds(result.toList());
    if (mounted) setState(() => _selectedCommanderIds = result);
  }

  // ═══════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════
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
                _tabBar(),
                if (_loading)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: kSamuraiRed),
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
          if (_tabCtrl.index == 0)
            IconButton(
              icon: const Icon(Icons.tune_rounded, color: kSamuraiGold),
              onPressed: _openFilterDialog,
            ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          _tabBtn('يدوي', 0, Icons.touch_app_rounded),
          _tabBtn('تلقائي', 1, Icons.auto_awesome_rounded),
        ]),
      ),
    );
  }

  Widget _tabBtn(String label, int index, IconData icon) {
    final sel = _tabCtrl.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabCtrl.animateTo(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: sel
                ? const LinearGradient(colors: [kSamuraiRed, kSamuraiDark])
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
                      color: sel ? Colors.white : AppTheme.subTextColor(context),
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
    final filtered = _camps.toList()
      ..sort((a, b) =>
          a.distanceFromSource.compareTo(b.distanceFromSource));

    return Column(
      children: [
        _sourcePicker(),
        _filterBar(),
        if (_scanning) _progressBar(),
        Expanded(
          child: filtered.isEmpty
              ? _emptyView()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => FadeSlideIn(
                    delay: Duration(milliseconds: 30 + i * 30),
                    child: _campCard(filtered[i]),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _sourcePicker(),
        const SizedBox(height: 10),
        _bigStatusCard(),
        const SizedBox(height: 10),
        _autoControlsCard(),
        const SizedBox(height: 10),
        _autoSettingsCard(),
        const SizedBox(height: 10),
        _autoFilterCard(),
      ],
    );
  }

  Widget _bigStatusCard() {
    // ⚠️ هل فعلاً شغال؟ (foreground أو background)
    final effectivelyRunning =
        _autoEnabled && (_bgRunning || _auto.isRunning);
    final status = _auto.statusNotifier.value;
    final attacks = _auto.attacksThisSession;
    final camps = _auto.campsScanned;
    final errors = _auto.statusHistory
        .where((e) => e.message.startsWith('❌'))
        .length;

    // ✅ لون وإيموجي حسب الحالة
    Color cardColor1, cardColor2;
    IconData icon;
    String title;
    String subtitle;

    if (!_autoEnabled) {
      cardColor1 = const Color(0xFF37474F);
      cardColor2 = const Color(0xFF546E7A);
      icon = Icons.pause_rounded;
      title = 'Auto متوقف';
      subtitle = 'في انتظار التشغيل';
    } else if (_bgRunning) {
      cardColor1 = const Color(0xFF16A34A);
      cardColor2 = const Color(0xFF15803D);
      icon = Icons.bolt_rounded;
      title = '🔒 Auto في الخلفية ✓';
      subtitle = 'Background Service شغال · ${_bgStatusExtra.isNotEmpty ? _bgStatusExtra : "24/7"}';
    } else if (_auto.isRunning) {
      cardColor1 = const Color(0xFF2196F3);
      cardColor2 = const Color(0xFF1565C0);
      icon = Icons.play_circle_rounded;
      title = '⚡ Auto في المقدمة ✓';
      subtitle = 'شغال فقط لما التطبيق مفتوح';
    } else {
      cardColor1 = const Color(0xFFF59E0B);
      cardColor2 = const Color(0xFFB45309);
      icon = Icons.warning_rounded;
      title = '⚠️ Auto مفعّل بس مش شغال';
      subtitle = 'شغّل Background Service للعمل 24/7';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cardColor1, cardColor2],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cardColor1.withOpacity(0.3),
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
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10.5,
                          decoration: TextDecoration.none),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
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
              child: Text(effectivelyRunning ? 'ON' : 'OFF',
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
                Text(
                    _bgRunning && _bgStatusText.isNotEmpty
                        ? '[BG] $_bgStatusText'
                        : status,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _miniStat('معسكرات', camps.toString())),
            Expanded(child: _miniStat('هجمات', attacks.toString())),
            Expanded(child: _miniStat('أخطاء', errors.toString())),
          ]),
        ],
      ),
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

  Widget _autoControlsCard() {
    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _toggleAuto,
            icon: Icon(_autoEnabled
                ? Icons.stop_rounded
                : Icons.play_arrow_rounded),
            label: Text(_autoEnabled ? 'إيقاف Auto' : 'تشغيل Auto',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    decoration: TextDecoration.none)),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _autoEnabled ? AppTheme.red : const Color(0xFF16A34A),
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
            onPressed: () => _showStatusHistory(context),
            icon: const Icon(Icons.history_rounded, size: 16),
            label: Text(
                'عرض كل الـ status (${_auto.statusHistory.length})',
                style: const TextStyle(
                    fontSize: 12, decoration: TextDecoration.none)),
            style: OutlinedButton.styleFrom(
              foregroundColor: kSamuraiGold,
              side: const BorderSide(color: kSamuraiGold),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton.icon(
            onPressed: () async {
              await _auto.clearAllState();
              if (mounted) {
                _snack('🧹 تم مسح cooldowns + failed camps',
                    color: AppTheme.green);
              }
            },
            icon: const Icon(Icons.cleaning_services_rounded, size: 16),
            label: const Text('مسح الـ state (cooldowns)',
                style: TextStyle(
                    fontSize: 12, decoration: TextDecoration.none)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.orange,
              side: const BorderSide(color: AppTheme.orange),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        if (!_autoEnabled && _selectedCommanderIds.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.5)),
            ),
            child: const Row(children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                    '⚠️ محتاج تختار قواد أولاً عشان Auto يشتغل',
                    style: TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        decoration: TextDecoration.none)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  void _showStatusHistory(BuildContext context) {
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
                width: 44, height: 5,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(3))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Icon(Icons.history_rounded, color: kSamuraiGold, size: 20),
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
                child: _auto.statusHistory.isEmpty
                    ? const Center(
                        child: Text('لا يوجد سجل بعد',
                            style: TextStyle(
                                color: Colors.grey,
                                fontFamily: 'monospace',
                                fontSize: 11,
                                decoration: TextDecoration.none)))
                    : ListView.builder(
                        itemCount: _auto.statusHistory.length,
                        itemBuilder: (_, i) {
                          final e = _auto.statusHistory[i];
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

  Widget _autoSettingsCard() {
    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.settings_rounded, color: kSamuraiGold, size: 18),
            const SizedBox(width: 8),
            Text('إعدادات الهجوم التلقائي',
                style: TextStyle(
                    color: AppTheme.textColor(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    decoration: TextDecoration.none)),
          ]),
          const SizedBox(height: 12),

          Text('التأخير بين الهجمات (ثواني)',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.subTextColor(context),
                  decoration: TextDecoration.none)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: _numberField('أقل', '$_delayMin', _delayMin, (v) async {
                if (v < 5) v = 5;
                setState(() => _delayMin = v);
                await _auto.setDelay(min: v);
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _numberField('أكثر', '$_delayMax', _delayMax, (v) async {
                if (v < _delayMin) v = _delayMin;
                setState(() => _delayMax = v);
                await _auto.setDelay(max: v);
              }),
            ),
          ]),

          const SizedBox(height: 12),
          Divider(color: AppTheme.subTextColor(context).withOpacity(0.15)),
          const SizedBox(height: 8),

          Row(children: [
            Expanded(
              child: _numberField('أقل وحدات', '$_minUnits', _minUnits, (v) async {
                setState(() => _minUnits = v);
                await _auto.setMinUnits(v);
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _numberField('Max Lv', '$_maxLevel', _maxLevel, (v) async {
                await _saveMaxLevel(v);
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _numberField('يومي', '0=∞', _maxAttacksDay, (v) async {
                setState(() => _maxAttacksDay = v);
                await _auto.setMaxAttacksDay(v);
              }),
            ),
          ]),

          const SizedBox(height: 12),
          Divider(color: AppTheme.subTextColor(context).withOpacity(0.15)),
          const SizedBox(height: 8),

          Row(children: [
            const Text('Waves:',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    decoration: TextDecoration.none)),
            Expanded(
              child: Slider(
                value: _waves.toDouble(),
                min: 1, max: 3, divisions: 2,
                activeColor: kSamuraiRed,
                label: '$_waves',
                onChanged: (v) async {
                  final w = v.round();
                  setState(() => _waves = w);
                  await _auto.setWaves(w);
                },
              ),
            ),
            Text('$_waves',
                style: const TextStyle(
                    color: kSamuraiRed,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none)),
          ]),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('الأدوات (WID $_toolId)',
                style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textColor(context),
                    decoration: TextDecoration.none)),
            subtitle: Text(
                (_toolL + _toolR + _toolM) > 0
                    ? '$_toolL L · $_toolM M · $_toolR R'
                    : 'بدون أدوات',
                style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.subTextColor(context),
                    decoration: TextDecoration.none)),
            value: (_toolL + _toolR + _toolM) > 0,
            activeColor: kSamuraiGold,
            onChanged: (v) async {
              if (v) {
                setState(() {
                  _toolL = 20;
                  _toolR = 20;
                  _toolM = 30;
                });
                await _auto.setToolAmounts(l: 20, r: 20, m: 30);
              } else {
                setState(() {
                  _toolL = 0;
                  _toolR = 0;
                  _toolM = 0;
                });
                await _auto.setToolAmounts(l: 0, r: 0, m: 0);
              }
            },
          ),

          if ((_toolL + _toolR + _toolM) > 0)
            Row(children: [
              Expanded(
                child: _numberField('L', '$_toolL', _toolL, (v) async {
                  setState(() => _toolL = v);
                  await _auto.setToolAmounts(l: v);
                }),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _numberField('M', '$_toolM', _toolM, (v) async {
                  setState(() => _toolM = v);
                  await _auto.setToolAmounts(m: v);
                }),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _numberField('R', '$_toolR', _toolR, (v) async {
                  setState(() => _toolR = v);
                  await _auto.setToolAmounts(r: v);
                }),
              ),
            ]),

          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('تجاهل قلاع الدايميو (37/38)',
                style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textColor(context),
                    decoration: TextDecoration.none)),
            subtitle: const Text(
                'موصى به — قلاع لاعبين مش NPC',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.green,
                    decoration: TextDecoration.none)),
            value: _skipDaimyo,
            activeColor: Colors.green,
            onChanged: (v) async {
              await _saveSkipDaimyo(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _autoFilterCard() {
    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.tune_rounded, color: AppTheme.orange, size: 18),
            const SizedBox(width: 8),
            Text('فلتر القواد',
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
                color: kSamuraiGold, size: 22),
            title: const Text('القواد المسموحين',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none)),
            subtitle: Text(
                _selectedCommanderIds.isEmpty
                    ? '⚠️ مفيش محدد — لازم تختار'
                    : '${_selectedCommanderIds.length} قائد مختار',
                style: TextStyle(
                    fontSize: 11,
                    color: _selectedCommanderIds.isEmpty
                        ? Colors.orange
                        : AppTheme.subTextColor(context),
                    decoration: TextDecoration.none)),
            trailing: const Icon(Icons.edit_rounded,
                color: kSamuraiGold, size: 18),
            onTap: _openCommandersPicker,
          ),
        ],
      ),
    );
  }

  Widget _numberField(
    String label,
    String hint,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return TextField(
      controller: TextEditingController(text: value.toString())
        ..selection =
            TextSelection.collapsed(offset: value.toString().length),
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
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: kSamuraiGold.withOpacity(0.3))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kSamuraiGold)),
      ),
      onChanged: (s) {
        final v = int.tryParse(s) ?? 0;
        onChanged(v.clamp(0, 9999));
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  //  Shared widgets
  // ═══════════════════════════════════════════════════════
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
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() {
                      _source = v;
                      _settings.sourceAreaId = v.areaId;
                      _settings.save();
                    });
                    await _auto.setSource(
                      areaId: v.areaId,
                      kid: v.kingdomId,
                      x: v.x,
                      y: v.y,
                    );
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
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.trending_up_rounded,
                  color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Text('Lv ≤ ${_settings.maxLevel}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none)),
            ]),
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
    final underAttack = _svc.isCampUnderAttack(c);
    final cd = _svc.campCooldownRemaining(c);
    final dead = c.isDead;
    final daimyo = c.isDaimyoCastle;

    final borderColor = dead
        ? Colors.grey
        : daimyo
            ? Colors.orange
            : (inCooldown || underAttack ? Colors.orange : kSamuraiRed);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: (inCooldown || dead || daimyo)
            ? null
            : () => _openCampSheet(c),
        child: Opacity(
          opacity: (inCooldown || dead || daimyo) ? 0.55 : 1.0,
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
                            : daimyo
                                ? Colors.orange
                                : (inCooldown || underAttack)
                                    ? Colors.orange
                                    : kSamuraiRed)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                      dead
                          ? Icons.dangerous_rounded
                          : daimyo
                              ? Icons.lock_rounded
                              : (inCooldown || underAttack)
                                  ? Icons.hourglass_top_rounded
                                  : Icons.shield_rounded,
                      color: dead
                          ? Colors.grey
                          : daimyo
                              ? Colors.orange
                              : (inCooldown || underAttack)
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
                        else if (daimyo)
                          _pill('Daimyo', Colors.orange)
                        else if (underAttack)
                          _pill('هجوم شغال', Colors.orange)
                        else if (inCooldown)
                          _pill(
                              '${cd.inMinutes}:${(cd.inSeconds % 60).toString().padLeft(2, "0")}',
                              Colors.orange)
                        else if (c.type != 29)
                          _pill('HP ${c.hp}', kSamuraiRed)
                        else if (c.level <= 0)
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
    final result = await showModalBottomSheet<SamuraiAttackResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SamuraiAttackSheet(
        client: widget.client,
        source: _source!,
        camp: c,
        svc: _svc,
      ),
    );
    if (result != null && result.success && mounted) {
      setState(() {
        final i = _camps.indexWhere((x) => x.key == c.key);
        if (i >= 0) {
          _camps[i] = _camps[i].copyWith(
            lastAttackAt: DateTime.now(),
          );
        }
      });
      _snack(
        '✅ ${result.wavesSent} waves · ${result.totalUnits} وحدة'
        '${result.usedTools ? " · ${result.toolsUsed} أداة" : " · بدون أدوات"}',
        color: AppTheme.green,
      );
    }
  }

  // ═══════════════════════════════════════════════════════
  //  Dialogs
  // ═══════════════════════════════════════════════════════
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
                  (kSamuraiRadiusMax - kSamuraiRadiusMin) ~/ kSamuraiRadiusStep,
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
              onPressed: () async {
                setState(() {
                  _settings.radiusTiles = temp.toInt();
                });
                await _settings.save();
                // ✅ حفظ في مفتاح background أيضًا
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt(kBgRadiusKey, temp.toInt());
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('موافق'),
            ),
          ],
        ),
      ),
    );
  }

  void _openFilterDialog() {
    int maxLevel = _settings.maxLevel;
    bool skipPlayer = _settings.skipPlayerCamps;
    bool includeDaimyo = _settings.includeDaimyoInScan;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          title: const Text('فلاتر المسح',
              style: TextStyle(decoration: TextDecoration.none)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Text('Max Level:',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        decoration: TextDecoration.none)),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: maxLevel.toDouble(),
                    min: 1, max: 100,
                    divisions: 99,
                    activeColor: kSamuraiGold,
                    label: '$maxLevel',
                    onChanged: (v) => setSt(() => maxLevel = v.round()),
                  ),
                ),
                Text('$maxLevel',
                    style: const TextStyle(
                        color: kSamuraiGold,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none)),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تجاهل قلاع اللاعبين',
                    style: TextStyle(
                        fontSize: 13,
                        decoration: TextDecoration.none)),
                value: skipPlayer,
                activeColor: kSamuraiGold,
                onChanged: (v) => setSt(() => skipPlayer = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('عرض قلاع الدايميو (37/38)',
                    style: TextStyle(
                        fontSize: 13,
                        decoration: TextDecoration.none)),
                subtitle: const Text(
                    '⚠️ مش هتتهاجم في الـ Auto',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange,
                        decoration: TextDecoration.none)),
                value: includeDaimyo,
                activeColor: Colors.orange,
                onChanged: (v) => setSt(() => includeDaimyo = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                setState(() {
                  _settings.maxLevel = maxLevel;
                  _settings.skipPlayerCamps = skipPlayer;
                  _settings.includeDaimyoInScan = includeDaimyo;
                });
                await _settings.save();
                // ✅ حفظ maxLevel في مفتاح background
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt(kBgMaxLevelKey, maxLevel);
                if (ctx.mounted) Navigator.pop(ctx);
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
//  Multi-select sheet
// ═══════════════════════════════════════════════════════
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
              width: 44, height: 5,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Icon(Icons.checklist_rounded,
                  color: kSamuraiGold, size: 20),
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
                    style: const TextStyle(
                        color: kSamuraiGold, fontSize: 11)),
              ),
            ]),
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
                  activeColor: kSamuraiGold,
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
                      backgroundColor: kSamuraiGold,
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

// ═══════════════════════════════════════════════════════
//  Attack sheet (manual)
// ═══════════════════════════════════════════════════════
class _SamuraiAttackSheet extends StatefulWidget {
  final GgeClient client;
  final OwnedCastle source;
  final SamuraiCamp camp;
  final SamuraiService svc;

  const _SamuraiAttackSheet({
    required this.client,
    required this.source,
    required this.camp,
    required this.svc,
  });

  @override
  State<_SamuraiAttackSheet> createState() => _SamuraiAttackSheetState();
}

class _SamuraiAttackSheetState extends State<_SamuraiAttackSheet> {
  List<CastleUnit> _units = [];
  List<CommanderInfo> _commanders = [];
  Lord? _selectedLord;

  int _waves = 3;
  int _toolL = 20;
  int _toolR = 20;
  int _toolM = 30;
  bool _useTools = true;

  int? _manualLevel;
  bool _loading = true;
  bool _sending = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
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
            _selectedLord =
                free.firstWhere((c) => c.lord.id != 0).lord;
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

  int get _totalUnits => _units.fold<int>(0, (s, u) => s + u.amount);

  int get _effectiveLevel {
    final m = _manualLevel ?? 0;
    if (m > 0) return m;
    if (widget.camp.level > 0) return widget.camp.level;
    if (widget.camp.level2 > 0) return widget.camp.level2;
    return 0;
  }

  Future<void> _attack() async {
    if (_selectedLord == null) {
      setState(() => _lastError = 'اختر قائد');
      return;
    }
    if (_units.isEmpty) {
      setState(() => _lastError = 'مفيش وحدات قتالية في القلعة');
      return;
    }
    if (_effectiveLevel <= 0) {
      setState(() => _lastError = 'محتاج تحدد Level المعسكر يدويًا');
      return;
    }

    setState(() {
      _sending = true;
      _lastError = null;
    });

    final fallbackLords = _commanders
        .where((c) => !c.isBusy)
        .map((c) => c.lord)
        .toList();

    final config = SamuraiAttackConfig(
      waves: _waves,
      toolId: _useTools ? 166 : null,
      toolL: _toolL,
      toolR: _toolR,
      toolM: _toolM,
    );

    final res = await widget.svc.attack(
      camp: widget.camp,
      source: widget.source,
      lordId: _selectedLord!.id,
      fallbackLords: fallbackLords,
      availableUnits: _units,
      config: config,
      manualLevel: _manualLevel,
    );

    if (!mounted) return;
    setState(() => _sending = false);

    if (res.success) {
      Navigator.pop(context, res);
    } else {
      setState(() => _lastError = res.error ?? 'فشل الهجوم');
    }
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
                  borderRadius: BorderRadius.circular(3))),
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
                          ' · $_totalUnits وحدة',
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
                        if (_lastError != null) _errorBanner(),
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

  Widget _errorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.red.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.red.withOpacity(0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: AppTheme.red, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_lastError!,
              style: const TextStyle(
                  color: AppTheme.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none)),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: AppTheme.red, size: 16),
          onPressed: () => setState(() => _lastError = null),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

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
          child: Text(
              needManual
                  ? 'Level غير معروف — أدخله يدويًا'
                  : 'Level تلقائي: $autoLevel',
              style: TextStyle(
                  color: needManual ? Colors.amber : Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none)),
        ),
        SizedBox(
          width: 70,
          child: TextFormField(
            key: ValueKey('lvl_${_manualLevel ?? 0}'),
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
              hintStyle:
                  const TextStyle(color: Colors.white30, fontSize: 11),
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
              setState(() =>
                  _manualLevel = (v != null && v > 0) ? v : null);
            },
          ),
        ),
      ]),
    );
  }

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
          Row(children: [
            const Text('Waves:',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    decoration: TextDecoration.none)),
            Expanded(
              child: Slider(
                value: _waves.toDouble(),
                min: 1, max: 3, divisions: 2,
                activeColor: kSamuraiRed,
                label: '$_waves',
                onChanged: (v) => setState(() => _waves = v.round()),
              ),
            ),
            Text('$_waves',
                style: const TextStyle(
                    color: kSamuraiRed,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none)),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('استخدام الأدوات (166)',
                style: TextStyle(
                    fontSize: 12, decoration: TextDecoration.none)),
            subtitle: Text(
                _useTools
                    ? 'L $_toolL · M $_toolM · R $_toolR'
                    : 'بدون أدوات',
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white54,
                    decoration: TextDecoration.none)),
            value: _useTools,
            activeColor: kSamuraiGold,
            onChanged: (v) => setState(() => _useTools = v),
          ),
          if (_useTools) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: _toolField('L', _toolL, (v) {
                setState(() => _toolL = v);
              })),
              const SizedBox(width: 6),
              Expanded(child: _toolField('M', _toolM, (v) {
                setState(() => _toolM = v);
              })),
              const SizedBox(width: 6),
              Expanded(child: _toolField('R', _toolR, (v) {
                setState(() => _toolR = v);
              })),
            ]),
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
      onChanged: (s) => onCh(int.tryParse(s) ?? 0),
    );
  }

  Widget _previewCard() {
    final lvl = _effectiveLevel;
    if (lvl <= 0) return const SizedBox.shrink();
    final maxFlank = SamuraiMath.flankMax(lvl);
    final maxMiddle = SamuraiMath.middleMax(lvl);
    final maxWave = maxFlank * 2 + maxMiddle;

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
          Text(
              '• كل wave أقصى: $maxWave وحدة ($maxFlank L + $maxMiddle M + $maxFlank R)',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  decoration: TextDecoration.none)),
          Text('• Waves: $_waves · إجمالي وحدة: $_totalUnits',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  decoration: TextDecoration.none)),
        ],
      ),
    );
  }

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