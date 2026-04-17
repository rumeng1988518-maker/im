import 'package:flutter/material.dart';
import 'package:im_client/config/app_config.dart';
import 'package:im_client/config/theme.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('关于内部通'),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 20),
          // Logo section
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0066FF), Color(0xFF0052CC)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 16),
                const Text(AppConfig.appName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('Version ${AppConfig.version}', style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Info cards
          _buildInfoCard([
            _InfoItem(icon: Icons.new_releases_outlined, label: '版本更新', value: '当前已是最新版本'),
            _InfoItem(icon: Icons.star_outline, label: '评分', value: '去应用商店评分'),
          ]),
          const SizedBox(height: 16),
          _buildInfoCard([
            _InfoItem(icon: Icons.description_outlined, label: '用户协议', onTap: () => _showDocument(context, '用户协议', _userAgreement)),
            _InfoItem(icon: Icons.privacy_tip_outlined, label: '隐私政策', onTap: () => _showDocument(context, '隐私政策', _privacyPolicy)),
            _InfoItem(icon: Icons.gavel_outlined, label: '开源许可', onTap: () => _showDocument(context, '开源许可', _openSourceLicense)),
          ]),
          const SizedBox(height: 32),
          // Tech stack
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)],
              ),
              child: const Text(
                'Flutter · Express.js · MySQL · Redis · Socket.IO',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              '© 2026 内部通 All rights reserved.',
              style: TextStyle(fontSize: 12, color: AppColors.textLight),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildInfoCard(List<_InfoItem> items) {
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
              ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(item.icon, color: AppColors.primary, size: 20),
                ),
                title: Text(item.label, style: const TextStyle(fontSize: 15)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (item.value != null) Text(item.value!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: AppColors.textLight, size: 20),
                ]),
                onTap: item.onTap,
              ),
              if (i < items.length - 1) const Divider(indent: 56, height: 0, color: Color(0xFFF0F0F0)),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _showDocument(BuildContext context, String title, String content) {
    Navigator.push(context, MaterialPageRoute(
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: Text(title),
          leading: IconButton(icon: const Icon(Icons.chevron_left, size: 28), onPressed: () => Navigator.pop(ctx)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Text(content, style: const TextStyle(fontSize: 14, height: 1.8, color: AppColors.textPrimary)),
        ),
      ),
    ));
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  _InfoItem({required this.icon, required this.label, this.value, this.onTap});
}

const _userAgreement = '''内部通用户服务协议

最近更新日期：2026年4月1日
生效日期：2026年4月1日

欢迎您使用内部通！请您仔细阅读以下条款，如您对本协议的任何条款表示异议，您可以选择不使用内部通服务。当您注册成功或使用内部通服务，即表示您已充分阅读、理解并接受本协议的全部内容。

一、服务内容

1.1 内部通是一款即时通讯应用，提供文字聊天、语音通话、视频通话、朋友圈等社交功能。

1.2 内部通为用户提供免费的基础通讯服务，包括但不限于文字消息、语音消息、图片发送、文件传输等功能。

二、用户注册与账号管理

2.1 用户需使用有效的手机号码注册内部通账号，一个手机号码仅能注册一个内部通账号。

2.2 用户应妥善保管账号信息和登录密码，因用户保管不善造成的损失，由用户自行承担。

2.3 用户可以绑定邮箱作为辅助安全验证方式，绑定后可用于找回密码等安全操作。

三、用户行为规范

3.1 用户不得利用内部通发布、传播违反国家法律法规、危害国家安全、破坏社会稳定的信息。

3.2 用户不得利用内部通从事任何违法犯罪活动，包括但不限于诈骗、传播淫秽色情信息等。

3.3 用户不得利用技术手段干扰内部通的正常运行，不得恶意攻击内部通的服务器和数据。

四、隐私保护

4.1 内部通尊重并保护用户的个人隐私，未经用户同意不会向第三方披露用户的个人信息。

4.2 内部通会采取合理的安全措施保护用户数据的安全性和完整性。

五、知识产权

5.1 内部通的所有知识产权均归内部通所有，包括但不限于商标、专利、著作权、商业秘密等。

六、免责声明

6.1 内部通不对用户之间的交流内容承担任何责任。

6.2 因不可抗力或非内部通原因导致的服务中断，内部通不承担责任。

七、协议修改

7.1 内部通有权根据需要修改本协议，修改后的协议将在内部通应用内公布。

7.2 如用户不同意修改后的协议，可以选择停止使用内部通服务。

八、联系方式

如您对本协议有任何疑问，请通过应用内的帮助中心与我们联系。
''';

