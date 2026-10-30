import 'package:flutter/material.dart';
import 'package:gge/gge_client.dart';
import 'package:gge/l10n/strings.dart';
import 'package:gge/main.dart' show GgeApp, GgeAppState;
import 'package:gge/models.dart';
import 'package:gge/theme.dart';
import 'package:gge/widgets/animated_widgets.dart';
import 'package:gge/screens/transfer_screen.dart';
import 'package:gge/screens/training_screen.dart';
import 'package:gge/screens/smuggle_screen.dart';
import 'package:gge/screens/commanders_screen.dart';
import 'package:gge/screens/login_screen.dart';
import 'package:gge/screens/stats_screen.dart';
import 'package:gge/screens/notifications_screen.dart';
import 'package:gge/services/notifications_service.dart';
import 'package:gge/services/background_service.dart';
import 'package:gge/screens/auto_defense_screen.dart';
import 'package:gge/screens/attack_screen.dart';
import 'package:gge/screens/desert_attack_screen.dart';
import 'package:gge/screens/logs_screen.dart';
import 'package:gge/screens/inventory_screen.dart';
import 'package:gge/screens/samurai_screen.dart'; // ✅ NEW

class MainScreen extends StatefulWidget {
  final GgeClient client;
  const MainScreen({super.key, required this.client});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String _username = '';
  bool _isKicked = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
    widget.client.onSessionConflict = _handleSessionConflict;
  }

  Future<void> _loadUser() async {
    final u = await AppStorage.getUsername();
    if (mounted) setState(() => _username = u ?? '');
  }

  Future<void> _handleSessionConflict() async {
    if (_isKicked || !mounted) return;
    _isKicked = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('انتهت الجلسة',
            style: TextStyle(decoration: TextDecoration.none)),
        content: const Text(
          'تم تسجيل الدخول لحسابك من مكان آخر (لعبت من الموبايل أو الكمبيوتر).\n\n'
          'هيتم تسجيل خروجك من التطبيق عشان ميحصلش تعارض.',
          style: TextStyle(decoration: TextDecoration.none, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.purple),
            child: const Text('حسناً', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    await _performLogout();
  }

  Future<void> _performLogout() async {
    try {
      await BackgroundService.stop();
    } catch (_) {}
    try {
      NotificationsService.stopListening();
      NotificationsService.clearHistory();
    } catch (_) {}

    await AppStorage.setLoggedIn(false);
    await AppStorage.setToken('');
    await widget.client.dispose();

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = GgeApp.of(context);

    return Scaffold(
      body: Stack(
        children: [
          AppTheme.background(context),
          SafeArea(
            child: Column(
              children: [
                _header(context, app),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _heroCard(context),
                      const SizedBox(height: 20),
                      _gridSection(context),
                      const SizedBox(height: 24),
                      _footer(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, GgeAppState app) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.purple.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.castle_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.appName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textColor(context),
                    letterSpacing: -0.3,
                    decoration: TextDecoration.none,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  S.mainTitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.subTextColor(context),
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          AppIconBtn(
            icon: Icons.translate_rounded,
            onTap: app.toggleLocale,
            size: 40,
          ),
          const SizedBox(width: 8),
          AppIconBtn(
            icon: app.isDark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
            onTap: app.toggleTheme,
            size: 40,
          ),
          const SizedBox(width: 8),
          AppIconBtn(
            icon: Icons.logout_rounded,
            onTap: () => _confirmLogout(context),
            color: AppTheme.red,
            size: 40,
          ),
        ],
      ),
    );
  }

  Widget _heroCard(BuildContext context) {
    return FadeSlideIn(
      delay: const Duration(milliseconds: 100),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3F51B5), Color(0xFF6C5CE7)],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C5CE7).withOpacity(0.35),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${S.welcome} $_username',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: const [
                _Pill(icon: Icons.bolt_rounded, label: 'Live'),
                _Pill(icon: Icons.shield_rounded, label: 'Anti-Ban'),
                _Pill(icon: Icons.sync_rounded, label: 'Auto-Reconnect'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _gridSection(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.2,
      children: [
        FadeSlideIn(
          delay: const Duration(milliseconds: 150),
          child: EnterTile(
            icon: Icons.swap_horiz_rounded,
            title: S.transferTroops,
            gradient: AppTheme.primaryGradient,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TransferScreen(client: widget.client)),
            ),
          ),
        ),
        FadeSlideIn(
          delay: const Duration(milliseconds: 200),
          child: EnterTile(
            icon: Icons.military_tech_rounded,
            title: S.trainTroops,
            gradient: AppTheme.secondaryGradient,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TrainingScreen(client: widget.client)),
            ),
          ),
        ),
        FadeSlideIn(
          delay: const Duration(milliseconds: 250),
          child: EnterTile(
            icon: Icons.local_shipping_rounded,
            title: S.smuggleTroops,
            gradient: AppTheme.cosmosGradient,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SmuggleScreen(client: widget.client)),
            ),
          ),
        ),
        FadeSlideIn(
          delay: const Duration(milliseconds: 300),
          child: EnterTile(
            icon: Icons.people_alt_rounded,
            title: S.commanders,
            gradient: AppTheme.orangeGradient,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CommandersScreen(client: widget.client)),
            ),
          ),
        ),
        FadeSlideIn(
          delay: const Duration(milliseconds: 350),
          child: EnterTile(
            icon: Icons.analytics_rounded,
            title: S.statsTitle,
            gradient: AppTheme.successGradient,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StatsScreen(client: widget.client)),
            ),
          ),
        ),
        FadeSlideIn(
          delay: const Duration(milliseconds: 400),
          child: EnterTile(
            icon: Icons.notifications_active_rounded,
            title: S.notificationsTitle,
            gradient: AppTheme.dangerGradient,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => NotificationsScreen(client: widget.client)),
            ),
          ),
        ),
        FadeSlideIn(
          delay: const Duration(milliseconds: 450),
          child: EnterTile(
            icon: Icons.shield_moon_rounded,
            title: 'دفاع تلقائي',
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF00838F), Color(0xFF26A69A)],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AutoDefenseScreen(client: widget.client)),
            ),
          ),
        ),
        FadeSlideIn(
          delay: const Duration(milliseconds: 500),
          child: EnterTile(
            icon: Icons.gps_fixed_rounded,
            title: 'هجوم NPC',
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFB71C1C), Color(0xFFE53935)],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AttackScreen(client: widget.client)),
            ),
          ),
        ),
        FadeSlideIn(
          delay: const Duration(milliseconds: 550),
          child: EnterTile(
            icon: Icons.landscape_rounded,
            title: 'برج الصحراء',
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE8A317), Color(0xFF8B5A2B)],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => DesertAttackScreen(client: widget.client)),
            ),
          ),
        ),
        // ✅ معسكرات الساموراي (جديد)
        FadeSlideIn(
          delay: const Duration(milliseconds: 600),
          child: EnterTile(
            icon: Icons.shield_rounded,
            title: 'معسكرات الساموراي',
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFDC2626), Color(0xFF7F1D1D)],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SamuraiScreen(client: widget.client)),
            ),
          ),
        ),
        // ✅ المخزن / البيع
        FadeSlideIn(
          delay: const Duration(milliseconds: 650),
          child: EnterTile(
            icon: Icons.inventory_2_rounded,
            title: 'المخزن / البيع',
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7B1FA2), Color(0xFFBA68C8)],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => InventoryScreen(client: widget.client)),
            ),
          ),
        ),
        // ✅ Logs
        FadeSlideIn(
          delay: const Duration(milliseconds: 700),
          child: EnterTile(
            icon: Icons.terminal_rounded,
            title: 'Logs',
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF37474F), Color(0xFF546E7A)],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LogsScreen()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer(BuildContext context) {
    return Center(
      child: Text(
        'SmokJ',
        style: TextStyle(
          color: AppTheme.subTextColor(context).withOpacity(0.5),
          fontSize: 11,
          letterSpacing: 4,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text(S.logout,
            style: const TextStyle(decoration: TextDecoration.none)),
        content: Text(S.logoutConfirm,
            style: const TextStyle(decoration: TextDecoration.none)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            child: Text(S.logout,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    await _performLogout();
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}