import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/pages/chat_page.dart';
import 'package:im_client/pages/friend_request_records_page.dart';
import 'package:im_client/providers/chat_provider.dart';
import 'package:im_client/providers/contacts_provider.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/widgets/user_avatar.dart';

class AddFriendPage extends StatefulWidget {
  const AddFriendPage({super.key});

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>>? _results;
  bool _searching = false;
  final Set<int> _pendingSent = {};

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _searching = true);
    try {
      final results = await context.read<ContactsProvider>().searchUsers(query);
      if (!mounted) return;
      final myId = context.read<AuthService>().userId;
      results.removeWhere((u) => u['userId'] == myId);
      _results = results;
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '搜索失败，请稍后重试'));
    }
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _sendRequest(Map<String, dynamic> user) async {
    final targetId = user['userId'] ?? user['id'];
    if (targetId == null) return;
    final id = targetId is int ? targetId : int.parse(targetId.toString());
    try {
      final result = await context.read<ContactsProvider>().sendFriendRequest(id, '请求添加好友');
      if (!mounted) return;
      if (result['directAdded'] == true) {
        AppToast.show(context, '已直接添加为好友');
        await _search();
      } else {
        AppToast.show(context, '好友申请已发送');
        setState(() => _pendingSent.add(id));
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '发送好友申请失败'));
    }
  }

  Future<void> _openChat(Map<String, dynamic> user) async {
    final targetId = user['userId'] ?? user['id'];
    if (targetId == null) return;
    final id = targetId is int ? targetId : int.parse(targetId.toString());
    try {
      final chat = context.read<ChatProvider>();
      final conv = await chat.createPrivateConv(id);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(
        conversationId: conv['conversationId'].toString(),
        title: (user['nickname'] ?? '').toString(),
      )));
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '打开会话失败'));
    }
  }

  Widget _buildActionButton(Map<String, dynamic> user) {
    final targetId = user['userId'] ?? user['id'];
    final id = targetId is int ? targetId : int.parse(targetId.toString());
    final isFriend = user['isFriend'] == true;
    final requestStatus = user['requestStatus'];

    if (isFriend) {
      return ElevatedButton(
        onPressed: () => _openChat(user),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          backgroundColor: AppColors.primary,
        ),
        child: const Text('发消息', style: TextStyle(fontSize: 13)),
      );
    }

    if (_pendingSent.contains(id) || requestStatus == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('等待验证', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
      );
    }

    return ElevatedButton(
      onPressed: () => _sendRequest(user),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: const Text('添加', style: TextStyle(fontSize: 13)),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('添加好友'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendRequestRecordsPage()));
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '输入手机号、UID或邮箱搜索',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _searching ? null : _search,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(64, 48)),
                  child: _searching
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('搜索'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_results != null) ...[
              if (_results!.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('未找到用户', style: TextStyle(color: Colors.grey[400])),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _results!.length,
                    itemBuilder: (context, index) {
                      final user = _results![index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
                        ),
                        child: Row(
                          children: [
                            UserAvatar(name: user['nickname'], url: user['avatarUrl'], size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text((user['nickname'] ?? '').toString(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 2),
                                  Text('UID: ${user['uid'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildActionButton(user),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
