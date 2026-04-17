import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/utils/clipboard_util.dart';
import 'package:im_client/widgets/user_avatar.dart';
import 'package:im_client/pages/settings_page.dart';
import 'package:im_client/pages/my_moments_page.dart';
import 'package:im_client/pages/security_page.dart';
import 'package:im_client/pages/about_page.dart';
import 'package:im_client/pages/help_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _profile;
  final _picker = ImagePicker();
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final api = context.read<ApiClient>();
      final data = await api.get('/users/me');
      if (!mounted) return;
      if (data is Map<String, dynamic>) {
        context.read<AuthService>().updateUser(data);
        setState(() => _profile = data);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        final user = _profile ?? auth.user ?? {};

        return Scaffold(
          backgroundColor: const Color(0xFFF5F6FA),
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            title: const Text('我的'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.qr_code_scanner, size: 22),
                onPressed: () => _showQrCode(context, user),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _loadProfile,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                const SizedBox(height: 16),
                _buildProfileCard(context, auth, user),
                const SizedBox(height: 20),
                _buildSectionTitle('常用功能'),
                const SizedBox(height: 10),
                _buildFeatureGrid(context, auth),
                const SizedBox(height: 20),
                _buildSectionTitle('设置与安全'),
                const SizedBox(height: 10),
                _buildMenuCard([
                  _MenuEntry(
                    icon: Icons.shield_outlined,
                    color: const Color(0xFF5B8DEF),
                    label: '账号与安全',
                    subtitle: '密码、邮箱绑定、设备管理',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SecurityPage()),
                    ).then((_) => _loadProfile()),
                  ),
                  _MenuEntry(
                    icon: Icons.tune_outlined,
                    color: const Color(0xFF78909C),
                    label: '通用设置',
                    subtitle: '消息通知、隐私、通用',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                _buildSectionTitle('支持与帮助'),
                const SizedBox(height: 10),
                _buildMenuCard([
                  _MenuEntry(
                    icon: Icons.help_outline,
                    color: const Color(0xFF26A69A),
                    label: '帮助中心',
                    subtitle: '常见问题、使用指南',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpPage())),
                  ),
                  _MenuEntry(
                    icon: Icons.info_outline,
                    color: const Color(0xFF42A5F5),
                    label: '关于内部通',
                    subtitle: '版本信息、隐私协议',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage())),
                  ),
                ]),
                const SizedBox(height: 100),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileCard(BuildContext context, AuthService auth, Map<String, dynamic> user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar with upload overlay
              GestureDetector(
                onTap: () => _pickAndUploadAvatar(context, auth),
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
                      ),
                      child: UserAvatar(name: user['nickname'], url: user['avatarUrl'], size: 72, radius: 22),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                        ),
                        child: _uploadingAvatar
                            ? const Padding(padding: EdgeInsets.all(5), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                            : const Icon(Icons.camera_alt_rounded, size: 14, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Name + ID + signature
              Expanded(
                child: GestureDetector(
                  onTap: () => _showEditProfile(context, auth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              (user['nickname'] ?? '未设置').toString(),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (user['gender'] == 1) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(color: const Color(0xFFE3F0FF), borderRadius: BorderRadius.circular(6)),
                              child: const Icon(Icons.male, size: 13, color: Color(0xFF4A90D9)),
                            ),
                          ] else if (user['gender'] == 2) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(color: const Color(0xFFFCE4EC), borderRadius: BorderRadius.circular(6)),
                              child: const Icon(Icons.female, size: 13, color: Color(0xFFE8758A)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () async {
                          await ClipboardUtil.copy(user['uid']?.toString() ?? '');
                          if (context.mounted) AppToast.show(context, '已复制内部通号');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFF5F6FA), borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('ID: ${user['uid'] ?? ''}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                              const SizedBox(width: 4),
                              const Icon(Icons.copy_rounded, size: 11, color: AppColors.textLight),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _showEditProfile(context, auth),
                child: const Icon(Icons.chevron_right, color: AppColors.textLight, size: 22),
              ),
            ],
          ),
          if (user['signature'] != null && user['signature'].toString().trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFF8F9FC), borderRadius: BorderRadius.circular(10)),
              child: Text(
                user['signature'].toString(),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickAndUploadAvatar(BuildContext context, AuthService auth) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (image == null) return;
    if (!mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final api = context.read<ApiClient>();
      final Uint8List bytes = await image.readAsBytes();
      final String ext = image.name.split('.').last.toLowerCase();
      final mimeType = {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp'}[ext] ?? 'image/jpeg';

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: 'avatar.$ext', contentType: MediaType.parse(mimeType)),
      });
      final uploadData = Map<String, dynamic>.from(await api.upload('/upload', formData));
      final avatarUrl = uploadData['url'] as String?;

      if (avatarUrl != null) {
        final result = await api.put('/users/me', data: {'avatarUrl': avatarUrl});
        if (result is Map<String, dynamic>) {
          auth.updateUser(result);
          if (mounted) setState(() => _profile = result);
        }
        if (mounted) AppToast.show(context, '头像已更新');
      }
    } catch (e) {
      if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '上传失败'));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
    );
  }

  Widget _buildFeatureGrid(BuildContext context, AuthService auth) {
    final items = [
      _FeatureItem(icon: Icons.camera_alt_outlined, label: '朋友圈', color: const Color(0xFF5B7BCA),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyMomentsPage(userId: auth.userId ?? 0)))),
      _FeatureItem(icon: Icons.photo_library_outlined, label: '我的相册', color: const Color(0xFF409EFF),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyMomentsPage(userId: auth.userId ?? 0)))),
      _FeatureItem(icon: Icons.collections_bookmark_outlined, label: '我的收藏', color: const Color(0xFFE6A23C),
        onTap: () => AppToast.show(context, '收藏功能即将上线')),
      _FeatureItem(icon: Icons.emoji_emotions_outlined, label: '表情商店', color: const Color(0xFFE87E52),
        onTap: () => AppToast.show(context, '表情商店即将上线')),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.map((item) {
          return GestureDetector(
            onTap: item.onTap,
            child: Column(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: item.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                  child: Icon(item.icon, color: item.color, size: 24),
                ),
                const SizedBox(height: 8),
                Text(item.label, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMenuCard(List<_MenuEntry> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Column(
            children: [
              InkWell(
                onTap: item.onTap,
                borderRadius: i == 0 && items.length == 1
                    ? BorderRadius.circular(16)
                    : i == 0
                        ? const BorderRadius.vertical(top: Radius.circular(16))
                        : i == items.length - 1
                            ? const BorderRadius.vertical(bottom: Radius.circular(16))
                            : BorderRadius.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(color: item.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                        child: Icon(item.icon, color: item.color, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                            if (item.subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(item.subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.textLight, size: 20),
                    ],
                  ),
                ),
              ),
              if (i < items.length - 1) const Divider(height: 0.5, indent: 68, color: Color(0xFFF0F0F0)),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _showQrCode(BuildContext context, Map<String, dynamic> user) {
    final uid = user['uid']?.toString() ?? '';
    final nickname = (user['nickname'] ?? '').toString();
    final qrData = 'im://add?uid=$uid';
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        child: Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                UserAvatar(name: nickname, url: user['avatarUrl'], size: 48, radius: 10),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nickname, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: () async {
                      await ClipboardUtil.copy(uid);
                      if (ctx.mounted) AppToast.show(ctx, '已复制内部通号');
                    },
                    child: Row(children: [
                      Text('内部通号: $uid', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      const SizedBox(width: 4),
                      const Icon(Icons.copy_rounded, size: 12, color: AppColors.textLight),
                    ]),
                  ),
                ])),
              ]),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEEEEEE))),
                child: QrImageView(data: qrData, version: QrVersions.auto, size: 180,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF333333)),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF333333)), gapless: true),
              ),
              const SizedBox(height: 14),
              const Text('扫一扫上面的二维码，加我内部通', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 40, child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(backgroundColor: const Color(0xFFF5F5F5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                child: const Text('关闭', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditProfile(BuildContext context, AuthService auth) {
    final user = auth.user ?? {};
    final nicknameCtrl = TextEditingController(text: user['nickname'] ?? '');
    final signatureCtrl = TextEditingController(text: user['signature'] ?? '');
    int gender = user['gender'] ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: const Color(0xFFDDDDDD), borderRadius: BorderRadius.circular(2)))),
              const Text('编辑个人资料', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              _buildInputField('昵称', nicknameCtrl, maxLength: 20),
              const SizedBox(height: 14),
              _buildInputField('签名', signatureCtrl, maxLength: 20),
              const SizedBox(height: 14),
              const Text('性别', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(children: [
                _genderChip('男', Icons.male, const Color(0xFF4A90D9), gender == 1, () => setModalState(() => gender = 1)),
                const SizedBox(width: 10),
                _genderChip('女', Icons.female, const Color(0xFFE8758A), gender == 2, () => setModalState(() => gender = 2)),
                const SizedBox(width: 10),
                _genderChip('保密', Icons.lock_outline, const Color(0xFF999999), gender == 0, () => setModalState(() => gender = 0)),
              ]),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    final api = context.read<ApiClient>();
                    final result = await api.put('/users/me', data: {
                      'nickname': nicknameCtrl.text.trim(),
                      'signature': signatureCtrl.text.trim(),
                      'gender': gender,
                    });
                    if (result is Map<String, dynamic>) {
                      auth.updateUser(result);
                      setState(() => _profile = result);
                    }
                    if (context.mounted) AppToast.show(context, '资料已更新');
                  } catch (e) {
                    if (context.mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '更新失败'));
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                child: const Text('保存', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, {int? maxLength}) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label, counterText: '', filled: true, fillColor: const Color(0xFFF8F8F8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _genderChip(String label, IconData icon, Color color, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : Colors.transparent, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: selected ? color : AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 13, color: selected ? color : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  _FeatureItem({required this.icon, required this.label, required this.color, required this.onTap});
}

class _MenuEntry {
  final IconData icon;
  final Color color;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  _MenuEntry({required this.icon, required this.color, required this.label, this.subtitle, required this.onTap});
}
