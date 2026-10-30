import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // ✅ مهم عشان Ticker
import 'package:flutter/services.dart';
import 'package:gge/gge_client.dart';
import 'package:gge/theme.dart';
import 'package:gge/widgets/animated_widgets.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  late TabController _catCtrl;
  late TabController _dirCtrl;
  StreamSubscription? _sub;
  final _scrollCtrl = ScrollController();
  bool _autoScroll = true;
  DateTime? _lastCopied;

  @override
  void initState() {
    super.initState();
    _catCtrl = TabController(
      length: LogCategory.values.length,
      vsync: const _FakeVSync(),
    );
    _dirCtrl = TabController(length: 5, vsync: const _FakeVSync());
    _catCtrl.addListener(() => setState(() {}));
    _dirCtrl.addListener(() => setState(() {}));
    _sub = TrafficLog.entryStream.listen((_) {
      if (!mounted) return;
      setState(() {});
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollCtrl.dispose();
    _catCtrl.dispose();
    _dirCtrl.dispose();
    super.dispose();
  }

  List<LogEntry> get _filtered {
    final cat = LogCategory.values[_catCtrl.index];
    final dirIdx = _dirCtrl.index;
    final dirs = <String>['', 'TX', 'RX', 'ST', 'ER'];

    return TrafficLog.logEntries.where((e) {
      if (cat != LogCategory.all && e.category != cat) return false;
      if (dirIdx > 0 && e.dir != dirs[dirIdx]) return false;
      return true;
    }).toList();
  }

  Future<void> _copyCurrent() async {
    final list = _filtered;
    if (list.isEmpty) {
      _toast('لا يوجد شيء لنسخه', error: true);
      return;
    }
    final cat = LogCategory.values[_catCtrl.index];
    final buf = StringBuffer();
    buf.writeln('═══ GGE Log · ${cat.label} · ${list.length} entries ═══');
    buf.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buf.writeln('═══════════════════════════════════════════');
    for (final e in list) buf.writeln(e.line);

    try {
      await Clipboard.setData(ClipboardData(text: buf.toString()));
      if (!mounted) return;
      setState(() => _lastCopied = DateTime.now());
      _toast('✓ تم نسخ ${list.length} سطر');
    } catch (e) {
      if (!mounted) return;
      _toast('فشل النسخ: $e', error: true);
    }
  }

  Future<void> _copyAll() async {
    try {
      await Clipboard.setData(ClipboardData(text: TrafficLog.dump()));
      if (!mounted) return;
      setState(() => _lastCopied = DateTime.now());
      _toast('✓ تم نسخ الكل (${TrafficLog.logEntries.length})');
    } catch (e) {
      if (!mounted) return;
      _toast('فشل النسخ: $e', error: true);
    }
  }

  Future<void> _clearCurrent() async {
    final cat = LogCategory.values[_catCtrl.index];
    final msg = cat == LogCategory.all
        ? 'مسح كل الـ log؟'
        : 'مسح log فئة "${cat.label}"؟';
    final ok = await _confirm(msg);
    if (ok != true) return;
    if (cat == LogCategory.all) {
      TrafficLog.clear();
    } else {
      TrafficLog.clearCategory(cat);
    }
    if (mounted) setState(() {});
  }

  Future<bool?> _confirm(String msg) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('تأكيد',
            style: TextStyle(decoration: TextDecoration.none)),
        content:
            Text(msg, style: const TextStyle(decoration: TextDecoration.none)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            child: const Text('مسح', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content:
            Text(msg, style: const TextStyle(decoration: TextDecoration.none)),
        backgroundColor: error ? AppTheme.red : AppTheme.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  Color _colorFor(LogEntry e) {
    switch (e.dir) {
      case 'RX': return AppTheme.blue;
      case 'TX': return const Color(0xFFB8860B);
      case 'ST': return AppTheme.teal;
      case 'ER': return AppTheme.red;
      default: return AppTheme.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filtered;
    return Scaffold(
      body: Stack(
        children: [
          AppTheme.background(context),
          SafeArea(
            child: Column(
              children: [
                _header(context, entries.length),
                _catTabs(context),
                _dirTabs(context),
                Expanded(child: _list(entries)),
                _footer(context, entries.length),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, int count) {
    final cat = LogCategory.values[_catCtrl.index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(children: [
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
              Text('Traffic Log',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textColor(context),
                      letterSpacing: -0.3,
                      decoration: TextDecoration.none)),
              Text('$count entries · ${cat.label}',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.subTextColor(context),
                      decoration: TextDecoration.none)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_all_rounded, color: AppTheme.blue),
          tooltip: 'Copy all',
          onPressed: _copyAll,
        ),
        IconButton(
          icon: const Icon(Icons.delete_sweep_rounded, color: AppTheme.red),
          tooltip: 'Clear',
          onPressed: _clearCurrent,
        ),
      ]),
    );
  }

  Widget _catTabs(BuildContext context) {
    return SizedBox(
      height: 42,
      child: TabBar(
        controller: _catCtrl,
        isScrollable: true,
        labelColor: AppTheme.purple,
        unselectedLabelColor: AppTheme.subTextColor(context),
        indicatorColor: AppTheme.purple,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold,
            decoration: TextDecoration.none),
        unselectedLabelStyle: const TextStyle(
            fontSize: 11, decoration: TextDecoration.none),
        tabs: LogCategory.values.map((c) => Tab(text: c.label)).toList(),
      ),
    );
  }

  Widget _dirTabs(BuildContext context) {
    const labels = ['الكل', 'TX', 'RX', 'ST', 'ER'];
    return SizedBox(
      height: 38,
      child: TabBar(
        controller: _dirCtrl,
        labelColor: AppTheme.teal,
        unselectedLabelColor: AppTheme.subTextColor(context),
        indicatorColor: AppTheme.teal,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold,
            decoration: TextDecoration.none),
        unselectedLabelStyle: const TextStyle(
            fontSize: 11, decoration: TextDecoration.none),
        tabs: labels.map((l) => Tab(text: l)).toList(),
      ),
    );
  }

  Widget _list(List<LogEntry> entries) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: entries.isEmpty
          ? const Center(
              child: Text('لا توجد logs في هذه الفئة',
                  style: TextStyle(
                      color: Colors.grey,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      decoration: TextDecoration.none)))
          : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(8),
              itemCount: entries.length,
              itemBuilder: (_, i) {
                final e = entries[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: SelectableText(
                    e.line,
                    style: TextStyle(
                      color: _colorFor(e),
                      fontFamily: 'monospace',
                      fontSize: 10,
                      height: 1.4,
                      decoration: TextDecoration.none,
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _footer(BuildContext context, int count) {
    final copied = _lastCopied != null &&
        DateTime.now().difference(_lastCopied!).inSeconds < 3;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _copyCurrent,
            icon: Icon(copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 18),
            label: Text(copied ? 'تم النسخ ✓' : 'Copy ($count)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: copied ? AppTheme.green : AppTheme.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => setState(() => _autoScroll = !_autoScroll),
          icon: Icon(
              _autoScroll ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 18),
          label: const Text('Auto'),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _autoScroll ? AppTheme.green : AppTheme.subTextColor(context),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ]),
    );
  }
}

// ✅ FakeVSync بسيط مع import صحيح للـ Ticker
class _FakeVSync implements TickerProvider {
  const _FakeVSync();

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}