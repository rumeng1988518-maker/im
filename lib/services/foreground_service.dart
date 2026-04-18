import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Android 前台服务：保持应用进程在后台不被系统杀死
class ForegroundService {
  static bool _initialized = false;

  /// 初始化前台任务配置（在 main() 中调用一次）
  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'im_foreground',
        channelName: '后台运行',
        channelDescription: '保持消息连接',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// 启动前台服务（App 进入后台时调用）
  static Future<void> start() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: '内部通',
      notificationText: '正在后台保持连接',
      callback: _startCallback,
    );
  }

  /// 停止前台服务（App 回到前台时调用）
  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }

  /// 请求忽略电池优化（首次登录后调用）
  static Future<void> requestBatteryOptimization() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final isIgnoring =
        await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!isIgnoring) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ForegroundTask] started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 周期性事件，保持进程活跃即可
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ForegroundTask] destroyed');
  }
}
