import 'dart:typed_data';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'notification_sound_stub.dart'
    if (dart.library.html) 'notification_sound_web.dart' as platform;

class NotificationSound {
  static AudioPlayer? _player;
  static AudioPlayer? _ringtonePlayer;
  static BytesSource? _cachedSource;
  static BytesSource? _cachedRingtone;
  static bool _contextSet = false;

  /// 配置音频播放器使用通知音频流（确保即使媒体音量为0也能发声）
  static Future<void> _ensureAudioContext(AudioPlayer player) async {
    if (kIsWeb || _contextSet) return;
    try {
      if (Platform.isAndroid) {
        await player.setAudioContext(AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ));
      }
      _contextSet = true;
    } catch (_) {}
  }

  static void play() {
    if (kIsWeb) {
      platform.playNotificationSound();
    } else {
      HapticFeedback.mediumImpact();
      _playNativeSound();
    }
  }

  /// Play a looping ringtone for incoming calls
  static Future<void> playRingtone() async {
    if (kIsWeb) {
      // Web: use repeated ding-dong
      platform.playNotificationSound();
      return;
    }
    try {
      _ringtonePlayer ??= AudioPlayer();
      _cachedRingtone ??= BytesSource(_generateRingtoneWav());
      await _ringtonePlayer!.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer!.play(_cachedRingtone!);
    } catch (_) {}
  }

  /// Stop the ringtone
  static Future<void> stopRingtone() async {
    try {
      await _ringtonePlayer?.stop();
    } catch (_) {}
  }

  static Future<void> _playNativeSound() async {
    try {
      _player ??= AudioPlayer();
      await _ensureAudioContext(_player!);
      _cachedSource ??= BytesSource(_generateNotificationWav());
      await _player!.stop();
      await _player!.setVolume(1.0);
      await _player!.play(_cachedSource!);
    } catch (_) {}
  }

  /// Generate a short "ding-dong" WAV tone (44100Hz, 16-bit mono, ~0.5s)
  static Uint8List _generateNotificationWav() {
    const sampleRate = 44100;
    const duration1 = 0.20; // "ding" duration
    const duration2 = 0.30; // "dong" duration
    const freq1 = 880.0;   // "ding" frequency (A5)
    const freq2 = 587.0;   // "dong" frequency (D5)
    const volume = 0.8;    // 高音量确保可听

    final totalSamples = ((duration1 + duration2) * sampleRate).toInt();
    final samples = Int16List(totalSamples);
    final samplesD1 = (duration1 * sampleRate).toInt();

    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      double sample;
      if (i < samplesD1) {
        final env = volume * exp(-t * 8); // 减缓衰减
        sample = env * sin(2 * pi * freq1 * t);
      } else {
        final t2 = (i - samplesD1) / sampleRate;
        final env = volume * exp(-t2 * 6); // 减缓衰减
        sample = env * sin(2 * pi * freq2 * t2);
      }
      samples[i] = (sample * 32767).clamp(-32768, 32767).toInt();
    }

    return _buildWav(samples);
  }

  /// Generate a repeating ringtone (~2s pattern: ring-ring-pause)
  static Uint8List _generateRingtoneWav() {
    const sampleRate = 44100;
    const volume = 0.25;
    // Classic phone ring: two tones alternating
    const freq1 = 440.0; // A4
    const freq2 = 480.0; // slightly above A4 (telephone standard)

    // Pattern: 0.4s ring, 0.2s silence, 0.4s ring, 1.0s silence = 2.0s total
    const totalDuration = 2.0;
    final totalSamples = (totalDuration * sampleRate).toInt();
    final samples = Int16List(totalSamples);

    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      double sample = 0;
      // Ring segments: 0-0.4s and 0.6-1.0s
      if (t < 0.4 || (t >= 0.6 && t < 1.0)) {
        final env = volume * (1 - (t % 0.4) / 0.5).clamp(0.6, 1.0);
        sample = env * (sin(2 * pi * freq1 * t) + sin(2 * pi * freq2 * t)) / 2;
      }
      samples[i] = (sample * 32767).clamp(-32768, 32767).toInt();
    }

    return _buildWav(samples);
  }

  static Uint8List _buildWav(Int16List samples) {
    final dataSize = samples.length * 2;
    final fileSize = 36 + dataSize;
    final wav = ByteData(44 + dataSize);
    const sampleRate = 44100;

    // RIFF header
    wav.setUint8(0, 0x52); wav.setUint8(1, 0x49); wav.setUint8(2, 0x46); wav.setUint8(3, 0x46);
    wav.setUint32(4, fileSize, Endian.little);
    wav.setUint8(8, 0x57); wav.setUint8(9, 0x41); wav.setUint8(10, 0x56); wav.setUint8(11, 0x45);

    // fmt chunk
    wav.setUint8(12, 0x66); wav.setUint8(13, 0x6D); wav.setUint8(14, 0x74); wav.setUint8(15, 0x20);
    wav.setUint32(16, 16, Endian.little);
    wav.setUint16(20, 1, Endian.little);
    wav.setUint16(22, 1, Endian.little);
    wav.setUint32(24, sampleRate, Endian.little);
    wav.setUint32(28, sampleRate * 2, Endian.little);
    wav.setUint16(32, 2, Endian.little);
    wav.setUint16(34, 16, Endian.little);

    // data chunk
    wav.setUint8(36, 0x64); wav.setUint8(37, 0x61); wav.setUint8(38, 0x74); wav.setUint8(39, 0x61);
    wav.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      wav.setInt16(44 + i * 2, samples[i], Endian.little);
    }

    return wav.buffer.asUint8List();
  }
}
