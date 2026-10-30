import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ إضافة
import 'package:gge/gge_client.dart';
import 'package:gge/l10n/strings.dart';
import 'package:gge/models.dart';
import 'package:gge/theme.dart';
import 'package:gge/screens/login_screen.dart';
import 'package:gge/services/notifications_service.dart';
import 'package:gge/services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool dark = true;
  Locale locale = const Locale('ar');
  try {
    dark = await AppStorage.getDarkMode()
        .timeout(const Duration(seconds: 2), onTimeout: () => true);
    final lang = await AppStorage.getLanguageCode()
        .timeout(const Duration(seconds: 2), onTimeout: () => 'ar');
    locale = Locale(lang);
  } catch (_) {}
  S.current = locale;

  runApp(GgeApp(initialDark: dark));

  unawaited(BackgroundService.init().catchError((e) {
    debugPrint('[Init] BackgroundService: $e');
  }));
  unawaited(NotificationsService.init().catchError((e) {
    debugPrint('[Init] NotificationsService: $e');
  }));

  try {
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data is String) {
        TrafficLog.add('ST', '[BG-IN] $data');
      }
    });
  } catch (e) {
    debugPrint('[Init] addTaskDataCallback: $e');
  }
}

class GgeApp extends StatefulWidget {
  final bool initialDark;
  const GgeApp({super.key, required this.initialDark});

  static GgeAppState of(BuildContext context) =>
      context.findAncestorStateOfType<GgeAppState>()!;

  @override
  State<GgeApp> createState() => GgeAppState();
}

class GgeAppState extends State<GgeApp> with WidgetsBindingObserver {
  late bool _isDark;
  late Locale _locale;

  bool get isDark => _isDark;
  Locale get locale => _locale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isDark = widget.initialDark;
    _locale = S.current;
    unawaited(_updateForegroundState(true)); // ✅ التطبيق فتح
    unawaited(_logBgWsStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    GgeClient().onAppLifecycleChanged(state);
    
    // ✅ حفظ حالة التطبيق (مفتوح/مقفول) عشان الخدمة الخلفية
    unawaited(_updateForegroundState(state == AppLifecycleState.resumed));

    if (state == AppLifecycleState.resumed) {
      unawaited(_logBgWsStatus());
    }
  }

  // ✅ دالة جديدة
  Future<void> _updateForegroundState(bool isForeground) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_app_foreground', isForeground);
      TrafficLog.add('ST', '[Lifecycle] App Foreground: $isForeground');
    } catch (_) {}
  }

  Future<void> _logBgWsStatus() async {
    try {
      final info = await BackgroundService.readStatus();
      TrafficLog.add('ST',
          '[BG Status] ${info['status']} @ ${info['time']} (msgs=${info['msgs']})');
    } catch (e) {
      TrafficLog.add('ER', '[BG Status] read failed: $e');
    }
  }

  Future<void> toggleTheme() async {
    setState(() => _isDark = !_isDark);
    await AppStorage.setDarkMode(_isDark);
  }

  Future<void> toggleLocale() async {
    final newCode = S.isAr ? 'en' : 'ar';
    S.current = Locale(newCode);
    await AppStorage.setLanguageCode(newCode);
    setState(() => _locale = S.current);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GGE Bot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      locale: _locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: S.isAr ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: const LoginScreen(),
    );
  }
}