import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/providers/chat_provider.dart';
import 'package:im_client/providers/contacts_provider.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/widgets/user_avatar.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selectedUserIds = <int>{};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contacts = context.read<ContactsProvider>();
      if (contacts.friends.isEmpty) {
        contacts.loadFriends();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String?> _askGroupName() async {
    final controller = TextEditingController(
      text: '新群聊${DateTime.now().millisecondsSinceEpoch % 1000}',
    );

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入群名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(
            hintText: '例如：产品讨论群',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx, name);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  Future<void> _createGroup() async {
    if (_selectedUserIds.isEmpty) {
      AppToast.show(context, '请至少选择 1 位好友');
      return;
    }

    final groupName = await _askGroupName();
    if (!mounted || groupName == null || groupName.trim().isEmpty) return;

    setState(() => _submitting = true);
    try {
      final result = await context.read<ChatProvider>().createGroupConv(
            name: groupName.trim(),
            memberIds: _selectedUserIds.toList(),
          );
      if (!mounted) return;
      Navigator.pop(context, {
        'conversationId': result['conversationId']?.toString(),
        'name': groupName.trim(),
      });
    } catch (e) {
      if (!mounted) return;
      final message = ErrorMessage.from(e, fallback: '创建群聊失败，请稍后重试');
      AppToast.show(context, message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  List<Map<String, dynamic>> _filterFriends(List<Map<String, dynamic>> source) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return source;

    return source.where((f) {
      final nickname = (f['nickname'] ?? '').toString().toLowerCase();
      final remark = (f['remark'] ?? '').toString().toLowerCase();
      final uid = (f['uid'] ?? '').toString().toLowerCase();
      return nickname.contains(q) || remark.contains(q) || uid.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('发起群聊'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _createGroup,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('完成(${_selectedUserIds.length})'),
          ),
        ],
      ),
      body: Consumer<ContactsProvider>(
        builder: (context, contacts, _) {
          final filtered = _filterFriends(contacts.friends);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEDED),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: '搜索好友昵称/备注/UID',
                      prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textLight),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              if (contacts.loading && contacts.friends.isEmpty)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (filtered.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      contacts.friends.isEmpty ? '暂无可选好友' : '没有匹配的好友',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 0.5, indent: 72),
                    itemBuilder: (context, index) {
                      final friend = filtered[index];
                      final userId = friend['userId'] as int?;
                      if (userId == null) return const SizedBox.shrink();
                      final selected = _selectedUserIds.contains(userId);

                      return Material(
                        color: selected ? const Color(0xFFEFF7FF) : Colors.white,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _selectedUserIds.remove(userId);
                              } else {
                                _selectedUserIds.add(userId);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                UserAvatar(
                                  name: friend['remark'] ?? friend['nickname'],
                                  url: friend['avatarUrl'],
                                  size: 44,
                                  radius: 8,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (friend['remark'] ?? friend['nickname'] ?? '未知用户').toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'UID: ${friend['uid'] ?? ''}',
                                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: selected ? AppColors.primary : AppColors.textLight,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
