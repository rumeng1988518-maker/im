import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ForegroundService {
  static bool _initialized = false;
  static AudioPlayer? _silentPlayer;
  static BytesSource? _silentSource;

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
    }
  }

  static Future<void> start() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      // 启用 WakeLock 防止 CPU 休眠，确保 socket 心跳和 Dart Timer 继续运行
      try { await WakelockPlus.enable(); } catch (_) {}

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
    } else if (Platform.isIOS) {
      await _startSilentAudio();
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
      // 回到前台，释放 WakeLock
      try { await WakelockPlus.disable(); } catch (_) {}
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData);

      try {
        if (!await FlutterForegroundTask.isRunningService) return;
        await FlutterForegroundTask.stopService();
      } catch (e) {
        debugPrint('[ForegroundService] Android stop error: $e');
      }
    } else if (Platform.isIOS) {
      await _stopSilentAudio();
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

  static Future<void> _startSilentAudio() async {
    if (_silentPlayer != null) return;
    try {
      final player = AudioPlayer();
      await player.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      ));
      _silentSource ??= BytesSource(_generateSilentWav());
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(0.01);
      await player.play(_silentSource!);
      _silentPlayer = player;
      debugPrint('[ForegroundService] iOS silent audio started');
    } catch (e) {
      debugPrint('[ForegroundService] iOS silent audio error: $e');
    }
  }

  static Future<void> _stopSilentAudio() async {
    try {
      await _silentPlayer?.stop();
      await _silentPlayer?.dispose();
    } catch (_) {}
    _silentPlayer = null;
    debugPrint('[ForegroundService] iOS silent audio stopped');
  }

  static Uint8List _generateSilentWav() {
    const sampleRate = 8000;
    const duration = 1;
    const numSamples = sampleRate * duration;
    const dataSize = numSamples * 2;
    const fileSize = 44 + dataSize;

    final buf = ByteData(fileSize);
    int o = 0;
    buf.setUint8(o++, 0x52); buf.setUint8(o++, 0x49);
    buf.setUint8(o++, 0x46); buf.setUint8(o++, 0x46);
    buf.setUint32(o, fileSize - 8, Endian.little); o += 4;
    buf.setUint8(o++, 0x57); buf.setUint8(o++, 0x41);
    buf.setUint8(o++, 0x56); buf.setUint8(o++, 0x45);
    buf.setUint8(o++, 0x66); buf.setUint8(o++, 0x6D);
    buf.setUint8(o++, 0x74); buf.setUint8(o++, 0x20);
    buf.setUint32(o, 16, Endian.little); o += 4;
    buf.setUint16(o, 1, Endian.little); o += 2;
    buf.setUint16(o, 1, Endian.little); o += 2;
    buf.setUint32(o, sampleRate, Endian.little); o += 4;
    buf.setUint32(o, sampleRate * 2, Endian.little); o += 4;
    buf.setUint16(o, 2, Endian.little); o += 2;
    buf.setUint16(o, 16, Endian.little); o += 2;
    buf.setUint8(o++, 0x64); buf.setUint8(o++, 0x61);
    buf.setUint8(o++, 0x74); buf.setUint8(o++, 0x61);
    buf.setUint32(o, dataSize, Endian.little); o += 4;

    return buf.buffer.asUint8List();
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