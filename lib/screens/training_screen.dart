import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gge/gge_client.dart';
import 'package:gge/l10n/strings.dart';
import 'package:gge/models.dart';
import 'package:gge/theme.dart';
import 'package:gge/widgets/animated_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SlotInfo {
  final int rut;
  final int units;
  final int? wodId;
  final DateTime fetchedAt;
  final bool isTraining;

  SlotInfo({
    required this.rut,
    required this.fetchedAt,
    this.isTraining = false,
    this.units = 0,
    this.wodId,
  });

  bool get isLocked => rut == -1;
  bool get isFree => rut == 0 && !isTraining;
  bool get isBusy => rut > 0 || isTraining;

  int get remainingSeconds {
    if (!isBusy) return 0;
    final elapsed = DateTime.now().difference(fetchedAt).inSeconds;
    return (rut - elapsed).clamp(0, 999999);
  }

  String get timeLabel {
    if (isLocked) return 'مقفول';
    if (isFree) return 'متاحة';
    final s = remainingSeconds;
    if (s <= 0) return 'خلص';
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${sec}s';
    return '${sec}s';
  }
}

class TrainingScreen extends StatefulWidget {
  final GgeClient client;
  const TrainingScreen({super.key, required this.client});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  static const int _maxPerBatch = 80;
  bool _isAutoMode = false;

  List<OwnedCastle> _castles = [];
  Map<int, UnitCatalogEntry> _catalog = {};
  OwnedCastle? _castle;

  List<UnitCatalogEntry> _trainable = [];
  UnitCatalogEntry? _selectedUnit;
  final _amountCtrl = TextEditingController(text: '10');
  bool _training = false;

  List<SlotInfo>? _slots;
  bool _slotsLoading = false;
  DateTime? _lastSlotFetch;
  Timer? _slotsTimer;
  Timer? _tickTimer;
  Timer? _autoTimer;
  int _totalTime = 0;

  // ═══ AUTO TRAIN VARIABLES ═══
  bool _autoEnabled = false;
  bool _triggerOnSlot = true;
  bool _triggerOnTime = false;
  int _timeInterval = 5;
  String _timeUnit = 'minutes';
  bool _useMaxTotal = false;
  final _maxTotalCtrl = TextEditingController(text: '1000');

  final Map<int, int> _autoSelectedAmounts = {};
  final Map<int, TextEditingController> _autoAmountCtrls = {};
  final Map<String, TextEditingController> _timeCtrl = {};

  int _autoRotationIndex = 0;
  int _autoTotalTrained = 0;

  // متغيرات الحماية من البان
  DateTime _lastActionTime = DateTime.now();
  bool _isAutoSending = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadAutoSettings();

