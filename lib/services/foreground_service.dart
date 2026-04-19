import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:audioplayers/audioplayers.dart';

class ForegroundService {
  static bool _initialized = false;
  static AudioPlayer? _silentPlayer;
  static Timer? _iosHeartbeatTimer;
  static bool _iosAudioReady = false;

  /// 主 isolate 注册的回调，前台服务 handler 发送心跳时触发
  static Function()? onKeepAliveTick;

  static Future<void> init() async {
    if (kIsWeb) return;
    if (_initialized) return;
    _initialized = true;

    if (Platform.isAndroid) {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'im_foreground',
          channelName: 'Background Service',
          channelDescription: 'Keep message connection alive',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(15000),
          autoRunOnBoot: true,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: true,
          allowAutoRestart: true,
          stopWithTask: false,
        ),
      );
    } else if (Platform.isIOS) {
      // iOS: 预热音频播放器，这样进入后台时只需 resume，不需要重新创建
      await _prepareIOSSilentPlayer();
    }
  }

  static Future<void> start() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      // 监听前台服务 handler 发来的心跳信号
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);

      try {
        if (await FlutterForegroundTask.isRunningService) return;
        await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: 'IM',
          notificationText: 'Keeping connection alive',
          callback: _startCallback,
        );
        debugPrint('[ForegroundService] Android service started');
      } catch (e) {
        debugPrint('[ForegroundService] Android start error: $e');
      }
      // Android: 立即触发一次心跳，不等15秒（socket 断连后尽快轮询新消息）
      Future.delayed(const Duration(seconds: 3), () {
        onKeepAliveTick?.call();
      });
    } else if (Platform.isIOS) {
      // iOS: 恢复预热好的静音播放器（极快，不需要重新创建）
      await _resumeIOSSilentPlayer();
      // 启动心跳定时器
      _iosHeartbeatTimer?.cancel();
      _iosHeartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        onKeepAliveTick?.call();
      });
      // 立即触发一次心跳，不等15秒
      Future.delayed(const Duration(seconds: 2), () {
        onKeepAliveTick?.call();
      });
      debugPrint('[ForegroundService] iOS background keep-alive started');
    }
  }

  static void _onTaskData(dynamic data) {
    // 前台服务 handler 每 15 秒发送一次心跳，唤醒主 isolate
    if (data == 'keepalive') {
      onKeepAliveTick?.call();
    }
  }

  static Future<void> stop() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData);

      try {
        if (!await FlutterForegroundTask.isRunningService) return;
        await FlutterForegroundTask.stopService();
      } catch (e) {
        debugPrint('[ForegroundService] Android stop error: $e');
      }
    } else if (Platform.isIOS) {
      _iosHeartbeatTimer?.cancel();
      _iosHeartbeatTimer = null;
      // 不销毁播放器，只暂停，这样下次 start 可以极快恢复
      await _pauseIOSSilentPlayer();
      debugPrint('[ForegroundService] iOS background keep-alive stopped');
    }
  }

  static Future<void> requestBatteryOptimization() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final isIgnoring =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!isIgnoring) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (e) {
      debugPrint('[ForegroundService] battery opt error: $e');
    }
  }

  /// iOS: 预热静音播放器 — 在 init() 时调用，设置好音频会话和播放器
  static Future<void> _prepareIOSSilentPlayer() async {
    if (_silentPlayer != null) return;
    try {
      final player = AudioPlayer();
      // 设置 playback + mixWithOthers 音频会话，这是后台播放的关键
      await player.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      ));
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(0.05);
      // 用真实的 asset 文件（而不是内存生成的 bytes），iOS 更可靠
      await player.setSource(AssetSource('audio/silence.wav'));
      _silentPlayer = player;
      _iosAudioReady = true;
      debugPrint('[ForegroundService] iOS silent player prepared');
    } catch (e) {
      debugPrint('[ForegroundService] iOS prepare player error: $e');
    }
  }

  /// iOS: 恢复播放（进入后台时调用）— 极快，因为播放器已经预热好了
  static Future<void> _resumeIOSSilentPlayer() async {
    try {
      if (_silentPlayer == null || !_iosAudioReady) {
        await _prepareIOSSilentPlayer();
      }
      await _silentPlayer?.resume();
      debugPrint('[ForegroundService] iOS silent audio resumed');
    } catch (e) {
      debugPrint('[ForegroundService] iOS resume error: $e');
      // 如果恢复失败，重新创建
      _silentPlayer = null;
      _iosAudioReady = false;
      await _prepareIOSSilentPlayer();
      try { await _silentPlayer?.resume(); } catch (_) {}
    }
  }

  /// iOS: 暂停播放（回到前台时调用）— 不销毁播放器
  static Future<void> _pauseIOSSilentPlayer() async {
    try {
      await _silentPlayer?.pause();
    } catch (_) {}
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
    // 每 15 秒向主 isolate 发送心跳信号，唤醒 Dart 引擎
    FlutterForegroundTask.sendDataToMain('keepalive');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ForegroundTask] destroyed');
  }
}