import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:audioplayers/audioplayers.dart';

/// 后台保活服务
/// - Android: 前台 Service（真正的 ForegroundService）
/// - iOS: 静音音频循环播放（利用 audio background mode 阻止进程挂起）
class ForegroundService {
  static bool _initialized = false;

  // ── iOS 静音音频 ──
  static AudioPlayer? _silentPlayer;
  static BytesSource? _silentSource;

  /// 初始化（在 main() 中调用一次）
  static Future<void> init() async {
    if (kIsWeb) return;
    if (_initialized) return;
    _initialized = true;

    if (Platform.isAndroid) {
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
  }

  /// 启动保活（App 进入后台时调用）
  static Future<void> start() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: '内部通',
        notificationText: '正在后台保持连接',
        callback: _startCallback,
      );
    } else if (Platform.isIOS) {
      await _startSilentAudio();
    }
  }

  /// 停止保活（App 回到前台时调用）
  static Future<void> stop() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.stopService();
    } else if (Platform.isIOS) {
      await _stopSilentAudio();
    }
  }

  /// 请求忽略电池优化（仅 Android）
  static Future<void> requestBatteryOptimization() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final isIgnoring =
        await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!isIgnoring) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  // ── iOS 静音音频保活 ──

  static Future<void> _startSilentAudio() async {
    if (_silentPlayer != null) return;
    try {
      final player = AudioPlayer();
      // 设置 iOS 音频上下文：允许后台播放，与其他音频混合
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

  /// 生成 1 秒静音 WAV（16-bit mono 8kHz）
  static Uint8List _generateSilentWav() {
    const sampleRate = 8000;
    const duration = 1; // 秒
    const numSamples = sampleRate * duration;
    const dataSize = numSamples * 2; // 16-bit = 2 bytes per sample
    const fileSize = 44 + dataSize; // WAV header + data

    final buf = ByteData(fileSize);
    int o = 0;
    // RIFF header
    buf.setUint8(o++, 0x52); buf.setUint8(o++, 0x49);
    buf.setUint8(o++, 0x46); buf.setUint8(o++, 0x46);
    buf.setUint32(o, fileSize - 8, Endian.little); o += 4;
    buf.setUint8(o++, 0x57); buf.setUint8(o++, 0x41);
    buf.setUint8(o++, 0x56); buf.setUint8(o++, 0x45);
    // fmt chunk
    buf.setUint8(o++, 0x66); buf.setUint8(o++, 0x6D);
    buf.setUint8(o++, 0x74); buf.setUint8(o++, 0x20);
    buf.setUint32(o, 16, Endian.little); o += 4;
    buf.setUint16(o, 1, Endian.little); o += 2; // PCM
    buf.setUint16(o, 1, Endian.little); o += 2; // mono
    buf.setUint32(o, sampleRate, Endian.little); o += 4;
    buf.setUint32(o, sampleRate * 2, Endian.little); o += 4; // byte rate
    buf.setUint16(o, 2, Endian.little); o += 2; // block align
    buf.setUint16(o, 16, Endian.little); o += 2; // bits per sample
    // data chunk
    buf.setUint8(o++, 0x64); buf.setUint8(o++, 0x61);
    buf.setUint8(o++, 0x74); buf.setUint8(o++, 0x61);
    buf.setUint32(o, dataSize, Endian.little); o += 4;
    // 16000 bytes of silence (all zeros) — already zeroed by ByteData

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
    // 周期性事件，保持进程活跃即可
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ForegroundTask] destroyed');
  }
}
