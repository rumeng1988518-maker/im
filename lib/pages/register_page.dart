import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // Step 1 fields
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _agreeTerms = false;

  // Step 2 fields
  final _nicknameCtrl = TextEditingController();
  int _gender = 0;
  Uint8List? _avatarBytes;
  String? _avatarName;
  final _picker = ImagePicker();

  int _step = 1;
  bool _loading = false;

  // Registration result (token data) from step 1
  Map<String, dynamic>? _authData;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _nicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _doRegister() async {
    final phone = _phoneCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (phone.isEmpty) { AppToast.show(context, '请输入账号'); return; }
    if (password.isEmpty) { AppToast.show(context, '请设置密码'); return; }
    if (password.length < 6) { AppToast.show(context, '密码至少6个字符'); return; }
    if (confirm.isEmpty) { AppToast.show(context, '请确认密码'); return; }
    if (password != confirm) { AppToast.show(context, '两次密码不一致'); return; }
    if (!_agreeTerms) { AppToast.show(context, '请先同意服务条款和隐私政策'); return; }

    setState(() => _loading = true);
    try {
      final api = context.read<ApiClient>();
      final data = await api.post('/auth/register', data: {
        'phone': phone,
        'password': password,
        'nickname': '内部通用户',
      });

      if (!mounted) return;
      _authData = Map<String, dynamic>.from(data);

      // Set auth so API calls in step 2 are authenticated
      final auth = context.read<AuthService>();
      await auth.setAuth(_authData!);

      if (!mounted) return;
      setState(() { _step = 2; _loading = false; });
    } catch (e) {
      if (mounted) {
        AppToast.show(context, ErrorMessage.from(e, fallback: '注册失败，请稍后重试'));
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickAvatar() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() { _avatarBytes = bytes; _avatarName = image.name; });
  }

  Future<void> _completeProfile() async {
    final nickname = _nicknameCtrl.text.trim();
    if (nickname.isEmpty) { AppToast.show(context, '请设置昵称'); return; }

    setState(() => _loading = true);
    try {
      final api = context.read<ApiClient>();
      final auth = context.read<AuthService>();

      String? avatarUrl;
      // Upload avatar if selected
      if (_avatarBytes != null) {
        final ext = (_avatarName ?? 'avatar.jpg').split('.').last.toLowerCase();
        final mimeType = {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp'}[ext] ?? 'image/jpeg';
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(_avatarBytes!, filename: 'avatar.$ext', contentType: MediaType.parse(mimeType)),
        });
        final uploadData = Map<String, dynamic>.from(await api.upload('/upload', formData));
        avatarUrl = uploadData['url'] as String?;
      }

      // Update profile
      final updateData = <String, dynamic>{
        'nickname': nickname,
        'gender': _gender,
      };
      if (avatarUrl != null) updateData['avatarUrl'] = avatarUrl;

      final result = await api.put('/users/me', data: updateData);
      if (!mounted) return;
      if (result is Map<String, dynamic>) {
        auth.updateUser(result);
      }

      if (!mounted) return;
      AppToast.show(context, '注册成功，欢迎使用内部通！');
      // Pop all auth pages - already logged in
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, ErrorMessage.from(e, fallback: '设置资料失败'));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: _step == 1 ? _buildStep1() : _buildStep2(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),

        // Logo
        Image.asset('assets/images/logo.png', width: 72, height: 72),
        const SizedBox(height: 16),
        const Text('创建账号', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 6),
        const Text('立即加入内部通，开始畅聊', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),

        // Step indicator
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Row(
            children: [
              Expanded(child: Container(height: 3, decoration: BoxDecoration(color: const Color(0xFF0066FF), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 3, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2)))),
            ],
          ),
        ),

        // Phone
        _buildTextField(controller: _phoneCtrl, hint: '请输入手机号', icon: Icons.phone_outlined, keyboard: TextInputType.phone),
        const SizedBox(height: 16),

        // Password
        _buildTextField(
          controller: _passwordCtrl, hint: '设置密码（至少6位）', icon: Icons.lock_outline, obscure: _obscure,
          suffix: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.textLight, size: 20),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        const SizedBox(height: 16),

        // Confirm
        _buildTextField(
          controller: _confirmCtrl, hint: '确认密码', icon: Icons.lock_outline, obscure: _obscureConfirm,
          suffix: IconButton(
            icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.textLight, size: 20),
            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
          onSubmitted: (_) => _doRegister(),
        ),
        const SizedBox(height: 20),

        // Terms
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 22, height: 22,
              child: Checkbox(
                value: _agreeTerms,
                onChanged: (v) => setState(() => _agreeTerms = v ?? false),
                shape: const CircleBorder(),
                activeColor: const Color(0xFF0066FF),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: '我已阅读并同意 ',
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  children: [
                    const TextSpan(text: '服务条款', style: TextStyle(color: Color(0xFF0066FF), fontWeight: FontWeight.w500, fontSize: 12)),
                    const TextSpan(text: ' 和 '),
                    const TextSpan(text: '隐私政策', style: TextStyle(color: Color(0xFF0066FF), fontWeight: FontWeight.w500, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Next button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _loading ? null : _doRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066FF),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF0066FF).withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              elevation: 0,
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            child: _loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Row(mainAxisSize: MainAxisSize.min, children: [Text('下一步'), SizedBox(width: 6), Icon(Icons.arrow_forward, size: 18)]),
          ),
        ),
        const SizedBox(height: 24),

        // Login link
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('已有账号？', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF0066FF), padding: const EdgeInsets.symmetric(horizontal: 4)),
              child: const Text('去登录', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        const Text('完善资料', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 6),
        const Text('设置你的头像和昵称', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),

        // Step indicator
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Row(
            children: [
              Expanded(child: Container(height: 3, decoration: BoxDecoration(color: const Color(0xFF0066FF), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 3, decoration: BoxDecoration(color: const Color(0xFF0066FF), borderRadius: BorderRadius.circular(2)))),
            ],
          ),
        ),

        // Avatar picker
        GestureDetector(
          onTap: _pickAvatar,
          child: Stack(
            children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6FA),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
                  image: _avatarBytes != null
                      ? DecorationImage(image: MemoryImage(_avatarBytes!), fit: BoxFit.cover)
                      : null,
                ),
                child: _avatarBytes == null
                    ? const Icon(Icons.person_rounded, size: 48, color: Color(0xFFD1D5DB))
                    : null,
              ),
              Positioned(
                right: 0, bottom: 0,
                child: Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0066FF),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, size: 15, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('点击上传头像', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 24),

        // Nickname
        _buildTextField(controller: _nicknameCtrl, hint: '设置你的昵称', icon: Icons.badge_outlined),
        const SizedBox(height: 20),

        // Gender selection
        const Align(alignment: Alignment.centerLeft, child: Text('选择性别', style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)))),
        const SizedBox(height: 10),
        Row(
          children: [
            _genderOption('男', Icons.male, const Color(0xFF4A90D9), 1),
            const SizedBox(width: 12),
            _genderOption('女', Icons.female, const Color(0xFFE8758A), 2),
            const SizedBox(width: 12),
            _genderOption('保密', Icons.lock_outline, const Color(0xFF9CA3AF), 0),
          ],
        ),
        const SizedBox(height: 32),

        // Complete button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _loading ? null : _completeProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066FF),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF0066FF).withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              elevation: 0,
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            child: _loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('开始使用'),
          ),
        ),
        const SizedBox(height: 16),

        // Skip button
        TextButton(
          onPressed: _loading ? null : () {
            AppToast.show(context, '注册成功，欢迎使用内部通！');
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF9CA3AF)),
          child: const Text('跳过，稍后设置', style: TextStyle(fontSize: 14)),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _genderOption(String label, IconData icon, Color color, int value) {
    final selected = _gender == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _gender = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.1) : const Color(0xFFF5F6FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : Colors.transparent, width: 1.5),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: selected ? color : const Color(0xFF9CA3AF)),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 13, color: selected ? color : const Color(0xFF9CA3AF), fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboard,
    bool obscure = false,
    Widget? suffix,
    void Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      style: const TextStyle(fontSize: 16),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textLight, fontSize: 15),
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF9CA3AF)),
        filled: true,
        fillColor: const Color(0xFFF5F6FA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF0066FF), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        suffixIcon: suffix,
      ),
    );
  }
}
