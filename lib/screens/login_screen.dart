import 'package:flutter/material.dart';
import 'package:gge/gge_client.dart';
import 'package:gge/l10n/strings.dart';
import 'package:gge/models.dart';
import 'package:gge/theme.dart';
import 'package:gge/main.dart' show GgeApp, GgeAppState;
import 'package:gge/screens/main_screen.dart' show MainScreen;
import 'package:gge/widgets/animated_widgets.dart';
import 'package:gge/services/notifications_service.dart';
import 'package:gge/services/background_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _client = GgeClient();

  bool _loading = false;
  String? _error;
  bool _obscure = true;
  bool _checkedPermissions = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final u = await AppStorage.getUsername();
    final p = await AppStorage.getPassword();

    if (!mounted) return;
    _userCtrl.text = u ?? '';
    _passCtrl.text = p ?? '';

    if (!_checkedPermissions) {
      _checkedPermissions = true;
      await _ensureNotificationPermission();
    }
    // ✅ شيلنا شرط الـ Auto-Login اللي كان بيدوس على الزرار
  }

  Future<void> _ensureNotificationPermission() async {
    try {
      final granted = await NotificationsService.checkPermission();
      if (granted) return;

      if (!mounted) return;
      final asked = await NotificationsService.hasAskedBefore();
      if (!asked) {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('تفعيل الإشعارات',
                style: TextStyle(decoration: TextDecoration.none)),
            content: const Text(
              'عشان نبهك أول ما حد يهجم عليك — لازم تسمح لنا نبعت إشعارات.\n\n'
              'ده مهم جداً عشان تلحق تتصرف قبل وصول الجيش.',
              style: TextStyle(decoration: TextDecoration.none, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('مش دلوقتي'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.purple),
                child: const Text('تفعيل',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }

      await NotificationsService.requestPermission();
    } catch (_) {}
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    final u = _userCtrl.text.trim();
    final p = _passCtrl.text;

    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = 'Please enter username and password');
      return;
    }

    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      await AppStorage.setUsername(u);
      await AppStorage.setPassword(p);

      if (!_client.isConnected) {
        await _client.connect();
      }
      await _client.loginWithPassword(u, p);
      await _client.loadCatalog();
      await _client.getCastles();

      await AppStorage.setLoggedIn(true);

      NotificationsService.startListening();
      BackgroundService.start().catchError((e) {});

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainScreen(client: _client)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      await AppStorage.setLoggedIn(false);
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = GgeApp.of(context);

    return Scaffold(
      body: Stack(
        children: [
          AppTheme.background(context),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    children: [
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 50),
                        child: _topRow(app),
                      ),
                      const SizedBox(height: 40),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 150),
                        offset: const Offset(0, -0.2),
                        child: _logoCard(),
                      ),
                      const SizedBox(height: 30),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 300),
                        child: _formCard(),
                      ),
                      const SizedBox(height: 20),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 500),
                        child: Text(
                          'SmokJ',
                          style: TextStyle(
                            color: AppTheme.subTextColor(context)
                                .withOpacity(0.4),
                            fontSize: 11,
                            letterSpacing: 4,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topRow(GgeAppState app) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppIconBtn(
          icon: Icons.translate_rounded,
          onTap: app.toggleLocale,
          size: 42,
        ),
        const SizedBox(width: 10),
        AppIconBtn(
          icon: app.isDark
              ? Icons.light_mode_rounded
              : Icons.dark_mode_rounded,
          onTap: app.toggleTheme,
          size: 42,
        ),
      ],
    );
  }

  Widget _logoCard() {
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppTheme.purple.withOpacity(0.5),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child:
              const Icon(Icons.castle_rounded, color: Colors.white, size: 48),
        ),
        const SizedBox(height: 20),
        Text(
          S.appName,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppTheme.textColor(context),
            letterSpacing: -0.5,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  Widget _formCard() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.darkSurface.withOpacity(0.7)
            : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: dark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.04),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.purple.withOpacity(dark ? 0.2 : 0.1),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sign in',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textColor(context),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your credentials are saved locally',
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.subTextColor(context),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _userCtrl,
            style: TextStyle(color: AppTheme.textColor(context)),
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon:
                  Icon(Icons.person_outline_rounded, color: AppTheme.purple),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            style: TextStyle(color: AppTheme.textColor(context)),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded,
                  color: AppTheme.purple),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: AppTheme.subTextColor(context),
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _login(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppTheme.red, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppTheme.red,
                        fontSize: 12,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          GradientButton(
            label: _loading ? S.connecting : S.login,
            icon: Icons.login_rounded,
            gradient: AppTheme.primaryGradient,
            loading: _loading,
            onPressed: _login,
          ),
        ],
      ),
    );
  }
}