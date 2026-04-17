import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:im_client/providers/contacts_provider.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/widgets/user_avatar.dart';

class ScanAddFriendPage extends StatefulWidget {
  const ScanAddFriendPage({super.key});

  @override
  State<ScanAddFriendPage> createState() => _ScanAddFriendPageState();
}

class _ScanAddFriendPageState extends State<ScanAddFriendPage> {
  late MobileScannerController _controller;
  bool _processing = false;
  bool _cameraError = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _extractKeyword(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';

    final uri = Uri.tryParse(text);
    if (uri != null) {
      final uid = uri.queryParameters['uid'];
      if (uid != null && uid.trim().isNotEmpty) return uid.trim();
      final phone = uri.queryParameters['phone'];
      if (phone != null && phone.trim().isNotEmpty) return phone.trim();
      final keyword = uri.queryParameters['keyword'];
      if (keyword != null && keyword.trim().isNotEmpty) return keyword.trim();
      if (uri.pathSegments.isNotEmpty) {
        final last = uri.pathSegments.last.trim();
        if (last.isNotEmpty) return last;
      }
    }

    final uidMatch = RegExp(r'uid[:=]\s*([A-Za-z0-9_-]+)', caseSensitive: false).firstMatch(text);
    if (uidMatch != null) {
      return (uidMatch.group(1) ?? '').trim();
    }

    final phoneMatch = RegExp(r'\d{6,20}').firstMatch(text);
    if (phoneMatch != null) {
      return (phoneMatch.group(0) ?? '').trim();
    }

    return text;
  }

  Future<void> _processKeyword(String keyword, {bool fromScanner = false}) async {
    if (_processing) return;
    final q = keyword.trim();
    if (q.isEmpty) {
      AppToast.show(context, '未识别到有效的好友信息');
      return;
    }

    setState(() => _processing = true);
    try {
      final users = await context.read<ContactsProvider>().searchUsers(q);
      if (!mounted) return;

      if (users.isEmpty) {
        AppToast.show(context, '未找到用户，请确认二维码是否有效');
        return;
      }

      await _showUserSheet(users, fromScanner: fromScanner);
    } catch (e) {
      if (!mounted) return;
      final message = ErrorMessage.from(e, fallback: '扫描处理失败，请稍后重试');
      AppToast.show(context, message);
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _showUserSheet(List<Map<String, dynamic>> users, {required bool fromScanner}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD8D8D8),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 14),
              Text(fromScanner ? '扫描到以下用户' : '匹配到以下用户', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: users.length,
                  separatorBuilder: (_, _) => const Divider(height: 0.5),
                  itemBuilder: (_, index) {
                    final user = users[index];
                    final userId = user['userId'] as int?;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: UserAvatar(name: user['nickname'], url: user['avatarUrl'], size: 44, radius: 8),
                      title: Text((user['nickname'] ?? '未知用户').toString()),
                      subtitle: Text('UID: ${user['uid'] ?? ''}', style: const TextStyle(fontSize: 12)),
                      trailing: TextButton(
                        onPressed: userId == null
                            ? null
                            : () async {
                                final contacts = context.read<ContactsProvider>();
                                try {
                                  await contacts.sendFriendRequest(userId, '来自扫一扫添加好友');
                                  if (!mounted || !ctx.mounted) return;
                                  Navigator.pop(ctx);
                                  AppToast.show(context, '好友申请已发送');
                                } catch (e) {
                                  if (!mounted || !ctx.mounted) return;
                                  final message = ErrorMessage.from(e, fallback: '发送好友申请失败，请稍后重试');
                                  AppToast.show(context, message);
                                }
                              },
                        child: const Text('添加'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _manualInput() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动输入好友信息'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '请输入 UID / 手机号 / 好友码',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || value == null || value.trim().isEmpty) return;
    await _processKeyword(value, fromScanner: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫一扫添加好友'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _manualInput,
            child: const Text('手动输入', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_cameraError)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_off_outlined, size: 64, color: Colors.white38),
                  const SizedBox(height: 16),
                  const Text('无法打开相机', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text('请确认已授予相机权限，\n且当前网址使用 HTTPS 协议', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 13)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _manualInput,
                    icon: const Icon(Icons.keyboard),
                    label: const Text('手动输入好友信息'),
                  ),
                ],
              ),
            )
          else
            MobileScanner(
              controller: _controller,
              errorBuilder: (context, error, child) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_cameraError) setState(() => _cameraError = true);
                });
                return const SizedBox();
              },
              onDetect: (capture) async {
                if (_processing) return;
                final raw = capture.barcodes
                    .map((b) => b.rawValue)
                    .whereType<String>()
                    .map((e) => e.trim())
                    .firstWhere((e) => e.isNotEmpty, orElse: () => '');
                if (raw.isEmpty) return;
                await _processKeyword(_extractKeyword(raw), fromScanner: true);
              },
            ),
          if (!_cameraError) ...[
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 40,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _processing ? '处理中...' : '将好友二维码放入框内即可自动识别',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