    _slotsTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _loadSlots(silent: true);
    });

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        if (_slots != null && _slots!.any((s) => s.isBusy)) {
          setState(() {});
        }
      }
    });

    _startFrontendAutoTrainer();
  }

  @override
  void dispose() {
    _slotsTimer?.cancel();
    _tickTimer?.cancel();
    _autoTimer?.cancel();
    _amountCtrl.dispose();
    _maxTotalCtrl.dispose();
    for (var c in _autoAmountCtrls.values) {
      c.dispose();
    }
    for (var c in _timeCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _throttle() async {
    final now = DateTime.now();
    final diff = now.difference(_lastActionTime).inMilliseconds;
    if (diff < 5500) {
      final wait = 5500 - diff + Random().nextInt(1500);
      await Future.delayed(Duration(milliseconds: wait));
    } else {
      await Future.delayed(Duration(milliseconds: Random().nextInt(1000)));
    }
    _lastActionTime = DateTime.now();
  }

  void _startFrontendAutoTrainer() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!_isAutoMode || !_autoEnabled || _isAutoSending) return;
      if (_castle == null || _autoSelectedAmounts.isEmpty) return;

      // ✅ التحقق الإجباري: لو مفيش شرط متعلم عليه، نعلم على الخانة
      if (!_triggerOnSlot && !_triggerOnTime) {
        setState(() => _triggerOnSlot = true);
      }

      if (_useMaxTotal) {
        final maxTotal = int.tryParse(_maxTotalCtrl.text) ?? 0;
        if (_autoTotalTrained >= maxTotal) {
          setState(() => _autoEnabled = false);
          _saveAutoSettings();
          _snack('تم الوصول للحد الأقصى للتدريب التلقائي',
              color: AppTheme.orange);
          return;
        }
      }

      bool shouldTrain = false;

      if (_triggerOnSlot && _slots != null) {
        final hasFreeSlot = _slots!.any((s) => s.isFree);
        if (hasFreeSlot) shouldTrain = true;
      }

      if (_triggerOnTime) {
        final prefs = await SharedPreferences.getInstance();
        final lastTrainStr = prefs.getString('auto_last_train_time');
        if (lastTrainStr == null) {
          shouldTrain = true;
        } else {
          final lastTrain = DateTime.parse(lastTrainStr);
          int intervalSeconds = _timeInterval;
          if (_timeUnit == 'minutes') intervalSeconds *= 60;
          if (_timeUnit == 'hours') intervalSeconds *= 3600;

          if (DateTime.now().difference(lastTrain).inSeconds >=
              intervalSeconds) {
            shouldTrain = true;
          }
        }
      }

      if (shouldTrain) {
        _log('AutoTrain: Conditions met. Sending...');
        await _executeFrontendAutoTrain();
      }
    });
  }

  void _log(String msg) {
    TrafficLog.add('ST', '[AutoTrain] $msg');
  }

  Future<void> _executeFrontendAutoTrain() async {
    _isAutoSending = true;
    final validUnits = _autoSelectedAmounts.keys
        .where((id) => widget.client.unlockedUnitIds.contains(id))
        .toList();

    if (validUnits.isEmpty) {
      _isAutoSending = false;
      _log('No valid units selected');
      return;
    }

    if (_autoRotationIndex >= validUnits.length) _autoRotationIndex = 0;
    final wodId = validUnits[_autoRotationIndex];
    final amount = _autoSelectedAmounts[wodId] ?? 10;

    try {
      await _throttle();

      final res = await widget.client.trainUnits(
        areaId: _castle!.areaId,
        wodId: wodId,
        amount: amount,
      );

      if (res.success) {
        setState(() {
          _autoTotalTrained += amount;
          _autoRotationIndex =
              (_autoRotationIndex + 1) % validUnits.length;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            'auto_last_train_time', DateTime.now().toIso8601String());
        await prefs.setInt('auto_total_trained', _autoTotalTrained);
        await prefs.setInt('auto_rotation_index', _autoRotationIndex);

        _log('Success! WID=$wodId AMT=$amount');
        await _loadSlots(force: true);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            'auto_last_train_time', DateTime.now().toIso8601String());
        _log('Failed WID=$wodId: ${res.error}');
      }
    } catch (e) {
      _log('Error: $e');
    } finally {
      await Future.delayed(const Duration(seconds: 3));
      _isAutoSending = false;
    }
  }

  Future<void> _loadAutoSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoEnabled = prefs.getBool('auto_enabled') ?? false;
      _triggerOnSlot = prefs.getBool('auto_trigger_slot') ?? true;
      _triggerOnTime = prefs.getBool('auto_trigger_time') ?? false;
      _timeInterval = prefs.getInt('auto_time_interval') ?? 5;
      _timeUnit = prefs.getString('auto_time_unit') ?? 'minutes';
      _useMaxTotal = prefs.getBool('auto_use_max') ?? false;
      _maxTotalCtrl.text = prefs.getString('auto_max_total') ?? '1000';
      _autoTotalTrained = prefs.getInt('auto_total_trained') ?? 0;
      _autoRotationIndex = prefs.getInt('auto_rotation_index') ?? 0;

      final selectedJson = prefs.getString('auto_selected_units');
      if (selectedJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(selectedJson);
        decoded.forEach((key, val) {
          final id = int.parse(key);
          _autoSelectedAmounts[id] = val as int;
          _autoAmountCtrls[id] = TextEditingController(text: val.toString());
        });
      }
      _timeCtrl['interval'] =
          TextEditingController(text: _timeInterval.toString());
    });
  }

  Future<void> _saveAutoSettings() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('auto_enabled', _autoEnabled);
    prefs.setBool('auto_trigger_slot', _triggerOnSlot);
    prefs.setBool('auto_trigger_time', _triggerOnTime);
    prefs.setInt('auto_time_interval', _timeInterval);
    prefs.setString('auto_time_unit', _timeUnit);
    prefs.setBool('auto_use_max', _useMaxTotal);
    prefs.setString('auto_max_total', _maxTotalCtrl.text);
    prefs.setString('auto_selected_units', jsonEncode(_autoSelectedAmounts));
  }

  Future<void> _loadAll() async {
    try {
      final castles = await widget.client.getCastles();
      final catalog = await widget.client.loadCatalog();
      if (!mounted) return;

      // ✅ FIX #1: نشمل areaType=12 (External Kingdom castles)
      //    عشان قلاع الخرائط التانية تظهر (بركان, ICY, Spicy, Landy)
      //    استبعدنا 10 (Village) و 15 (Camp) — عادةً مفيش فيهم باراكس
      final trainableCastles = castles
          .where((c) =>
              c.areaType == 1 || // Main Castle
              c.areaType == 4 || // Outpost
              c.areaType == 12) // External Kingdom Castle
          .toList();

      setState(() {
        _castles = trainableCastles;
        _catalog = catalog;
        if (trainableCastles.isEmpty) {
          _castle = null;
        } else {
          _castle = trainableCastles.firstWhere(
            (c) => c.areaType == 1,
            orElse: () => trainableCastles.first,
          );
        }
        _trainable = catalog.values.where((e) => e.isTrainable).toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));

        final filtered = _filteredTrainable;
        _selectedUnit = filtered.isNotEmpty ? filtered.first : null;
      });

      if (_castle != null) {
        // ✅ FIX #3: chain sequential — jca first, then spl
        await _fetchBarracksLevel();
        await _loadSlots(force: true);
      }
    } catch (e) {
      _snack('$e', color: AppTheme.red);
    }
  }

  /// ✅ FIX #2: يستخدم `_castle!.kingdomId` بدل `KID: 0` الثابت
  ///    عشان jca يروح للمملكة الصحيحة (KID=1,2,3,4 مش بس 0)
  Future<void> _fetchBarracksLevel() async {
    if (_castle == null) return;
    try {
      await widget.client.sendXtAndWait(
        'jca',
        jsonEncode({'CID': -1, 'KID': _castle!.kingdomId}),
        responseCmd: 'jaa',
        timeoutMs: 8000,
        isAction: false,
      );
      if (mounted) setState(() {});
    } catch (e) {
      TrafficLog.add('ER', 'jca fetch error: $e');
    }
  }

  /// ✅ FIX #3: castle switch — sequential: jca → spl
  Future<void> _onCastleChanged(OwnedCastle v) async {
    setState(() {
      _castle = v;
      _slots = null;
      _selectedUnit = null;
    });

    // 1. اذهب لمملكة القلعة الجديدة (jca) — هيرجع barracks level في jaa
    await _fetchBarracksLevel();

    // 2. دلوقتي إحنا في سياق المملكة الصح — نطلب الخانات
    await _loadSlots(force: true);

    // 3. اختيار وحدة افتراضية
    if (!mounted) return;
    setState(() {
      _selectedUnit =
          _filteredTrainable.isNotEmpty ? _filteredTrainable.first : null;
    });
  }

  Future<void> _loadSlots({bool silent = false, bool force = false}) async {
    if (_slotsLoading && !force) return;
    if (!force && _lastSlotFetch != null) {
      final diff = DateTime.now().difference(_lastSlotFetch!).inSeconds;
      if (diff < 30) return;
    }
    _lastSlotFetch = DateTime.now();
    if (!silent && mounted) setState(() => _slotsLoading = true);

    try {
      final resp = await widget.client.sendXtAndWait(
        'spl',
        jsonEncode({'LID': 0}),
        responseCmd: 'spl',
        timeoutMs: 8000,
        isAction: false,
      );
      if (!mounted) return;
      if (resp.payload == null || resp.payload!.isEmpty) {
        if (mounted) setState(() => _slotsLoading = false);
        return;
      }

      final data = jsonDecode(resp.payload!) as Map<String, dynamic>;
      final spl = data['spl'] ?? data;
      final ps = spl['PS'] as Map?;
      final qs = spl['QS'] as List?;
      final tct = spl['TCT'] as num? ?? 0;

      final now = DateTime.now();
      final parsedSlots = <SlotInfo>[];

      if (ps != null && ps.isNotEmpty) {
        final rct = ps['RCT'] as num? ?? 0;
        final tua = ps['TUA'] as num? ?? 0;
        final wid = ps['WID'] as num? ?? 0;
        parsedSlots.add(SlotInfo(
          rut: rct.toInt(),
          fetchedAt: now,
          isTraining: true,
          units: tua.toInt(),
          wodId: wid.toInt(),
        ));
      } else {
        parsedSlots.add(SlotInfo(rut: 0, fetchedAt: now, isTraining: true));
      }

      if (qs != null) {
        for (final q in qs) {
          if (q is! Map) continue;
          final si = q['SI'];
          final rut = (si is Map ? si['RUT'] : null) ?? q['RUT'];
          final wid = q['WID'] as num?;
          final tua = q['TUA'] as num?;
          if (rut is num) {
            parsedSlots.add(SlotInfo(
              rut: rut.toInt(),
              fetchedAt: now,
              wodId: wid?.toInt(),
              units: tua?.toInt() ?? 0,
            ));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _slots = parsedSlots;
        _totalTime = tct.toInt();
        _slotsLoading = false;
      });
    } catch (e) {
      TrafficLog.add('ER', '[Slots] spl error: $e');
      if (mounted) setState(() => _slotsLoading = false);
    }
  }

  List<UnitCatalogEntry> get _filteredTrainable {
    final unlocked = widget.client.unlockedUnitIds;
    if (unlocked.isEmpty) return [];
    return _trainable.where((u) => unlocked.contains(u.wodId)).toList();
  }

  Future<void> _trainManual() async {
    if (_castle == null || _selectedUnit == null) return;
    final amt = int.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amt <= 0) {
      _snack(S.error, color: AppTheme.red);
      return;
    }
    if (amt > _maxPerBatch) {
      _snack(S.isAr ? 'الحد الأقصى $_maxPerBatch' : 'Max $_maxPerBatch',
          color: AppTheme.orange);
      return;
    }

    setState(() => _training = true);
    await _throttle();
    final result = await widget.client.trainUnits(
      areaId: _castle!.areaId,
      wodId: _selectedUnit!.wodId,
      amount: amt,
    );

    if (!mounted) return;
    setState(() => _training = false);

    if (result.success) {
      _snack('✓ ${S.trainingOk}', color: AppTheme.green);
      HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) await _loadSlots(force: true);
    } else {
      _snack('${S.trainingFail}: ${result.error}', color: AppTheme.red);
    }
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content:
            Text(msg, style: const TextStyle(decoration: TextDecoration.none)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
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
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                      FadeSlideIn(
                          delay: const Duration(milliseconds: 100),
                          child: _castlePicker(context)),
                      const SizedBox(height: 14),
                      FadeSlideIn(
                          delay: const Duration(milliseconds: 160),
                          child: _slotsCard(context)),
                      const SizedBox(height: 14),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 200),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _isAutoMode = false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10),
                                  decoration: BoxDecoration(
                                    color: !_isAutoMode
                                        ? AppTheme.teal.withOpacity(0.2)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: !_isAutoMode
                                            ? AppTheme.teal
                                            : Colors.grey.withOpacity(0.3)),
                                  ),
                                  child: Center(
                                      child: Text('تدريب يدوي',
                                          style: TextStyle(
                                              color: !_isAutoMode
                                                  ? AppTheme.teal
                                                  : AppTheme.subTextColor(
                                                      context),
                                              fontWeight:
                                                  FontWeight.bold))),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _isAutoMode = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _isAutoMode
                                        ? AppTheme.purple.withOpacity(0.2)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: _isAutoMode
                                            ? AppTheme.purple
                                            : Colors.grey.withOpacity(0.3)),
                                  ),
                                  child: Center(
                                      child: Text('تدريب تلقائي',
                                          style: TextStyle(
                                              color: _isAutoMode
                                                  ? AppTheme.purple
                                                  : AppTheme.subTextColor(
                                                      context),
                                              fontWeight:
                                                  FontWeight.bold))),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (!_isAutoMode) ...[
                        FadeSlideIn(
                            delay: const Duration(milliseconds: 280),
                            child: _unitPickerManual(context)),
                        const SizedBox(height: 14),
                        FadeSlideIn(
                            delay: const Duration(milliseconds: 340),
                            child: _amountInputManual(context)),
                        const SizedBox(height: 14),
                        FadeSlideIn(
                            delay: const Duration(milliseconds: 400),
                            child: _unitPreviewManual(context)),
                      ] else ...[
                        FadeSlideIn(
                            delay: const Duration(milliseconds: 280),
                            child: _autoTrainPanel(context)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!_isAutoMode)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: FadeSlideIn(
                delay: const Duration(milliseconds: 500),
                offset: const Offset(0, 0.2),
                child: GradientButton(
                  label: S.startTraining,
                  icon: Icons.play_arrow_rounded,
                  gradient: AppTheme.successGradient,
                  loading: _training,
                  onPressed: _selectedUnit != null ? _trainManual : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          AppIconBtn(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.pop(context),
              size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.trainTroops,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textColor(context),
                        letterSpacing: -0.3,
                        decoration: TextDecoration.none)),
                Text(S.trainDesc,
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.subTextColor(context),
                        decoration: TextDecoration.none)),
              ],
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                gradient: AppTheme.successGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: AppTheme.green.withOpacity(0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6))
                ]),
            child: const Icon(Icons.military_tech_rounded,
                color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _castlePicker(BuildContext context) {
    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: AppTheme.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppTheme.blue.withOpacity(0.3))),
              child: const Icon(Icons.castle_rounded,
                  color: AppTheme.blue, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.selectCastle,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.subTextColor(context),
                        letterSpacing: 0.8,
                        decoration: TextDecoration.none)),
                const SizedBox(height: 2),
                if (_castles.isEmpty)
                  Text(S.isAr ? 'لا توجد قلاع' : 'No castles',
                      style: TextStyle(
                          color: AppTheme.subTextColor(context),
                          fontSize: 12,
                          decoration: TextDecoration.none))
                else
                  DropdownButtonHideUnderline(
                    child: DropdownButton<OwnedCastle>(
                      value: _castle,
                      isExpanded: true,
                      isDense: true,
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textColor(context)),
                      items: _castles
                          .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.fullLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppTheme.textColor(context),
                                      fontSize: 13))))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        // ✅ fire and forget — التنفيذ داخل _onCastleChanged
                        unawaited(_onCastleChanged(v));
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotsCard(BuildContext context) {
    final slots = _slots;
    final loading = _slotsLoading;

    final activeSlot = slots?.firstWhere(
          (s) => s.isTraining,
          orElse: () => SlotInfo(rut: 0, fetchedAt: DateTime.now()),
        ) ??
        SlotInfo(rut: 0, fetchedAt: DateTime.now());

    final queueSlots = slots?.where((s) => !s.isTraining).toList() ?? [];

    final elapsed = _lastSlotFetch == null
        ? 0
        : DateTime.now().difference(_lastSlotFetch!).inSeconds;
    final liveTotal = (_totalTime - elapsed).clamp(0, 999999);

    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: AppTheme.purple.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.meeting_room_rounded,
                      color: AppTheme.purple, size: 18)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(S.isAr ? 'خانات التدريب' : 'Training slots',
                      style: TextStyle(
                          color: AppTheme.textColor(context),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          decoration: TextDecoration.none))),
              if (loading)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.purple))
              else
                GestureDetector(
                  onTap: () => _loadSlots(force: true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppTheme.teal.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('تحديث',
                        style: TextStyle(
                            color: AppTheme.teal,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            decoration: TextDecoration.none)),
                  ),
                ),
            ],
          ),
          if (slots != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    flex: 2,
                    child: _slotBox(context, activeSlot, isMain: true)),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: queueSlots
                        .take(5)
                        .map((s) => SizedBox(
                              width: (MediaQuery.of(context).size.width -
                                      100) /
                                  5,
                              child: _slotBox(context, s),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppTheme.blue.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_rounded,
                      size: 16, color: AppTheme.blue),
                  const SizedBox(width: 6),
                  Text(
                    'الوقت الإجمالي: ${_formatTotalTime(liveTotal)}',
                    style: const TextStyle(
                        color: AppTheme.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none),
                  ),
                ],
              ),
            ),
          ] else if (!loading) ...[
            const SizedBox(height: 8),
            Text('جاري تحميل الخانات...',
                style: TextStyle(
                    color: AppTheme.subTextColor(context),
                    fontSize: 11,
                    decoration: TextDecoration.none)),
          ],
        ],
      ),
    );
  }

  Widget _slotBox(BuildContext context, SlotInfo s, {bool isMain = false}) {
    Color c = s.isFree
        ? AppTheme.green
        : (s.isBusy ? AppTheme.orange : AppTheme.subTextColor(context));

    String unitName = '';
    if (s.isBusy && s.wodId != null) {
      final catalogEntry = _catalog[s.wodId];
      if (catalogEntry != null) {
        unitName = S.unitName(catalogEntry.displayName);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            s.isFree
                ? Icons.check_circle_outline_rounded
                : (s.isBusy
                    ? Icons.hourglass_top_rounded
                    : Icons.lock_rounded),
            color: c,
            size: isMain ? 24 : 18,
          ),
          const SizedBox(height: 4),
          if (isMain) ...[
            Text(s.timeLabel,
                style: TextStyle(
                    color: c,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none),
                textAlign: TextAlign.center),
            if (s.isBusy) ...[
              Text(unitName,
                  style: TextStyle(
                      color: c, fontSize: 10, decoration: TextDecoration.none),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
              Text('${s.units} جندي',
                  style: TextStyle(
                      color: c,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none)),
            ]
          ] else ...[
            Text(
              s.isFree ? 'متاحة' : (s.isBusy ? 'مشغولة' : 'مقفولة'),
              style: TextStyle(
                  color: c,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none),
            ),
            if (s.isBusy)
              Text(s.timeLabel,
                  style: TextStyle(
                      color: c, fontSize: 8, decoration: TextDecoration.none)),
          ],
        ],
      ),
    );
  }

  String _formatTotalTime(int totalSeconds) {
    if (totalSeconds <= 0) return '0s';
    final d = totalSeconds ~/ 86400;
    final h = (totalSeconds % 86400) ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Widget _unitPickerManual(BuildContext context) {
    final filtered = _filteredTrainable;
    if (filtered.isEmpty) return const SizedBox.shrink();

    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: AppTheme.teal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppTheme.teal.withOpacity(0.3))),
              child: const Icon(Icons.gavel_rounded,
                  color: AppTheme.teal, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.unitType,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.subTextColor(context),
                        letterSpacing: 0.8,
                        decoration: TextDecoration.none)),
                const SizedBox(height: 2),
                DropdownButtonHideUnderline(
                  child: DropdownButton<UnitCatalogEntry>(
                    value: filtered.contains(_selectedUnit)
                        ? _selectedUnit
                        : filtered.first,
                    isExpanded: true,
                    isDense: true,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textColor(context)),
                    items: filtered.map((u) {
                      return DropdownMenuItem(
                        value: u,
                        child: Row(
                          children: [
                            Icon(
                                u.role == 'ranged'
                                    ? Icons.gps_fixed_rounded
                                    : Icons.gavel_rounded,
                                size: 14,
                                color: u.role == 'ranged'
                                    ? AppTheme.teal
                                    : AppTheme.red),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(S.unitName(u.displayName),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color:
                                            AppTheme.textColor(context)))),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedUnit = v),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountInputManual(BuildContext context) {
    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: AppTheme.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppTheme.orange.withOpacity(0.3))),
              child: const Icon(Icons.numbers_rounded,
                  color: AppTheme.orange, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(S.amount,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.subTextColor(context),
                            letterSpacing: 0.8,
                            decoration: TextDecoration.none)),
                    const SizedBox(width: 6),
                    Text('(حد أقصى $_maxPerBatch)',
                        style: TextStyle(
                            fontSize: 9,
                            color: AppTheme.subTextColor(context)
                                .withOpacity(0.7),
                            decoration: TextDecoration.none)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        style: TextStyle(
                            color: AppTheme.textColor(context),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none),
                        decoration: const InputDecoration(
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 6),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _stepBtn(
                        icon: Icons.keyboard_double_arrow_up_rounded,
                        color: AppTheme.green,
                        tooltip: '80',
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _amountCtrl.text = _maxPerBatch.toString();
                          setState(() {});
                        }),
                    const SizedBox(width: 6),
                    _stepBtn(
                        icon: Icons.keyboard_double_arrow_down_rounded,
                        color: AppTheme.red,
                        tooltip: '1',
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _amountCtrl.text = '1';
                          setState(() {});
                        }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _unitPreviewManual(BuildContext context) {
    if (_selectedUnit == null) return const SizedBox.shrink();
    final u = _selectedUnit!;
    final isRanged = u.role == 'ranged';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: isRanged
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF00B894), Color(0xFF00D68F)])
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEC4899), Color(0xFFFF8E53)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: (isRanged ? AppTheme.green : AppTheme.pink)
                  .withOpacity(0.35),
              blurRadius: 22,
              offset: const Offset(0, 10))
        ],
      ),
      child: Row(
        children: [
          Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withOpacity(0.2))),
              child: Icon(
                  isRanged
                      ? Icons.gps_fixed_rounded
                      : Icons.gavel_rounded,
                  color: Colors.white,
                  size: 32)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.unitName(u.displayName),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        decoration: TextDecoration.none)),
                const SizedBox(height: 4),
                Text(isRanged ? 'Ranged · Offense' : 'Melee · Offense',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 11.5,
                        decoration: TextDecoration.none)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.2))),
            child: Text('x${_amountCtrl.text}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    decoration: TextDecoration.none)),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(
      {required IconData icon,
      required Color color,
      required String tooltip,
      required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.35))),
              child: Icon(icon, color: color, size: 22)),
        ),
      ),
    );
  }

  Widget _autoTrainPanel(BuildContext context) {
    final filtered = _filteredTrainable;

    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.autorenew_rounded,
                  color: AppTheme.purple, size: 20),
              const SizedBox(width: 8),
              Text('التدريب التلقائي',
                  style: TextStyle(
                      color: AppTheme.textColor(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      decoration: TextDecoration.none)),
              const Spacer(),
              Switch(
                value: _autoEnabled,
                onChanged: (v) {
                  setState(() {
                    _autoEnabled = v;
                    if (v && !_triggerOnSlot && !_triggerOnTime) {
                      _triggerOnSlot = true;
                    }
                  });
                  _saveAutoSettings();
                },
                activeColor: AppTheme.purple,
              ),
            ],
          ),
          const Divider(),
          Text('شروط التشغيل:',
              style: TextStyle(
                  color: AppTheme.subTextColor(context),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none)),
          CheckboxListTile(
            title: Text('عند توفر خانة فارغة',
                style: TextStyle(
                    color: AppTheme.textColor(context),
                    fontSize: 13,
                    decoration: TextDecoration.none)),
            value: _triggerOnSlot,
            activeColor: AppTheme.purple,
            onChanged: (v) {
              setState(() => _triggerOnSlot = v ?? true);
              _saveAutoSettings();
            },
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          CheckboxListTile(
            title: Text('حسب الوقت',
                style: TextStyle(
                    color: AppTheme.textColor(context),
                    fontSize: 13,
                    decoration: TextDecoration.none)),
            value: _triggerOnTime,
            activeColor: AppTheme.purple,
            onChanged: (v) {
              setState(() => _triggerOnTime = v ?? false);
              _saveAutoSettings();
            },
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          if (_triggerOnTime)
            Padding(
              padding: const EdgeInsets.only(right: 32, bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _timeCtrl['interval'],
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: AppTheme.textColor(context)),
                      decoration: const InputDecoration(
                          isDense: true, hintText: 'الوقت'),
                      onChanged: (v) {
                        _timeInterval = int.tryParse(v) ?? 5;
                        _saveAutoSettings();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  DropdownButton<String>(
                    value: _timeUnit,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    items: const [
                      DropdownMenuItem(value: 'seconds', child: Text('ثواني')),
                      DropdownMenuItem(value: 'minutes', child: Text('دقائق')),
                      DropdownMenuItem(value: 'hours', child: Text('ساعات')),
                    ],
                    onChanged: (v) {
                      setState(() => _timeUnit = v ?? 'minutes');
                      _saveAutoSettings();
                    },
                  ),
                ],
              ),
            ),
          const Divider(),
          CheckboxListTile(
            title: Text('تحديد أقصى عدد للتدريب',
                style: TextStyle(
                    color: AppTheme.textColor(context),
                    fontSize: 13,
                    decoration: TextDecoration.none)),
            value: _useMaxTotal,
            activeColor: AppTheme.purple,
            onChanged: (v) {
              setState(() => _useMaxTotal = v ?? false);
              _saveAutoSettings();
            },
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          if (_useMaxTotal) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _maxTotalCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: AppTheme.textColor(context)),
                      decoration: const InputDecoration(
                          isDense: true, hintText: 'أقصى عدد'),
                      onChanged: (_) => _saveAutoSettings(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('تم تدريب: $_autoTotalTrained',
                      style: TextStyle(
                          color: AppTheme.subTextColor(context),
                          fontSize: 12,
                          decoration: TextDecoration.none)),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const Divider(),
          Text('الوحدات المطلوبة:',
              style: TextStyle(
                  color: AppTheme.subTextColor(context),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none)),
          const SizedBox(height: 8),
          ...filtered.map((u) {
            final isSelected = _autoSelectedAmounts.containsKey(u.wodId);
            if (!_autoAmountCtrls.containsKey(u.wodId)) {
              _autoAmountCtrls[u.wodId] =
                  TextEditingController(text: '10');
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.purple.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: isSelected
                        ? AppTheme.purple.withOpacity(0.5)
                        : Colors.grey.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        activeColor: AppTheme.purple,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _autoSelectedAmounts[u.wodId] = int.tryParse(
                                      _autoAmountCtrls[u.wodId]!.text) ??
                                  10;
                            } else {
                              _autoSelectedAmounts.remove(u.wodId);
                            }
                          });
                          _saveAutoSettings();
                        },
                      ),
                      Expanded(
                        child: Text(S.unitName(u.displayName),
                            style: TextStyle(
                                color: AppTheme.textColor(context),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none)),
                      ),
                    ],
                  ),
                  if (isSelected)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 40),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: TextField(
                                controller: _autoAmountCtrls[u.wodId],
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppTheme.textColor(context),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          vertical: 8),
                                  filled: true,
                                  fillColor: AppTheme.isDark(context)
                                      ? Colors.black26
                                      : Colors.grey.shade200,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none),
                                ),
                                onChanged: (v) {
                                  _autoSelectedAmounts[u.wodId] =
                                      int.tryParse(v) ?? 10;
                                  _saveAutoSettings();
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              _autoAmountCtrls[u.wodId]!.text = '80';
                              _autoSelectedAmounts[u.wodId] = 80;
                              _saveAutoSettings();
                              setState(() {});
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                  color: AppTheme.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color:
                                          AppTheme.green.withOpacity(0.4))),
                              child: const Text('80',
                                  style: TextStyle(
                                      color: AppTheme.green,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () {
                              _autoAmountCtrls[u.wodId]!.text = '0';
                              _autoSelectedAmounts[u.wodId] = 0;
                              _saveAutoSettings();
                              setState(() {});
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                  color: AppTheme.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppTheme.red.withOpacity(0.4))),
                              child: const Icon(Icons.refresh_rounded,
                                  color: AppTheme.red, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }),
          if (_autoEnabled && _autoSelectedAmounts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                  'يرجى اختيار وحدة واحدة على الأقل للتدريب التلقائي.',
                  style: TextStyle(
                      color: AppTheme.red,
                      fontSize: 12,
                      decoration: TextDecoration.none)),
            ),
        ],
      ),
    );
  }
}