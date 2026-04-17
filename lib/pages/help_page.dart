import 'package:flutter/material.dart';
import 'package:im_client/config/theme.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('帮助中心'),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Search bar (decorative)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)],
            ),
            child: const Row(children: [
              Icon(Icons.search, color: AppColors.textLight, size: 20),
              SizedBox(width: 10),
              Text('搜索常见问题...', style: TextStyle(color: AppColors.textLight, fontSize: 14)),
            ]),
          ),
          const SizedBox(height: 20),
          // Quick actions
          Row(
            children: [
              _quickAction(Icons.chat_bubble_outline, '在线客服', const Color(0xFF0066FF)),
              const SizedBox(width: 12),
              _quickAction(Icons.feedback_outlined, '意见反馈', const Color(0xFF5B8DEF)),
              const SizedBox(width: 12),
              _quickAction(Icons.report_outlined, '投诉举报', const Color(0xFFE87E52)),
            ],
          ),
          const SizedBox(height: 24),
          const Text('常见问题', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          _buildFaqSection('账号相关', Icons.person_outline, const Color(0xFF5B8DEF), [
            _FaqItem('如何注册内部通账号？', '打开内部通应用，点击"注册"按钮，输入手机号码获取验证码，设置密码和昵称即可完成注册。'),
            _FaqItem('忘记密码怎么办？', '在登录页面点击"忘记密码"，通过手机验证码验证身份后可重置密码。如果已绑定邮箱，也可通过邮箱找回。'),
            _FaqItem('如何绑定邮箱？', '进入"我" → "账号与安全" → "邮箱"，输入邮箱地址获取验证码，验证成功即可绑定。绑定邮箱可提升账号安全性。'),
            _FaqItem('如何修改个人资料？', '点击"我"页面顶部的个人信息区域，即可修改昵称、签名、性别等个人资料。'),
          ]),
          const SizedBox(height: 12),
          _buildFaqSection('聊天功能', Icons.chat_outlined, const Color(0xFF0066FF), [
            _FaqItem('如何发送语音消息？', '在聊天界面，长按底部的麦克风按钮即可录制语音消息，松手自动发送。'),
            _FaqItem('如何发起音视频通话？', '在聊天界面点击右上角的电话或视频图标，即可发起一对一的音视频通话。'),
            _FaqItem('如何创建群聊？', '在通讯录页面点击右上角的"+"号，选择"创建群聊"，勾选好友后即可创建群聊。'),
            _FaqItem('消息可以撤回吗？', '长按消息选择"撤回"，2分钟内的消息可以撤回。'),
          ]),
          const SizedBox(height: 12),
          _buildFaqSection('朋友圈', Icons.camera_alt_outlined, const Color(0xFF9B59B6), [
            _FaqItem('如何发布动态？', '进入"动态"页面，点击右上角的相机图标，可以发布文字、图片或视频动态。'),
            _FaqItem('如何设置动态可见范围？', '发布动态时可选择"公开"、"仅好友可见"或"仅自己可见"三种可见范围。'),
            _FaqItem('如何删除已发布的动态？', '在个人动态列表中，点击要删除的动态，选择"删除"即可。'),
          ]),
          const SizedBox(height: 12),
          _buildFaqSection('安全与隐私', Icons.security_outlined, const Color(0xFFE6A23C), [
            _FaqItem('我的聊天记录安全吗？', '内部通采用加密传输技术保护您的聊天数据安全，我们不会查看您的私人聊天内容。'),
            _FaqItem('如何防止账号被盗？', '建议您：1) 设置强密码；2) 绑定邮箱；3) 不要在不安全的设备上登录；4) 定期修改密码。'),
            _FaqItem('如何举报不良内容？', '长按不良消息选择"举报"，或在对方资料页面点击"举报"按钮，我们会及时处理。'),
          ]),
          const SizedBox(height: 32),
          Center(
            child: Column(children: [
              const Text('没有找到答案？', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.headset_mic_outlined, size: 18),
                label: const Text('联系在线客服'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ]),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)],
        ),
        child: Column(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
        ]),
      ),
    );
  }

  Widget _buildFaqSection(String title, IconData icon, Color color, List<_FaqItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          subtitle: Text('${items.length} 个常见问题', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          children: items.map((item) {
            return Theme(
              data: ThemeData(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(item.question, style: const TextStyle(fontSize: 14)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: Text(item.answer, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.6)),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _FaqItem {
  final String question;
  final String answer;
  _FaqItem(this.question, this.answer);
}
