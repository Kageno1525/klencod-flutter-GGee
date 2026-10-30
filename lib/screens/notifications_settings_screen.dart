import 'package:flutter/material.dart';
import 'package:gge/gge_client.dart';
import 'package:gge/l10n/strings.dart';
import 'package:gge/services/notifications_service.dart';
import 'package:gge/services/background_service.dart';
import 'package:gge/services/settings_guide_service.dart';
import 'package:gge/theme.dart';
import 'package:gge/widgets/animated_widgets.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  final GgeClient client;
  const NotificationsSettingsScreen({super.key, required this.client});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> with WidgetsBindingObserver {
  bool _batteryOptimized = true;
  bool _oemRestricted = false;
  bool _permissionGranted = false;
  bool _bgRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final bat = await SettingsGuideService.isBatteryOptimized();
    final oem = await SettingsGuideService.isOemRestricted();
    final notif = await NotificationsService.checkPermission();
    final bg = BackgroundService.isRunning;
    if (!mounted) return;
    setState(() {
      _batteryOptimized = bat;
      _oemRestricted = oem;
      _permissionGranted = notif;
      _bgRunning = bg;
    });
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
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    color: AppTheme.purple,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        _setupGuideCard(context),
                        const SizedBox(height: 14),
                        _togglesCard(context),
                        const SizedBox(height: 14),
                        _serviceCard(context),
                      ],
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
            child: Text(
              S.isAr ? 'إعدادات الإشعارات' : 'Notification Settings',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textColor(context),
                letterSpacing: -0.3,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _setupGuideCard(BuildContext context) {
    final notifDone = _permissionGranted;
    final batteryDone = !_batteryOptimized;
    final allDone = notifDone && batteryDone;

    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: allDone
                      ? AppTheme.successGradient
                      : AppTheme.orangeGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  allDone
                      ? Icons.check_circle_rounded
                      : Icons.assignment_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allDone
                          ? (S.isAr ? 'الإعدادات جاهزة ✓' : 'All set ✓')
                          : (S.isAr ? 'إعدادات مطلوبة' : 'Setup required'),
                      style: TextStyle(
                        color: AppTheme.textColor(context),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    Text(
                      allDone
                          ? (S.isAr
                              ? 'كل حاجة متظبطة، الإشعارات شغالة'
                              : 'Everything is configured')
                          : (S.isAr
                              ? 'اتبع الخطوات دي مرة واحدة'
                              : 'Follow these steps once'),
                      style: TextStyle(
                        color: AppTheme.subTextColor(context),
                        fontSize: 11,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _setupItem(
            context: context,
            icon: Icons.notifications_active_rounded,
            title: S.isAr ? 'صلاحية الإشعارات' : 'Notification permission',
            subtitle: notifDone
                ? (S.isAr ? 'مفعّلة ✓' : 'Enabled ✓')
                : (S.isAr ? 'مطلوبة عشان توصلك التنبيهات' : 'Required'),
            done: notifDone,
            actionLabel:
                notifDone ? (S.isAr ? 'تعديل' : 'Edit') : (S.isAr ? 'فتح' : 'Open'),
            actionColor: notifDone ? AppTheme.blue : AppTheme.red,
            onTap: () async {
              await SettingsGuideService.openNotificationSettings();
              await Future.delayed(const Duration(seconds: 1));
              await _refresh();
            },
          ),
          _divider(context),
          _setupItem(
            context: context,
            icon: Icons.battery_saver_rounded,
            title: S.isAr ? 'إيقاف تحسين البطارية' : 'Battery optimization',
            subtitle: batteryDone
                ? (S.isAr ? 'متوقف ✓' : 'Disabled ✓')
                : (S.isAr
                    ? 'مطلوب عشان التطبيق يشتغل في الخلفية'
                    : 'Required for background'),
            done: batteryDone,
            actionLabel:
                batteryDone ? (S.isAr ? 'تعديل' : 'Edit') : (S.isAr ? 'فتح' : 'Open'),
            actionColor: batteryDone ? AppTheme.blue : AppTheme.orange,
            onTap: () async {
              await SettingsGuideService.openBatteryOptimization();
              await Future.delayed(const Duration(seconds: 2));
              await _refresh();
            },
          ),
          if (_oemRestricted) ...[
            _divider(context),
            _setupItem(
              context: context,
              icon: Icons.rocket_launch_rounded,
              title: S.isAr ? 'Autostart' : 'Autostart',
              subtitle:
                  S.isAr ? 'جهازك محتاج تفعيلها يدوياً' : 'Device requires manual setup',
              done: null,
              actionLabel: S.isAr ? 'فتح' : 'Open',
              actionColor: AppTheme.purple,
              onTap: () async {
                await SettingsGuideService.openAutostart();
              },
            ),
          ],
          _divider(context),
          _setupItem(
            context: context,
            icon: Icons.lock_rounded,
            title:
                S.isAr ? 'قفل في Recent Apps' : 'Lock in Recent Apps',
            subtitle: S.isAr
                ? 'اسحب لأسفل واضغط 🔒'
                : 'Swipe down and tap 🔒',
            done: null,
            actionLabel: S.isAr ? 'شرح' : 'Info',
            actionColor: AppTheme.teal,
            onTap: () => _showLockGuide(context),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Divider(
        height: 1,
        color: AppTheme.subTextColor(context).withOpacity(0.08),
      );

  Widget _setupItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool? done,
    required String actionLabel,
    required Color actionColor,
    required VoidCallback onTap,
  }) {
    final Color iconColor;
    final IconData statusIcon;

    if (done == true) {
      iconColor = AppTheme.green;
      statusIcon = Icons.check_circle_rounded;
    } else if (done == false) {
      iconColor = AppTheme.red;
      statusIcon = Icons.cancel_rounded;
    } else {
      iconColor = AppTheme.orange;
      statusIcon = Icons.info_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: AppTheme.textColor(context),
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          decoration: TextDecoration.none,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(statusIcon, color: iconColor, size: 14),
                  ],
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppTheme.subTextColor(context),
                    fontSize: 10.5,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: actionColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: actionColor.withOpacity(0.4)),
              ),
              child: Text(
                actionLabel,
                style: TextStyle(
                  color: actionColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLockGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.lock_rounded, color: AppTheme.teal),
            const SizedBox(width: 8),
            Text(S.isAr ? 'قفل التطبيق' : 'Lock App',
                style: const TextStyle(decoration: TextDecoration.none)),
          ],
        ),
        content: Text(
          S.isAr
              ? '1. اضغط زر الـ Home عشان تطلع من التطبيق\n'
                  '2. افتح شاشة الـ Recent Apps\n'
                  '3. اسحب التطبيق لأسفل → هتلاقي أيقونة 🔒\n'
                  '4. اضغطها عشان التطبيق يفضل شغال\n\n'
                  'ده بيمنع النظام من إغلاقه تلقائي.'
              : '1. Press Home to exit the app\n'
                  '2. Open Recent Apps screen\n'
                  '3. Swipe down → find 🔒 icon\n'
                  '4. Tap it to keep the app running\n\n'
                  'This prevents the system from killing it.',
          style: const TextStyle(decoration: TextDecoration.none, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.isAr ? 'فهمت' : 'Got it'),
          ),
        ],
      ),
    );
  }

  Widget _togglesCard(BuildContext context) {
    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          _toggleRow(
            icon: Icons.notifications_active_rounded,
            title: S.notificationsEnabled,
            subtitle: S.notificationsEnabledDesc,
            value: NotificationsService.enabled,
            onChanged: (v) async {
              await NotificationsService.setEnabled(v);
              if (mounted) setState(() {});
            },
          ),
          _divider(context),
          _toggleRow(
            icon: Icons.volume_up_rounded,
            title: S.soundAlert,
            subtitle: S.soundAlertDesc,
            value: NotificationsService.soundEnabled,
            onChanged: (v) async {
              await NotificationsService.setSound(v);
              if (mounted) setState(() {});
            },
          ),
          _divider(context),
          _toggleRow(
            icon: Icons.groups_rounded,
            title: S.allianceAttacks,
            subtitle: S.allianceAttacksDesc,
            value: NotificationsService.allianceAttacksEnabled,
            onChanged: (v) async {
              await NotificationsService.setAllianceAttacksEnabled(v);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Future<void> Function(bool) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.purple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.purple, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                      color: AppTheme.textColor(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      decoration: TextDecoration.none),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                      color: AppTheme.subTextColor(context),
                      fontSize: 10.5,
                      decoration: TextDecoration.none),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) => onChanged(v),
            activeColor: AppTheme.purple,
          ),
        ],
      ),
    );
  }

  Widget _serviceCard(BuildContext context) {
    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: _bgRunning
                  ? AppTheme.successGradient
                  : const LinearGradient(colors: [Colors.grey, Colors.grey]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _bgRunning ? Icons.shield_moon_rounded : Icons.shield_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _bgRunning
                      ? (S.isAr ? 'الحماية شغالة' : 'Protection ON')
                      : (S.isAr ? 'الحماية متوقفة' : 'Protection OFF'),
                  style: TextStyle(
                    color: AppTheme.textColor(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                ),
                Text(
                  _bgRunning
                      ? (S.isAr
                          ? 'التطبيق شغال في الخلفية'
                          : 'App runs in background')
                      : (S.isAr
                          ? 'شغّلها عشان الإشعارات تشتغل في الخلفية'
                          : 'Enable for background notifications'),
                  style: TextStyle(
                    color: AppTheme.subTextColor(context),
                    fontSize: 11,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _bgRunning,
            onChanged: (v) async {
              if (v) {
                await BackgroundService.start();
              } else {
                await BackgroundService.stop();
              }
              if (mounted) setState(() => _bgRunning = v);
            },
            activeColor: AppTheme.green,
          ),
        ],
      ),
    );
  }
}