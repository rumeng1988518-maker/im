import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/providers/contacts_provider.dart';
import 'package:im_client/providers/chat_provider.dart';
import 'package:im_client/widgets/user_avatar.dart';
import 'package:im_client/pages/chat_page.dart';
import 'package:im_client/pages/chat_user_settings_page.dart';
import 'package:im_client/pages/friend_request_page.dart';
import 'package:im_client/pages/add_friend_page.dart';
import 'package:im_client/pages/group_list_page.dart';
import 'package:im_client/pages/starred_friends_page.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  // Letter index keys for scrolling
  final Map<String, GlobalKey> _sectionKeys = {};

  static const List<String> _indexLetters = [
    '☆', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L',
    'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactsProvider>().loadFriends();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scrollToSection(String letter) {
    final key = _sectionKeys[letter];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(key!.currentContext!, alignment: 0.0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E5E5)),
        ),
        title: const Text('通讯录', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_outlined, size: 22),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddFriendPage())),
          ),
        ],
      ),
      body: Consumer<ContactsProvider>(
        builder: (context, contacts, _) {
          if (contacts.loading && contacts.friends.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final allFriends = contacts.friends;
          final friends = _searchText.isEmpty
              ? allFriends
              : allFriends.where((f) {
                  final name = (f['remark'] ?? f['nickname'] ?? '').toString().toLowerCase();
                  final uid = (f['uid'] ?? '').toString().toLowerCase();
                  final q = _searchText.toLowerCase();
                  return name.contains(q) || uid.contains(q);
                }).toList();

          return Stack(
            children: [
              RefreshIndicator(
                onRefresh: () => contacts.loadFriends(),
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(right: 20),
                  children: [
                    // Search bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDEDED),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: '搜索',
                            hintStyle: TextStyle(color: AppColors.textLight, fontSize: 14),
                            prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textLight),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 14),
                          onChanged: (v) => setState(() => _searchText = v.trim()),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Function items
                    _buildFuncItem(Icons.person_add_alt, const Color(0xFFFA9D3B), '新的朋友',
                      badge: contacts.pendingRequestCount,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendRequestPage()))),
                    _buildDivider(),
                    _buildFuncItem(Icons.people_alt, const Color(0xFF4FC3F7), '群组',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupListPage()))),
                    _buildDivider(),
                    _buildFuncItem(Icons.star_rounded, const Color(0xFFFFC107), '星标好友',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StarredFriendsPage()))),

                    // Friends list with section headers
                    ..._buildFriendSections(friends),

                    // Footer
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '${allFriends.length}位联系人',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Right-side letter index
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: _buildLetterIndex(friends),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLetterIndex(List<Map<String, dynamic>> friends) {
    final existingLetters = <String>{};
    for (final f in friends) {
      final name = (f['remark'] ?? f['nickname'] ?? '').toString();
      existingLetters.add(_getFirstLetter(name));
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _indexLetters.map((letter) {
            final exists = existingLetters.contains(letter);
            return GestureDetector(
              onTap: exists ? () => _scrollToSection(letter) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: exists ? AppColors.textPrimary : AppColors.textLight,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFuncItem(IconData icon, Color color, String label, {required VoidCallback onTap, int badge = 0}) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
              if (badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                  child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      color: Colors.white,
      child: const Divider(height: 0.5, indent: 70, color: Color(0xFFEEEEEE)),
    );
  }

  List<Widget> _buildFriendSections(List<Map<String, dynamic>> friends) {
    _sectionKeys.clear();
    // Group friends by first letter
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final f in friends) {
      final name = (f['remark'] ?? f['nickname'] ?? '').toString();
      final letter = _getFirstLetter(name);
      grouped.putIfAbsent(letter, () => []).add(f);
    }

    final sortedKeys = grouped.keys.toList()..sort((a, b) {
      // ☆ (starred) always first
      if (a == '☆') return -1;
      if (b == '☆') return 1;
      // # always last
      if (a == '#') return 1;
      if (b == '#') return -1;
      return a.compareTo(b);
    });
    final widgets = <Widget>[];

    for (final key in sortedKeys) {
      final sectionKey = GlobalKey();
      _sectionKeys[key] = sectionKey;

      // Section header
      widgets.add(Container(
        key: sectionKey,
        width: double.infinity,
        color: const Color(0xFFF7F7F7),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(key, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
      ));

      final items = grouped[key]!;
      for (int i = 0; i < items.length; i++) {
        widgets.add(_buildFriendTile(items[i]));
        if (i < items.length - 1) widgets.add(_buildDivider());
      }
    }

    return widgets;
  }

  String _getFirstLetter(String name) {
    if (name.isEmpty) return '#';
    final first = name[0].toUpperCase();
    if (RegExp(r'[A-Z]').hasMatch(first)) return first;
    // Simple pinyin first letter mapping for common Chinese surnames
    final charCode = name.codeUnitAt(0);
    if (charCode >= 0x4e00 && charCode <= 0x9fff) {
      // Use Unicode ranges for approximate pinyin grouping
      final pinyinMap = {
        '阿': 'A', '艾': 'A',
        '白': 'B', '柏': 'B', '班': 'B', '包': 'B',
        '陈': 'C', '程': 'C', '成': 'C', '崔': 'C', '曹': 'C',
        '邓': 'D', '丁': 'D', '董': 'D', '杜': 'D',
        '范': 'F', '方': 'F', '冯': 'F', '傅': 'F',
        '高': 'G', '葛': 'G', '龚': 'G', '顾': 'G', '郭': 'G',
        '韩': 'H', '何': 'H', '贺': 'H', '侯': 'H', '胡': 'H', '黄': 'H',
        '贾': 'J', '江': 'J', '蒋': 'J', '金': 'J',
        '康': 'K', '孔': 'K',
        '赖': 'L', '李': 'L', '梁': 'L', '林': 'L', '刘': 'L', '龙': 'L', '卢': 'L', '陆': 'L', '吕': 'L', '罗': 'L',
        '马': 'M', '毛': 'M', '孟': 'M', '苗': 'M',
        '牛': 'N', '聂': 'N',
        '潘': 'P', '彭': 'P',
        '钱': 'Q', '秦': 'Q', '邱': 'Q',
        '任': 'R',
        '沈': 'S', '施': 'S', '石': 'S', '宋': 'S', '孙': 'S', '苏': 'S',
        '谭': 'T', '汤': 'T', '唐': 'T', '田': 'T', '童': 'T',
        '万': 'W', '汪': 'W', '王': 'W', '魏': 'W', '文': 'W', '吴': 'W',
        '夏': 'X', '肖': 'X', '谢': 'X', '熊': 'X', '徐': 'X', '许': 'X', '薛': 'X',
        '严': 'Y', '颜': 'Y', '杨': 'Y', '姚': 'Y', '叶': 'Y', '易': 'Y', '尹': 'Y', '于': 'Y', '余': 'Y', '袁': 'Y',
        '张': 'Z', '赵': 'Z', '郑': 'Z', '钟': 'Z', '周': 'Z', '朱': 'Z', '庄': 'Z', '邹': 'Z',
      };
      final ch = name[0];
      if (pinyinMap.containsKey(ch)) return pinyinMap[ch]!;
    }
    return '#';
  }

  Widget _buildFriendTile(Map<String, dynamic> friend) {
    final nickname = (friend['nickname'] ?? '未知').toString();
    final remark = (friend['remark'] ?? '').toString();
    final displayName = remark.isNotEmpty ? '$nickname（$remark）' : nickname;
    final isBlocked = friend['isBlocked'] == true;
    final isStarred = friend['isStarred'] == true;
    final userId = friend['userId'] as int;

    return Slidable(
      key: ValueKey('friend_$userId'),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.22,
        children: [
          SlidableAction(
            onPressed: (_) => _toggleStar(friend),
            backgroundColor: isStarred ? Colors.grey : const Color(0xFFFFC107),
            foregroundColor: Colors.white,
            icon: isStarred ? Icons.star_outline : Icons.star,
            label: isStarred ? '取消星标' : '星标',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.42,
        children: [
          SlidableAction(
            onPressed: (_) => _confirmBlock(friend),
            backgroundColor: const Color(0xFF9E9E9E),
            foregroundColor: Colors.white,
            icon: isBlocked ? Icons.check_circle_outline : Icons.block,
            label: isBlocked ? '取消拉黑' : '拉黑',
          ),
          SlidableAction(
            onPressed: (_) => _confirmDelete(friend),
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: '删除',
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: () => _openFriendDetail(friend),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                UserAvatar(name: nickname, url: friend['avatarUrl'], size: 40, radius: 6),
                const SizedBox(width: 14),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(displayName, style: const TextStyle(fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (isStarred) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3CD),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('星标', style: TextStyle(fontSize: 10, color: Color(0xFFE6A800))),
                        ),
                      ],
                      if (isBlocked) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('已拉黑', style: TextStyle(fontSize: 10, color: AppColors.danger)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleStar(Map<String, dynamic> friend) async {
    final contacts = context.read<ContactsProvider>();
    final userId = friend['userId'] as int;
    final isStarred = friend['isStarred'] == true;
    try {
      if (isStarred) {
        await contacts.unstarFriend(userId);
        if (mounted) AppToast.show(context, '已取消星标');
      } else {
        await contacts.starFriend(userId);
        if (mounted) AppToast.show(context, '已设为星标好友');
      }
    } catch (e) {
      if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '操作失败'));
    }
  }

  Future<void> _showSwipeActions(Map<String, dynamic> friend) async {
    final userId = friend['userId'] as int;
    final nickname = (friend['nickname'] ?? '').toString();
    final isBlocked = friend['isBlocked'] == true;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isBlocked ? Icons.check_circle_outline : Icons.block, color: const Color(0xFF9E9E9E)),
              title: Text(isBlocked ? '取消拉黑' : '拉黑 $nickname'),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
            const Divider(height: 0.5),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: Text('删除 $nickname', style: const TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const Divider(height: 0.5),
            ListTile(
              title: const Text('取消', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'block') {
      await _confirmBlock(friend);
    } else if (action == 'delete') {
      await _confirmDelete(friend);
    }
  }

  Future<void> _confirmBlock(Map<String, dynamic> friend) async {
    final userId = friend['userId'] as int;
    final nickname = (friend['nickname'] ?? '').toString();
    final isBlocked = friend['isBlocked'] == true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isBlocked ? '取消拉黑' : '拉黑用户'),
        content: Text(isBlocked
            ? '确定取消拉黑 $nickname？取消后对方可以给你发送消息。'
            : '确定拉黑 $nickname？拉黑后你们将无法互相发送消息。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isBlocked ? '确定' : '拉黑', style: TextStyle(color: isBlocked ? AppColors.primary : AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final contacts = context.read<ContactsProvider>();
      if (isBlocked) {
        await contacts.unblockFriend(userId);
        if (mounted) AppToast.show(context, '已取消拉黑');
      } else {
        await contacts.blockFriend(userId);
        if (mounted) AppToast.show(context, '已拉黑');
      }
    } catch (e) {
      if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '操作失败'));
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> friend) async {
    final userId = friend['userId'] as int;
    final nickname = (friend['nickname'] ?? '').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定删除好友 $nickname？删除后将清除聊天记录，且需要重新添加好友。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final contacts = context.read<ContactsProvider>();
      await contacts.deleteFriend(userId);
      if (mounted) AppToast.show(context, '已删除');
    } catch (e) {
      if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '删除失败'));
    }
  }

  Future<void> _openFriendDetail(Map<String, dynamic> friend) async {
    try {
      final chat = context.read<ChatProvider>();
      final conv = await chat.createPrivateConv(friend['userId']);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatUserSettingsPage(
          targetUserId: friend['userId'],
          conversationId: conv['conversationId'].toString(),
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '打开失败'));
    }
  }

  void _showFriendDetail(Map<String, dynamic> friend) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.8,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              UserAvatar(name: friend['nickname'], url: friend['avatarUrl'], size: 72, radius: 16),
              const SizedBox(height: 16),
              Text((friend['remark'] ?? friend['nickname'] ?? '').toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('UID: ${friend['uid'] ?? ''}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 24),
              _detailRow('昵称', (friend['nickname'] ?? '').toString()),
              _detailRow('性别', friend['gender'] == 1 ? '男' : friend['gender'] == 2 ? '女' : '未设置'),
              _detailRow('个性签名', (friend['signature'] ?? '暂无').toString()),
              _detailRow('在线状态', friend['onlineStatus'] == 'online' ? '在线' : '离线'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('发消息'),
                  onPressed: () async {
                    Navigator.pop(context);
                    try {
                      final chat = context.read<ChatProvider>();
                      final conv = await chat.createPrivateConv(friend['userId']);
                      if (!context.mounted) return;
                      if (mounted) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(
                          conversationId: conv['conversationId'].toString(),
                          title: (friend['nickname'] ?? '').toString(),
                        )));
                      }
                    } catch (e) {
                      if (!context.mounted) return;
                      if (mounted) {
                        final message = ErrorMessage.from(e, fallback: '打开会话失败，请稍后重试');
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
