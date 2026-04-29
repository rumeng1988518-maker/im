import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 通话前权限检测与申请工具类
///
/// 在发起或接听语音/视频通话前调用 [requestCallPermissions]，
/// 返回 true 表示所有必要权限已就绪，可以继续通话。
class CallPermissionHelper {
  CallPermissionHelper._();

  /// 检测并申请通话所需权限。
  ///
  /// [callType] 为 `'voice'` 时仅申请麦克风；
  /// 为 `'video'` 时同时申请麦克风与摄像头。
  ///
  /// 返回 `true` 表示权限已全部获取，可以继续通话；
  /// 返回 `false` 表示权限不足，调用方应中止通话流程。
  static Future<bool> requestCallPermissions(
    BuildContext context,
    String callType,
  ) async {
    // Web 端不需要原生权限检测
    if (kIsWeb) return true;

    final isVideo = callType == 'video';
    final required = <Permission>[Permission.microphone];
    if (isVideo) required.add(Permission.camera);

    // ── Step 1：检查当前状态 ──
    final statuses = {
      for (final p in required) p: await p.status,
    };

    if (statuses.values.every((s) => s.isGranted)) return true;

    // ── Step 2：已被永久拒绝，引导去设置 ──
    final permanentlyDenied =
        statuses.entries.where((e) => e.value.isPermanentlyDenied).map((e) => e.key).toList();
    if (permanentlyDenied.isNotEmpty) {
      if (!context.mounted) return false;
      await _showSettingsDialog(context, isVideo, permanentlyDenied);
      return false;
    }

    // ── Step 3：展示权限用途说明，征得用户同意后再申请 ──
    if (!context.mounted) return false;
    final confirmed = await _showRationaleDialog(context, isVideo);
    if (!confirmed) return false;

    // ── Step 4：正式申请权限 ──
    final results = await required.request();
    final allGranted = results.values.every((s) => s.isGranted);
    if (allGranted) return true;

    if (!context.mounted) return false;

    // ── Step 5：申请后仍被拒绝 ──
    final nowPermanentlyDenied =
        results.entries.where((e) => e.value.isPermanentlyDenied).map((e) => e.key).toList();
    if (nowPermanentlyDenied.isNotEmpty) {
      await _showSettingsDialog(context, isVideo, nowPermanentlyDenied);
    } else {
      await _showDeniedDialog(context, isVideo, results);
    }
    return false;
  }

  // ── 权限用途说明对话框（申请前展示） ──
  static Future<bool> _showRationaleDialog(BuildContext context, bool isVideo) async {
    final title = isVideo ? '需要麦克风和摄像头权限' : '需要麦克风权限';
    final content = isVideo
        ? '视频通话需要使用麦克风采集您的声音、使用摄像头拍摄您的画面，才能与对方进行实时视频通话。\n\n请在接下来的弹窗中点击「允许」以开启相关权限。'
        : '语音通话需要使用麦克风采集您的声音，才能与对方进行实时语音通话。\n\n请在接下来的弹窗中点击「允许」以开启麦克风权限。';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isVideo ? Icons.videocam_outlined : Icons.mic_outlined,
              color: const Color(0xFF0066FF),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: Text(content, style: const TextStyle(fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('去授权', style: TextStyle(color: Color(0xFF0066FF))),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ── 用户拒绝后（可再次申请）的提示对话框 ──
  static Future<void> _showDeniedDialog(
    BuildContext context,
    bool isVideo,
    Map<Permission, PermissionStatus> results,
  ) async {
    final deniedNames = <String>[];
    if (results[Permission.microphone]?.isDenied == true) deniedNames.add('麦克风');
    if (results[Permission.camera]?.isDenied == true) deniedNames.add('摄像头');

    final permLabel = deniedNames.join('和');
    final callLabel = isVideo ? '视频通话' : '语音通话';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.mic_off_outlined, color: Colors.orange),
            const SizedBox(width: 8),
            Text('未开启$permLabel权限', style: const TextStyle(fontSize: 16)),
          ],
        ),
        content: Text(
          '您拒绝了$permLabel权限，将无法使用$callLabel功能。\n\n如需使用，请重新开启$permLabel权限。',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('暂不开启', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openAppSettings();
            },
            child: const Text('去设置', style: TextStyle(color: Color(0xFF0066FF))),
          ),
        ],
      ),
    );
  }

  // ── 已永久拒绝时引导去系统设置 ──
  static Future<void> _showSettingsDialog(
    BuildContext context,
    bool isVideo,
    List<Permission> permissions,
  ) async {
    final names = <String>[];
    if (permissions.contains(Permission.microphone)) names.add('麦克风');
    if (permissions.contains(Permission.camera)) names.add('摄像头');

    final permLabel = names.join('和');
    final callLabel = isVideo ? '视频通话' : '语音通话';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.block_outlined, color: Colors.red),
            const SizedBox(width: 8),
            Text('$permLabel权限已被禁用', style: const TextStyle(fontSize: 16)),
          ],
        ),
        content: Text(
          '$permLabel权限已被禁用，无法使用$callLabel功能。\n\n请前往手机「设置 → 应用 → 权限」中手动开启$permLabel权限。',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openAppSettings();
            },
            child: const Text('去设置', style: TextStyle(color: Color(0xFF0066FF))),
          ),
        ],
      ),
    );
  }
}
