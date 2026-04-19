import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/services/socket_service.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/pages/landing_page.dart';
import 'package:im_client/services/push_token_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic> _settings = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final api = context.read<ApiClient>();
      final data = await api.get('/users/me/settings');
      if (!mounted) return;
      setState(() {
        _settings = data is Map<String, dynamic> ? data : {};
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    setState(() => _settings[key] = value);
    try {
      final api = context.read<ApiClient>();
      await api.put('/users/me/settings', data: {key: value});
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '更新失败'));
      _loadSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _group([
                  _switchTile(Icons.volume_up, '消息提示音', AppColors.warning,
                      value: _settings['notificationSound'] == true,
                      onChanged: (v) => _updateSetting('notificationSound', v)),
                  _switchTile(Icons.vibration, '消息振动', AppColors.warning,
                      value: _settings['notificationVibrate'] == true,
                      onChanged: (v) => _updateSetting('notificationVibrate', v)),
                  _switchTile(Icons.visibility, '消息预览', AppColors.warning,
                      value: _settings['notificationPreview'] == true,
                      onChanged: (v) => _updateSetting('notificationPreview', v)),
                ]),
                const SizedBox(height: 12),
                _group([
                  _switchTile(Icons.person_add, '加好友需验证', AppColors.primary,
                      value: _settings['addFriendVerify'] == true,
                      onChanged: (v) => _updateSetting('addFriendVerify', v)),
                ]),
                const SizedBox(height: 12),
                _group([
                  _tile(Icons.lock_outline, '修改密码', const Color(0xFF9b59b6), onTap: _showChangePassword),
                ]),
                const SizedBox(height: 12),
                _group([
                  _tile(Icons.info_outline, '关于内部通', const Color(0xFF42A5F5), onTap: () => _showAbout(context)),
                  _tile(Icons.notifications_active, '推送诊断', const Color(0xFF26A69A), onTap: _showPushDiagnostics),
                ]),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    title: const Center(
                      child: Text('退出登录', style: TextStyle(color: AppColors.danger, fontSize: 16)),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: () => _confirmLogout(context),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _group(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1) const Divider(indent: 56, height: 0),
        ],
      ]),
    );
  }

  Widget _tile(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textLight, size: 20),
      onTap: onTap,
    );
  }

  Widget _switchTile(IconData icon, String label, Color color,
      {required bool value, required ValueChanged<bool> onChanged}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColors.primary,
      ),
    );
  }

  Future<void> _showPushDiagnostics() async {
    final api = context.read<ApiClient>();
    String info = '正在获取推送状态...';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // 首次加载
          if (info == '正在获取推送状态...') {
            _fetchPushStatus(api).then((result) {
              if (ctx.mounted) setDialogState(() => info = result);
            });
          }
          return AlertDialog(
            title: const Text('推送诊断'),
            content: SingleChildScrollView(
              child: SelectableText(info, style: const TextStyle(fontSize: 13)),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  setDialogState(() => info = '正在重新获取并上报 Token...');
                  try {
                    final token = await PushTokenService.getToken();
                    if (token == null || token.isEmpty) {
                      setDialogState(() => info = 'Token 获取失败（系统未返回 APNs token）\n\n请检查:\n1. 是否允许了通知权限\n2. 网络是否正常\n3. 证书配置是否正确');
                      return;
                    }
                    final prefs = await SharedPreferences.getInstance();
                    String? deviceId = prefs.getString('im_device_id');
                    if (deviceId == null || deviceId.isEmpty) {
                      deviceId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
                      await prefs.setString('im_device_id', deviceId);
                    }
                    await api.put('/users/me/push-token', data: {
                      'pushToken': token,
                      'deviceId': deviceId,
                      'platform': PushTokenService.platform,
                    });
                    // 重新获取状态
                    final newStatus = await _fetchPushStatus(api);
                    if (ctx.mounted) setDialogState(() => info = '上报成功！Token: ${token.substring(0, 12)}...\n\n$newStatus');
                  } catch (e) {
                    if (ctx.mounted) setDialogState(() => info = '上报失败: $e');
                  }
                },
                child: const Text('重新上报Token'),
              ),
              TextButton(
                onPressed: () async {
                  setDialogState(() => info = '正在发送测试推送...');
                  try {
                    final res = await api.post('/debug/push-test');
                    final results = res['results'] as List? ?? [];
                    if (results.isEmpty) {
                      setDialogState(() => info = '没有可用的推送设备（push_token 为空）\n\n请先点击「重新上报Token」');
                    } else {
                      final buf = StringBuffer('测试推送已发送:\n');
                      for (final r in results) {
                        buf.writeln('  ${r['type']}: ${r['status']} ${r['error'] ?? ''}');
                      }
                      buf.writeln('\n请切到后台等几秒，看是否收到通知');
                      setDialogState(() => info = buf.toString());
                    }
                  } catch (e) {
                    setDialogState(() => info = '发送失败: $e');
                  }
                },
                child: const Text('发送测试推送'),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            ],
          );
        },
      ),
    );
  }

  Future<String> _fetchPushStatus(ApiClient api) async {
    try {
      final localToken = PushTokenService.cachedToken;
      final res = await api.get('/debug/push-status');
      final apns = res['apns'] as Map<String, dynamic>? ?? {};
      final devices = res['devices'] as List? ?? [];
      final buf = StringBuffer();
      buf.writeln('=== 本地状态 ===');
      buf.writeln('平台: ${PushTokenService.platform}');
      buf.writeln('本地Token: ${localToken != null ? '${localToken.substring(0, 12)}...' : '(无)'}');
      buf.writeln('');
      buf.writeln('=== APNs 服务端 ===');
      buf.writeln('启用: ${apns['enabled']}');
      buf.writeln('证书已加载: ${apns['certLoaded']}');
      if (apns['certError'] != null) {
        buf.writeln('证书错误: ${apns['certError']}');
      }
      buf.writeln('连接状态: ${apns['connected']}');
      buf.writeln('Host: ${apns['host']}');
      buf.writeln('BundleId: ${apns['bundleId']}');
      buf.writeln('证书路径: ${apns['certPath']}');
      // 显示证书详细信息
      final ci = apns['certInfo'] as Map<String, dynamic>?;
      if (ci != null) {
        buf.writeln('');
        buf.writeln('=== 证书信息 ===');
        buf.writeln('主题: ${ci['subject'] ?? '未知'}');
        buf.writeln('有效期: ${ci['validFrom'] ?? '?'} → ${ci['validTo'] ?? '?'}');
        if (ci['expired'] == true) buf.writeln('⚠ 证书已过期!');
        if (ci['isPushCert'] == true) {
          buf.writeln('类型: APNs 推送证书 ✓');
        } else if (ci['isDistCert'] == true) {
          buf.writeln('⚠ 这是打包/签名证书，不是推送证书!');
        } else {
          buf.writeln('类型: ${ci['subject'] ?? '未知'}');
        }
      }
      buf.writeln('');
      buf.writeln('=== 已注册设备 (${devices.length}) ===');
      for (final d in devices) {
        buf.writeln('  ${d['deviceType']}: token=${d['hasPushToken'] ? d['tokenPrefix'] : '(无)'}');
      }
      return buf.toString();
    } catch (e) {
      return '获取失败: $e';
    }
  }

  void _showChangePassword() {
    final oldPwdCtrl = TextEditingController();
    final newPwdCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: oldPwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: '原密码')),
            const SizedBox(height: 8),
            TextField(controller: newPwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: '新密码 (至少6位)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final oldPwd = oldPwdCtrl.text.trim();
              final newPwd = newPwdCtrl.text.trim();
              if (oldPwd.isEmpty || newPwd.length < 6) {
                AppToast.show(context, '新密码长度至少6位');
                return;
              }
              Navigator.pop(ctx);
              try {
                final api = context.read<ApiClient>();
                await api.put('/users/me/password', data: {'oldPassword': oldPwd, 'newPassword': newPwd});
                if (mounted) AppToast.show(context, '密码已修改');
              } catch (e) {
                if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '修改失败'));
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 12),
            const Text('内部通', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const Text('Version 1.0.0', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            const Text('Express.js + MySQL + Redis\nSocket.IO · Flutter', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定'))],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              context.read<SocketService>().disconnect();
              await context.read<AuthService>().logout();
              if (context.mounted) {
                AppToast.show(context, '已退出登录');
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LandingPage()),
                  (_) => false,
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}
