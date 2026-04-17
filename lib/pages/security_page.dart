import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  Map<String, dynamic>? _profile;
  bool _loading = true;

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
        setState(() {
          _profile = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('账号与安全'),
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
                // Security overview card
                _buildSecurityOverview(),
                const SizedBox(height: 20),
                // Account info
                _buildSectionLabel('账号信息'),
                const SizedBox(height: 10),
                _buildCard([
                  _infoTile(
                    Icons.phone_android,
                    '手机号',
                    _profile?['phone'] ?? '未绑定',
                    const Color(0xFF0066FF),
                    enabled: false,
                  ),
                  _infoTile(
                    Icons.email_outlined,
                    '邮箱',
                    _profile?['email'] ?? '未绑定',
                    const Color(0xFF5B8DEF),
                    trailing: _profile?['email'] != null
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('已绑定', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, color: AppColors.textLight, size: 20),
                          ])
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('去绑定', style: TextStyle(fontSize: 11, color: AppColors.warning)),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, color: AppColors.textLight, size: 20),
                          ]),
                    onTap: () => _showEmailBinding(context),
                  ),
                  _infoTile(
                    Icons.badge_outlined,
                    '内部通号',
                    _profile?['uid'] ?? '-',
                    const Color(0xFF9B59B6),
                    enabled: false,
                  ),
                ]),
                const SizedBox(height: 20),
                // Security settings
                _buildSectionLabel('安全设置'),
                const SizedBox(height: 10),
                _buildCard([
                  _actionTile(
                    Icons.lock_outline,
                    '修改登录密码',
                    '定期修改密码可以保护账号安全',
                    const Color(0xFF9B59B6),
                    onTap: _showChangePassword,
                  ),
                ]),
                const SizedBox(height: 20),
                // Login devices
                _buildSectionLabel('登录设备'),
                const SizedBox(height: 10),
                _buildCard([
                  _actionTile(
                    Icons.devices,
                    '设备管理',
                    '查看当前登录设备',
                    const Color(0xFF26A69A),
                    onTap: () => AppToast.show(context, '设备管理即将上线'),
                  ),
                ]),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildSecurityOverview() {
    final hasPhone = _profile?['phone'] != null;
    final hasEmail = _profile?['email'] != null;
    int score = 60;
    if (hasPhone) score += 20;
    if (hasEmail) score += 20;
    final color = score >= 80 ? AppColors.primary : (score >= 60 ? AppColors.warning : AppColors.danger);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          // Score circle
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.2),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 3),
            ),
            child: Center(
              child: Text('$score', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  score >= 80 ? '安全等级：高' : (score >= 60 ? '安全等级：中' : '安全等级：低'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  score >= 100 ? '您的账号安全性很高' : '建议绑定邮箱提升安全等级',
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  _securityBadge('手机', hasPhone),
                  const SizedBox(width: 8),
                  _securityBadge('邮箱', hasEmail),
                  const SizedBox(width: 8),
                  _securityBadge('密码', true),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _securityBadge(String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? Colors.white.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(active ? Icons.check_circle : Icons.cancel, size: 12, color: Colors.white.withValues(alpha: active ? 1 : 0.5)),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: active ? 1 : 0.5))),
      ]),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary));
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1) const Divider(indent: 56, height: 0, color: Color(0xFFF0F0F0)),
        ],
      ]),
    );
  }

  Widget _infoTile(IconData icon, String label, String value, Color color, {Widget? trailing, VoidCallback? onTap, bool enabled = true}) {
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      subtitle: Text(value, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: trailing ?? (enabled ? const Icon(Icons.chevron_right, color: AppColors.textLight, size: 20) : null),
      onTap: enabled ? onTap : null,
    );
  }

  Widget _actionTile(IconData icon, String label, String subtitle, Color color, {VoidCallback? onTap}) {
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textLight, size: 20),
      onTap: onTap,
    );
  }

  void _showEmailBinding(BuildContext context) {
    final currentEmail = _profile?['email'];
    final emailCtrl = TextEditingController(text: currentEmail ?? '');
    final codeCtrl = TextEditingController();
    int countdown = 0;
    Timer? timer;
    bool sending = false;
    bool binding = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void startCountdown() {
            countdown = 60;
            timer?.cancel();
            timer = Timer.periodic(const Duration(seconds: 1), (t) {
              if (countdown <= 1) {
                t.cancel();
                setModalState(() => countdown = 0);
              } else {
                setModalState(() => countdown--);
              }
            });
          }

          return Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: const Color(0xFFDDDDDD), borderRadius: BorderRadius.circular(2)))),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(currentEmail != null ? '修改邮箱' : '绑定邮箱', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    if (currentEmail != null)
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          try {
                            final api = context.read<ApiClient>();
                            final result = await api.delete('/users/me/email');
                            if (result is Map<String, dynamic>) {
                              context.read<AuthService>().updateUser(result);
                            }
                            _loadProfile();
                            if (context.mounted) AppToast.show(context, '邮箱已解绑');
                          } catch (e) {
                            if (context.mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '解绑失败'));
                          }
                        },
                        child: const Text('解除绑定', style: TextStyle(color: AppColors.danger, fontSize: 13)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  currentEmail != null ? '当前已绑定: $currentEmail' : '绑定邮箱后可用于找回密码',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                // Email input
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: '邮箱地址',
                    prefixIcon: const Icon(Icons.email_outlined, size: 20),
                    filled: true, fillColor: const Color(0xFFF8F8F8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 14),
                // Code input with send button
                TextField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: '验证码',
                    counterText: '',
                    prefixIcon: const Icon(Icons.verified_user_outlined, size: 20),
                    filled: true, fillColor: const Color(0xFFF8F8F8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: TextButton(
                        onPressed: (countdown > 0 || sending) ? null : () async {
                          final email = emailCtrl.text.trim();
                          if (email.isEmpty || !email.contains('@')) {
                            AppToast.show(ctx, '请输入正确的邮箱地址');
                            return;
                          }
                          setModalState(() => sending = true);
                          try {
                            final api = context.read<ApiClient>();
                            await api.post('/users/me/email/send-code', data: {'email': email});
                            if (ctx.mounted) AppToast.show(ctx, '验证码已发送');
                            startCountdown();
                          } catch (e) {
                            if (ctx.mounted) AppToast.show(ctx, ErrorMessage.from(e, fallback: '发送失败'));
                          }
                          setModalState(() => sending = false);
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: (countdown > 0 || sending) ? const Color(0xFFE0E0E0) : AppColors.primary,
                          foregroundColor: (countdown > 0 || sending) ? const Color(0xFF9CA3AF) : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 36),
                        ),
                        child: Text(
                          countdown > 0 ? '${countdown}s' : (sending ? '...' : '发送验证码'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  ),
                ),
                const SizedBox(height: 24),
                // Bind button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: binding ? null : () async {
                      final email = emailCtrl.text.trim();
                      final code = codeCtrl.text.trim();
                      if (email.isEmpty || !email.contains('@')) {
                        AppToast.show(ctx, '请输入正确的邮箱地址');
                        return;
                      }
                      if (code.length != 6) {
                        AppToast.show(ctx, '请输入6位验证码');
                        return;
                      }
                      setModalState(() => binding = true);
                      try {
                        final api = context.read<ApiClient>();
                        final result = await api.post('/users/me/email/bind', data: {'email': email, 'code': code});
                        if (result is Map<String, dynamic>) {
                          context.read<AuthService>().updateUser(result);
                        }
                        timer?.cancel();
                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadProfile();
                        if (context.mounted) AppToast.show(context, '邮箱绑定成功');
                      } catch (e) {
                        if (ctx.mounted) AppToast.show(ctx, ErrorMessage.from(e, fallback: '绑定失败'));
                      }
                      setModalState(() => binding = false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text(binding ? '绑定中...' : '确认绑定', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showChangePassword() {
    final oldPwdCtrl = TextEditingController();
    final newPwdCtrl = TextEditingController();
    final confirmPwdCtrl = TextEditingController();
    bool obscureOld = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

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
              const Text('修改密码', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text('修改后需要重新登录', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              _passwordField('原密码', oldPwdCtrl, obscureOld, () => setModalState(() => obscureOld = !obscureOld)),
              const SizedBox(height: 14),
              _passwordField('新密码 (至少6位)', newPwdCtrl, obscureNew, () => setModalState(() => obscureNew = !obscureNew)),
              const SizedBox(height: 14),
              _passwordField('确认新密码', confirmPwdCtrl, obscureConfirm, () => setModalState(() => obscureConfirm = !obscureConfirm)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final oldPwd = oldPwdCtrl.text.trim();
                    final newPwd = newPwdCtrl.text.trim();
                    final confirmPwd = confirmPwdCtrl.text.trim();
                    if (oldPwd.isEmpty) {
                      AppToast.show(ctx, '请输入原密码');
                      return;
                    }
                    if (newPwd.length < 6) {
                      AppToast.show(ctx, '新密码长度至少6位');
                      return;
                    }
                    if (newPwd != confirmPwd) {
                      AppToast.show(ctx, '两次输入的密码不一致');
                      return;
                    }
                    Navigator.pop(ctx);
                    try {
                      final api = context.read<ApiClient>();
                      await api.put('/users/me/password', data: {'oldPassword': oldPwd, 'newPassword': newPwd});
                      if (context.mounted) AppToast.show(context, '密码已修改');
                    } catch (e) {
                      if (context.mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '修改失败'));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0,
                  ),
                  child: const Text('确认修改', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _passwordField(String label, TextEditingController ctrl, bool obscure, VoidCallback toggle) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline, size: 20),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 20, color: AppColors.textLight),
          onPressed: toggle,
        ),
        filled: true, fillColor: const Color(0xFFF8F8F8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      ),
    );
  }
}
