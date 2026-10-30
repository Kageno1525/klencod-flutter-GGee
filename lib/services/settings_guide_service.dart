import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class SettingsGuideService {
  SettingsGuideService._();

  static const String _pkg = 'com.kageno.gge';

  // ═══ Battery Optimization ═══
  static Future<bool> isBatteryOptimized() async {
    try {
      final ignoring =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      return !ignoring;
    } catch (_) {
      return true;
    }
  }

  static Future<void> openBatteryOptimization() async {
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (e) {
      debugPrint('[SettingsGuide] battery open failed: $e');
      await _openAppSettings();
    }
  }

  // ═══ Notification Settings ═══
  static Future<void> openNotificationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      final intent = AndroidIntent(
        action: 'android.settings.APP_NOTIFICATION_SETTINGS',
        arguments: {
          'android.provider.extra.APP_PACKAGE': _pkg,
        },
      );
      await intent.launch();
    } catch (e) {
      debugPrint('[SettingsGuide] notif open failed: $e');
      await _openAppSettings();
    }
  }

  // ═══ App Settings ═══
  static Future<void> _openAppSettings() async {
    if (!Platform.isAndroid) return;
    try {
      final intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$_pkg',
      );
      await intent.launch();
    } catch (e) {
      debugPrint('[SettingsGuide] app settings failed: $e');
    }
  }

  // ═══ Autostart (OEM-specific) ═══
  static Future<void> openAutostart() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final brand = info.brand.toLowerCase();
      final manufacturer = info.manufacturer.toLowerCase();

      AndroidIntent? intent;

      if (brand.contains('xiaomi') ||
          manufacturer.contains('xiaomi') ||
          brand.contains('redmi') ||
          brand.contains('poco')) {
        intent = AndroidIntent(
          action: 'miui.intent.action.OP_AUTO_START',
          package: 'com.miui.securitycenter',
          componentName:
              'com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity',
        );
      } else if (brand.contains('oppo') ||
          manufacturer.contains('oppo') ||
          manufacturer.contains('realme') ||
          brand.contains('realme')) {
        intent = AndroidIntent(
          action:
              'com.coloros.safecenter.permission.startup.StartupAppListActivity',
        );
      } else if (brand.contains('vivo') ||
          manufacturer.contains('vivo') ||
          brand.contains('iqoo')) {
        intent = AndroidIntent(
          action:
              'com.vivo.permissionmanager.activity.BgStartUpManagerActivity',
        );
      } else if (brand.contains('huawei') ||
          manufacturer.contains('huawei') ||
          brand.contains('honor')) {
        intent = AndroidIntent(
          action:
              'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
        );
      } else if (brand.contains('asus') || manufacturer.contains('asus')) {
        intent = AndroidIntent(
          action: 'com.asus.mobilemanager.entry.FunctionActivity',
          package: 'com.asus.mobilemanager',
        );
      } else if (brand.contains('oneplus') ||
          manufacturer.contains('oneplus')) {
        intent = AndroidIntent(
          action:
              'com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity',
        );
      }

      if (intent != null) {
        await intent.launch();
      } else {
        await _openAppSettings();
      }
    } catch (e) {
      debugPrint('[SettingsGuide] autostart failed: $e');
      await _openAppSettings();
    }
  }

  // ═══ Device info ═══
  static Future<String> getDeviceName() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return '${info.manufacturer} ${info.model}'.trim();
    } catch (_) {
      return 'Android';
    }
  }

  static Future<bool> isOemRestricted() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final brand = info.brand.toLowerCase();
      final manufacturer = info.manufacturer.toLowerCase();
      return brand.contains('xiaomi') ||
          manufacturer.contains('xiaomi') ||
          brand.contains('oppo') ||
          manufacturer.contains('oppo') ||
          brand.contains('vivo') ||
          manufacturer.contains('vivo') ||
          brand.contains('huawei') ||
          manufacturer.contains('huawei') ||
          brand.contains('oneplus') ||
          manufacturer.contains('oneplus');
    } catch (_) {
      return false;
    }
  }
}