const _privacyPolicy = '''内部通隐私政策

最近更新日期：2026年4月1日
生效日期：2026年4月1日

内部通非常重视您的个人信息和隐私保护。本隐私政策说明了我们如何收集、使用、共享和保护您的个人信息。

一、我们收集的信息

1.1 注册信息：当您注册内部通账号时，我们会收集您的手机号码、密码和昵称。

1.2 个人资料：您可以选择性地提供您的头像、性别、签名、邮箱等信息。

1.3 通讯数据：为提供即时通讯服务，我们会处理您发送和接收的消息内容。消息采用端到端加密技术保护。

1.4 设备信息：我们会收集您的设备标识符、操作系统版本、设备型号等信息，用于提供安全登录和设备管理功能。

二、信息使用目的

2.1 提供、维护和改进我们的服务。
2.2 验证您的身份，保护账号安全。
2.3 向您发送服务通知和安全提醒。
2.4 预防和处理欺诈、安全问题。

三、信息共享

3.1 我们不会将您的个人信息出售给任何第三方。

3.2 仅在以下情况下，我们可能会共享您的信息：
  - 获得您的明确同意后；
  - 根据法律法规的要求；
  - 为保护内部通及其用户的合法权益。

四、信息存储与安全

4.1 您的个人信息将存储在安全的服务器上，采用行业标准的加密技术保护。

4.2 我们会定期审查信息安全实践，确保您的数据安全。

4.3 我们将在提供服务所需的期限内保留您的信息，超出保留期限后将删除或匿名化处理。

五、您的权利

5.1 您有权访问、更正和删除您的个人信息。
5.2 您有权注销您的内部通账号。
5.3 您有权拒绝或撤回您此前提供的同意。

六、未成年人保护

6.1 我们非常重视未成年人的信息保护。若您是未成年人的监护人，请确保您的未成年子女在您的同意下使用内部通。

七、隐私政策更新

7.1 我们可能会不时更新本隐私政策。更新后的政策将在内部通应用内公布。

八、联系我们

如您对本隐私政策有任何疑问，请通过应用内的帮助中心与我们联系。
''';

const _openSourceLicense = '''内部通开源组件声明

内部通的开发过程中使用了以下优秀的开源项目，在此表示感谢：

前端框架
━━━━━━━━━━━━━━━━━━━━
Flutter (BSD 3-Clause License)
Copyright 2014 The Flutter Authors

Dart (BSD 3-Clause License)
Copyright 2012 The Dart Authors

后端框架
━━━━━━━━━━━━━━━━━━━━
Express.js (MIT License)
Copyright (c) 2009-2014 TJ Holowaychuk

Socket.IO (MIT License)
Copyright (c) 2014-2018 Automattic

数据库
━━━━━━━━━━━━━━━━━━━━
MySQL (GPL v2)
Copyright (c) 2000, 2024, Oracle and/or its affiliates

Knex.js (MIT License)
Copyright (c) 2013-2023 Tim Griesser

核心依赖
━━━━━━━━━━━━━━━━━━━━
Provider (MIT License) - 状态管理
Dio (MIT License) - HTTP 客户端
SharedPreferences (BSD 3-Clause) - 本地存储
QR Flutter (BSD 3-Clause) - 二维码生成
WebRTC (BSD 3-Clause) - 实时通讯
Record (MIT License) - 录音功能

以上所有开源组件均按其各自的开源协议使用。完整的许可证文本请参阅各项目的官方仓库。
''';
