import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/providers/contacts_provider.dart';
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

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _searching = true);
    try {
      final results = await context.read<ContactsProvider>().searchUsers(query);
      if (!mounted) return;
      _results = results;
    } catch (e) {
      if (!mounted) return;
      final message = ErrorMessage.from(e, fallback: '搜索失败，请稍后重试');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    if (mounted) setState(() => _searching = false);
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
                      hintText: '输入手机号或UID搜索',
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
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: UserAvatar(name: user['nickname'], url: user['avatarUrl'], size: 44),
                          title: Text((user['nickname'] ?? '').toString()),
                          subtitle: Text('UID: ${user['uid'] ?? ''}', style: const TextStyle(fontSize: 12)),
                          trailing: ElevatedButton(
                            onPressed: () async {
                              try {
                                final uid = user['id'] ?? user['userId'];
                                await context.read<ContactsProvider>().sendFriendRequest(uid, '请求添加好友');
                                if (!context.mounted) return;
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('好友申请已发送')));
                                }
                              } catch (e) {
                                if (!context.mounted) return;
                                if (mounted) {
                                  final message = ErrorMessage.from(e, fallback: '发送好友申请失败，请稍后重试');
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            child: const Text('添加', style: TextStyle(fontSize: 13)),
                          ),
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
