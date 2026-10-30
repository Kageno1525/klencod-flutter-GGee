import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gge/gge_client.dart';
import 'package:gge/l10n/strings.dart';
import 'package:gge/models.dart';
import 'package:gge/theme.dart';
import 'package:gge/widgets/animated_widgets.dart';

class CommandersScreen extends StatefulWidget {
  final GgeClient client;
  const CommandersScreen({super.key, required this.client});

  @override
  State<CommandersScreen> createState() => _CommandersScreenState();
}

class _CommandersScreenState extends State<CommandersScreen> {
  List<CommanderInfo> _commanders = [];
  bool _loading = true;
  Timer? _timer;

  /// عدد مرات محاولة reload تلقائي بعد ما تنتهي الحركات.
  /// بيمنع spam على gam لو السيرفر لسه بيرجع الحركات القديمة.
  int _staleReloadAttempts = 0;
  static const int _maxStaleReloadAttempts = 3;

  @override
  void initState() {
    super.initState();
    _loadCommanders();
  }

  Future<void> _loadCommanders({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
      _staleReloadAttempts = 0;
    }
    try {
      final cmds = await widget.client.getCommanders();
      if (!mounted) return;
      setState(() {
        _commanders = cmds;
        if (!silent) _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() => _loading = false);
        _snack('$e', color: AppTheme.red);
      }
    } finally {
      if (mounted) _startTimer();
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Timer — بيحدث الـ countdowns و يكتشف transition
  //  (قائد وصل / stationed خلص) و يعمل reload تلقائي.
  // ═══════════════════════════════════════════════════════════
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      // مفيش أي movement في الكاش — بلاش timer أصلاً
      final hasAnyMovement = _commanders.any((c) => c.movement != null);
      if (!hasAnyMovement) {
        _timer?.cancel();
        return;
      }

      // فيه حركة "شغالة" فعلاً (مسافرة أو stationed لسه في الدعم)
      final hasActiveMovement = _commanders.any((c) =>
          c.movement != null && !_isMovementFullyDone(c.movement!));

      if (hasActiveMovement) {
        // حدّث الـ countdowns
        setState(() {});
        return;
      }

      // كل الحركات في الكاش خلصت — اعمل setState نهائي، ألغِ الـ timer،
      // و جرّب reload واحد لتنضيف الكاش (بدون spam)
      setState(() {});
      _timer?.cancel();
      _silentReloadAndRestart();
    });
  }

  bool _isMovementFullyDone(LordMovement m) {
    // لسه بيسافر
    if (!m.isArrived) return false;
    // stationed و لسه في وقت الدعم
    if (m.type == 1 && m.isStationed) return false;
    // غير كده → خلص تماماً
    return true;
  }

  Future<void> _silentReloadAndRestart() async {
    if (_staleReloadAttempts >= _maxStaleReloadAttempts) {
      // السيرفر لسه بيرجع الحركات القديمة — استسلم، المستخدم يعمل refresh يدوي.
      return;
    }
    _staleReloadAttempts++;

    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    await _loadCommanders(silent: true);
    if (!mounted) return;

    // لو الـ reload نجح و نضّف الحركات، صفّر العداد
    final stillStale = _commanders.any((c) =>
        c.movement != null && _isMovementFullyDone(c.movement!));
    if (!stillStale) {
      _staleReloadAttempts = 0;
    }
  }

  Future<void> _recall(CommanderInfo cmd) async {
    if (cmd.movement == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(S.recall,
            style: const TextStyle(decoration: TextDecoration.none)),
        content: Text('${S.recall} ${cmd.lord.displayName}?',
            style: const TextStyle(decoration: TextDecoration.none)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(S.cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
              child: Text(S.recall,
                  style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    final res = await widget.client.recallMovement(cmd.movement!.movementId);

    if (!mounted) return;

    if (res.success) {
      _snack('✓ ${S.recallSuccess}', color: AppTheme.green);
      await _loadCommanders();
    } else {
      setState(() => _loading = false);
      _snack('${S.recallFail}: ${res.error}', color: AppTheme.red);
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
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
                  child: _loading
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(
                                  color: AppTheme.purple),
                              const SizedBox(height: 16),
                              Text(
                                'Loading commanders...',
                                style: TextStyle(
                                    color: AppTheme.subTextColor(context),
                                    fontSize: 12,
                                    decoration: TextDecoration.none),
                              ),
                            ],
                          ),
                        )
                      : _commanders.isEmpty
                          ? _empty(context)
                          : RefreshIndicator(
                              onRefresh: () => _loadCommanders(),
                              color: AppTheme.purple,
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                itemCount: _commanders.length,
                                itemBuilder: (_, i) => FadeSlideIn(
                                  delay:
                                      Duration(milliseconds: 100 + i * 60),
                                  child:
                                      _commanderCard(context, _commanders[i]),
                                ),
                              ),
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final busyCount = _commanders.where((c) => c.isBusy).length;
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
                Text(
                  S.commanders,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textColor(context),
                    letterSpacing: -0.3,
                    decoration: TextDecoration.none,
                  ),
                ),
                Text(
                  '$busyCount / ${_commanders.length} ${S.commanderBusy}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.subTextColor(context),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          AppIconBtn(
            icon: Icons.refresh_rounded,
            onTap: _loading ? null : () => _loadCommanders(),
            size: 42,
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.purple.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.purple.withOpacity(0.3)),
            ),
            child: Icon(Icons.people_outline_rounded,
                size: 56, color: AppTheme.purple.withOpacity(0.7)),
          ),
          const SizedBox(height: 16),
          Text(
            S.noCommanders,
            style: TextStyle(
              color: AppTheme.subTextColor(context),
              fontSize: 14,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _commanderCard(BuildContext context, CommanderInfo cmd) {
    final movement = cmd.movement;
    final isBusy = cmd.isBusy;
    final isStationed = movement?.isStationed ?? false;
    final isReturning = movement?.isReturning ?? false;
    final accent = isBusy ? AppTheme.orange : AppTheme.green;
    final gradient =
        isBusy ? AppTheme.orangeGradient : AppTheme.successGradient;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surface
            .withOpacity(AppTheme.isDark(context) ? 0.6 : 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.25), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${cmd.lord.visibleIndex + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cmd.lord.displayName,
                        style: TextStyle(
                          color: AppTheme.textColor(context),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: accent.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isBusy ? S.commanderBusy : S.commanderFree,
                              style: TextStyle(
                                color: accent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isBusy && movement != null) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.isDark(context)
                    ? Colors.white.withOpacity(0.04)
                    : Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withOpacity(0.15)),
              ),
              child: Column(
                children: [
                  // ─── Action row ─────────────────────────────
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isStationed
                              ? Icons.flag_rounded
                              : (isReturning
                                  ? Icons.undo_rounded
                                  : movement.type == 1
                                      ? Icons.shield_rounded
                                      : Icons.gavel_rounded),
                          color: accent,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isStationed
                              ? (S.isAr
                                  ? 'متمركز في قلعة الحليف'
                                  : 'Stationed at ally')
                              : movement.actionLabel,
                          style: TextStyle(
                            color: AppTheme.textColor(context),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ─── Target ──────────────────────────────────
                  Row(
                    children: [
                      const Icon(Icons.place_rounded,
                          color: AppTheme.blue, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${movement.targetPlayerName ?? "Unknown"} '
                          '(${movement.targetX}, ${movement.targetY})',
                          style: TextStyle(
                            color: AppTheme.subTextColor(context),
                            fontSize: 11.5,
                            decoration: TextDecoration.none,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ─── Started + Return time ──────────────────
                  Row(
                    children: [
                      const Icon(Icons.play_arrow_rounded,
                          size: 12, color: AppTheme.blue),
                      const SizedBox(width: 4),
                      Text(
                        '${S.isAr ? "بدأ" : "Started"}: ${movement.startedAtLabel}',
                        style: TextStyle(
                            color: AppTheme.subTextColor(context),
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            decoration: TextDecoration.none),
                      ),
                      const Spacer(),
                      // ✅ لما stationed: نعرض وقت الرجوع المتوقع (returnAt)
                      //    غير كده: نعرض وقت الوصول (arrivalAt)
                      Icon(
                        movement.isArrived
                            ? Icons.check_circle_rounded
                            : Icons.flag_rounded,
                        size: 12,
                        color: movement.isArrived
                            ? AppTheme.green
                            : AppTheme.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isStationed
                            ? '${S.isAr ? "يعود" : "Returns"}: ${movement.stationReturnAtLabel ?? "..."}'
                            : (movement.isArrived
                                ? (S.isAr ? 'وصل' : 'Arrived')
                                : '${S.isAr ? "هيوصل" : "Arrives"}: ${movement.arrivalAtLabel}'),
                        style: TextStyle(
                            color: movement.isArrived
                                ? AppTheme.green
                                : AppTheme.orange,
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            decoration: TextDecoration.none),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ─── Countdown ───────────────────────────────
                  Row(
                    children: [
                      const Icon(Icons.timer_rounded,
                          color: AppTheme.orange, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        isStationed
                            ? (S.isAr
                                ? 'الوقت المتبقي في الدعم'
                                : 'Station time remaining')
                            : S.timeRemaining,
                        style: TextStyle(
                          color: AppTheme.subTextColor(context),
                          fontSize: 11.5,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.blue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          movement.timeLabel,
                          style: const TextStyle(
                            color: AppTheme.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!isReturning && !isStationed)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: () => _recall(cmd),
                    icon: const Icon(Icons.undo_rounded,
                        color: AppTheme.red, size: 18),
                    label: Text(S.recall,
                        style: const TextStyle(
                            color: AppTheme.red,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: AppTheme.red.withOpacity(0.5), width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      backgroundColor: AppTheme.red.withOpacity(0.08),
                    ),
                  ),
                ),
              )
            else if (isStationed)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: () => _recall(cmd),
                    icon: const Icon(Icons.undo_rounded,
                        color: AppTheme.orange, size: 18),
                    label: Text(
                        S.isAr ? 'استرجاع القائد' : 'Recall commander',
                        style: const TextStyle(
                            color: AppTheme.orange,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: AppTheme.orange.withOpacity(0.5),
                          width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      backgroundColor: AppTheme.orange.withOpacity(0.08),
                    ),
                  ),
                ),
              ),
          ] else
            const SizedBox(height: 14),
        ],
      ),
    );
  }
}