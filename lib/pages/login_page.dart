import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/pages/register_page.dart';
import 'package:im_client/pages/forgot_password_page.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/pages/home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    if (phone.isEmpty) {
      AppToast.show(context, '请输入账号');
      return;
    }
    if (password.isEmpty) {
      AppToast.show(context, '请输入密码');
      return;
    }

    setState(() => _loading = true);

    try {
      final api = context.read<ApiClient>();
      final data = await api.post('/auth/login', data: {
        'phone': phone,
        'password': password,
      });

      if (!mounted) return;
      final auth = context.read<AuthService>();
      await auth.setAuth(Map<String, dynamic>.from(data));

      if (!mounted) return;
      AppToast.show(context, '登录成功');
      // 显式导航到主页，不依赖 Consumer 重建时序
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, ErrorMessage.from(e, fallback: '登录失败，请检查账号或密码'));
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // Logo
                    Image.asset('assets/images/logo.png', width: 80, height: 80),
                    const SizedBox(height: 16),
                    const Text('欢迎回来', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 6),
                    const Text('登录你的内部通账号', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                    const SizedBox(height: 40),

                    // Phone field
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        hintText: '请输入手机号',
                        hintStyle: const TextStyle(color: AppColors.textLight, fontSize: 15),
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20, color: Color(0xFF9CA3AF)),
                        filled: true,
                        fillColor: const Color(0xFFF5F6FA),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF0066FF), width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Password field
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        hintText: '请输入密码',
                        hintStyle: const TextStyle(color: AppColors.textLight, fontSize: 15),
                        prefixIcon: const Icon(Icons.lock_outline, size: 20, color: Color(0xFF9CA3AF)),
                        filled: true,
                        fillColor: const Color(0xFFF5F6FA),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF0066FF), width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.textLight, size: 20),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onSubmitted: (_) => _login(),
                    ),

                    // Forgot password
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordPage())),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF0066FF), padding: const EdgeInsets.symmetric(vertical: 8)),
                        child: const Text('忘记密码？', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Login button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
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
                            : const Text('登 录'),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Register link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('还没有账号？', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
                        TextButton(
                          onPressed: () async {
                            final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage()));
                            if (!context.mounted) return;
                            if (result is String && result.trim().isNotEmpty) {
                              AppToast.show(context, result);
                            }
                          },
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF0066FF), padding: const EdgeInsets.symmetric(horizontal: 4)),
                          child: const Text('立即注册', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 40),

                    // Terms
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text.rich(
                        TextSpan(
                          text: '登录即代表同意 ',
                          style: const TextStyle(color: AppColors.textLight, fontSize: 11),
                          children: [
                            TextSpan(text: '服务条款', style: TextStyle(color: const Color(0xFF0066FF).withValues(alpha: 0.8), fontSize: 11)),
                            const TextSpan(text: ' 和 '),
                            TextSpan(text: '隐私政策', style: TextStyle(color: const Color(0xFF0066FF).withValues(alpha: 0.8), fontSize: 11)),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
