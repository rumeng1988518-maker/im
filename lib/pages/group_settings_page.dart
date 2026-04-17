import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/utils/clipboard_util.dart';
import 'package:im_client/providers/chat_provider.dart';
import 'package:im_client/providers/contacts_provider.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/widgets/user_avatar.dart';

class GroupSettingsPage extends StatefulWidget {
  final String conversationId;
  const GroupSettingsPage({super.key, required this.conversationId});

  @override
  State<GroupSettingsPage> createState() => _GroupSettingsPageState();
}

class _GroupSettingsPageState extends State<GroupSettingsPage> {
  Map<String, dynamic>? _detail;
  List<dynamic> _members = [];
  bool _loading = true;
  int? _currentUserId;
  bool _isPinned = false;
  bool _isDisturb = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthService>().userId;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiClient>();
      final detail = await api.get('/conversations/${widget.conversationId}');
      final membersResp = await api.get('/conversations/${widget.conversationId}/members', params: {'page': '1', 'pageSize': '200'});
      if (!mounted) return;
      setState(() {
        _detail = detail is Map<String, dynamic> ? detail : {};
        _members = (membersResp is Map && membersResp['list'] is List) ? membersResp['list'] : [];
        _isPinned = _detail?['isPinned'] == true || _detail?['isPinned'] == 1;
        _isDisturb = _detail?['isDisturb'] == true || _detail?['isDisturb'] == 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.show(context, ErrorMessage.from(e, fallback: '加载失败'));
    }
  }

  bool get _isOwner => _detail?['ownerId'] == _currentUserId;
  bool get _isAdmin {
    for (final m in _members) {
      if (m is Map && m['userId'] == _currentUserId && (m['role'] == 1 || m['role'] == 2)) return true;
    }
    return false;
  }

  int get _myRole {
    for (final m in _members) {
      if (m is Map && m['userId'] == _currentUserId) return m['role'] ?? 0;
    }
    return 0;
  }

  String get _myRoleLabel {
    switch (_myRole) {
      case 2: return '群主';
      case 1: return '管理员';
      default: return '成员';
    }
  }

  int get _adminCount => _members.where((m) => m is Map && m['role'] == 1).length;

  Future<void> _editGroupName() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _EditFieldPage(
        title: '修改群名称',
        initialValue: _detail?['name']?.toString() ?? '',
        maxLength: 24,
        hintText: '请输入群名称',
      )),
    );
    if (result == null || !mounted) return;

    try {
      final api = context.read<ApiClient>();
      await api.put('/conversations/${widget.conversationId}', data: {'name': result});
      if (!mounted) return;
      AppToast.show(context, '群名称已更新');
      context.read<ChatProvider>().loadConversations();
      _loadData();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '修改失败'));
    }
  }

  Future<void> _editGroupNotice() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _EditFieldPage(
        title: '群公告',
        initialValue: _detail?['notice']?.toString() ?? '',
        maxLength: 200,
        maxLines: 6,
        hintText: '请输入群公告内容',
      )),
    );
    if (result == null || !mounted) return;

    try {
      final api = context.read<ApiClient>();
      await api.put('/conversations/${widget.conversationId}', data: {'notice': result});
      if (!mounted) return;
      AppToast.show(context, '群公告已更新');
      context.read<ChatProvider>().loadConversations();
      _loadData();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '修改失败'));
    }
  }

  Future<void> _toggleSetting(String field, bool value) async {
    setState(() {
      if (field == 'isPinned') _isPinned = value;
      if (field == 'isDisturb') _isDisturb = value;
    });
    try {
      final api = context.read<ApiClient>();
      await api.put('/conversations/${widget.conversationId}/settings', data: {field: value});
      if (!mounted) return;
      context.read<ChatProvider>().loadConversations();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (field == 'isPinned') _isPinned = !value;
        if (field == 'isDisturb') _isDisturb = !value;
      });
      AppToast.show(context, ErrorMessage.from(e, fallback: '操作失败'));
    }
  }

  void _showAdminManagement() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) {
          final admins = _members.where((m) => m is Map && m['role'] == 1).toList();
          final regulars = _members.where((m) => m is Map && m['role'] == 0).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text('群管理员 (${admins.length}/5)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    GestureDetector(onTap: () => Navigator.pop(ctx), child: const Icon(Icons.close, size: 22)),
                  ],
                ),
              ),
              const Divider(height: 0.5),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    if (admins.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Text('当前管理员', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ),
                      ...admins.map((m) {
                        final nickname = m['nickname']?.toString() ?? '';
                        final avatarUrl = m['avatarUrl']?.toString();
                        return ListTile(
                          leading: UserAvatar(name: nickname, url: avatarUrl, size: 40, radius: 8),
                          title: Text(nickname),
                          trailing: TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _removeAdmin(m['userId'], nickname);
                            },
                            child: const Text('取消', style: TextStyle(color: AppColors.danger, fontSize: 13)),
                          ),
                        );
                      }),
                    ],
                    if (regulars.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Text('普通成员', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ),
                      ...regulars.map((m) {
                        final nickname = m['nickname']?.toString() ?? '';
                        final avatarUrl = m['avatarUrl']?.toString();
                        return ListTile(
                          leading: UserAvatar(name: nickname, url: avatarUrl, size: 40, radius: 8),
                          title: Text(nickname),
                          trailing: admins.length < 5
                              ? TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _setAdmin(m['userId'], nickname);
                                  },
                                  child: const Text('设为管理', style: TextStyle(color: AppColors.primary, fontSize: 13)),
                                )
                              : null,
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _setAdmin(int userId, String nickname) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置管理员'),
        content: Text('确定将 $nickname 设为群管理员？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final api = context.read<ApiClient>();
      await api.post('/conversations/${widget.conversationId}/admin/set', data: {'targetUserId': userId});
      if (!mounted) return;
      AppToast.show(context, '$nickname 已设为管理员');
      _loadData();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '操作失败'));
    }
  }

  Future<void> _removeAdmin(int userId, String nickname) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消管理员'),
        content: Text('确定取消 $nickname 的管理员身份？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final api = context.read<ApiClient>();
      await api.post('/conversations/${widget.conversationId}/admin/remove', data: {'targetUserId': userId});
      if (!mounted) return;
      AppToast.show(context, '已取消 $nickname 的管理员');
      _loadData();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '操作失败'));
    }
  }

  Future<void> _addMembers() async {
    final contacts = context.read<ContactsProvider>();
    if (contacts.friends.isEmpty) await contacts.loadFriends();
    if (!mounted) return;

    final existingIds = _members.map((m) => m is Map ? m['userId'] : null).whereType<int>().toSet();
    final availableFriends = contacts.friends.where((f) => !existingIds.contains(f['userId'])).toList();

    if (availableFriends.isEmpty) {
      AppToast.show(context, '所有好友均已在群中');
      return;
    }

    final selected = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => _AddMemberDialog(friends: availableFriends),
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    try {
      final api = context.read<ApiClient>();
      await api.post('/conversations/${widget.conversationId}/members', data: {'memberIds': selected});
      if (!mounted) return;
      AppToast.show(context, '已添加 ${selected.length} 位成员');
      _loadData();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '添加失败'));
    }
  }

  Future<void> _removeMember(int userId, String nickname) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除成员'),
        content: Text('确定将 $nickname 移出群聊？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final api = context.read<ApiClient>();
      await api.delete('/conversations/${widget.conversationId}/members/$userId');
      if (!mounted) return;
      AppToast.show(context, '已移除');
      _loadData();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '操作失败'));
    }
  }

  Future<void> _transferOwnership() async {
    final candidates = _members.where((m) => m is Map && m['userId'] != _currentUserId).toList();
    if (candidates.isEmpty) return;

    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择新群主'),
        children: candidates.map((m) {
          final nickname = m['nickname']?.toString() ?? '';
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, m['userId'] as int),
            child: Row(
              children: [
                UserAvatar(name: nickname, url: m['avatarUrl']?.toString(), size: 36),
                const SizedBox(width: 12),
                Text(nickname),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (selected == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认转让'),
        content: const Text('转让后你将成为普通成员，确定转让群主？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定转让', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final api = context.read<ApiClient>();
      await api.post('/conversations/${widget.conversationId}/transfer', data: {'targetUserId': selected});
      if (!mounted) return;
      AppToast.show(context, '群主已转让');
      _loadData();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '转让失败'));
    }
  }

  Future<void> _clearMessages() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: const Text('清空后将无法恢复，确定清空？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final api = context.read<ApiClient>();
      await api.delete('/conversations/${widget.conversationId}/messages');
      if (!mounted) return;
      context.read<ChatProvider>().clearLocalMessages(widget.conversationId);
      AppToast.show(context, '聊天记录已清空');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '操作失败'));
    }
  }

  Future<void> _quitGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出群聊'),
        content: const Text('退出后将不再接收该群消息，确定退出？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final api = context.read<ApiClient>();
      await api.post('/conversations/${widget.conversationId}/quit');
      if (!mounted) return;
      context.read<ChatProvider>().loadConversations();
      Navigator.of(context)..pop()..pop();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '退出失败'));
    }
  }

  Future<void> _dismissGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散群聊'),
        content: const Text('解散后所有成员将被移除且无法恢复，确定解散？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解散', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final api = context.read<ApiClient>();
      await api.delete('/conversations/${widget.conversationId}/dismiss');
      if (!mounted) return;
      context.read<ChatProvider>().loadConversations();
      Navigator.of(context)..pop()..pop();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '解散失败'));
    }
  }

  Future<void> _copyGroupId() async {
    final id = widget.conversationId;
    await ClipboardUtil.copy(id);
    if (mounted) AppToast.show(context, '群ID已复制');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text('群聊设置', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child: Divider(height: 0.5, thickness: 0.5, color: Color(0xFFE0E0E0)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 10),
                // Group header card
                _buildGroupHeader(),
                const SizedBox(height: 10),
                // Member grid section
                _buildMemberGridSection(),
                const SizedBox(height: 10),
                // Group info section
                _buildGroupInfoSection(),
                const SizedBox(height: 10),
                // Settings section
                _buildSettingsSection(),
                const SizedBox(height: 10),
                // Owner/admin actions
                if (_isOwner) ...[
                  _buildOwnerSection(),
                  const SizedBox(height: 10),
                ],
                // Danger zone
                _buildDangerSection(),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildGroupHeader() {
    final name = _detail?['name']?.toString() ?? '群聊';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Group avatar
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.people_alt_rounded, size: 32, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          // Group name
          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          // Member count + My role
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${_members.length} 名成员', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _myRole == 2
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : _myRole == 1
                          ? AppColors.warning.withValues(alpha: 0.12)
                          : const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _myRoleLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _myRole == 2 ? AppColors.primary : _myRole == 1 ? AppColors.warning : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMemberGridSection() {
    // Show up to 20 members in grid, plus add button
    final showMembers = _members.take(20).toList();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('群成员', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(width: 6),
              Text('(${_members.length})', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const Spacer(),
              if (_members.length > 20)
                GestureDetector(
                  onTap: () => _showAllMembers(),
                  child: const Row(
                    children: [
                      Text('查看全部', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      Icon(Icons.chevron_right, size: 16, color: AppColors.textSecondary),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 14,
            children: [
              ...showMembers.map((m) => _buildMemberAvatar(m)),
              if (_isAdmin)
                _buildActionAvatar(Icons.add, '邀请', onTap: _addMembers),
              if (_isOwner)
                _buildActionAvatar(Icons.remove, '移除', onTap: () => _showAllMembers(removeMode: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMemberAvatar(dynamic member) {
    if (member is! Map) return const SizedBox.shrink();
    final nickname = member['nickname']?.toString() ?? '';
    final avatarUrl = member['avatarUrl']?.toString();
    final role = member['role'] ?? 0;

    return SizedBox(
      width: 56,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(name: nickname, url: avatarUrl, size: 46, radius: 10),
              if (role == 2)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFC107)),
                  ),
                ),
              if (role == 1)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.shield_rounded, size: 14, color: AppColors.warning),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            nickname,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActionAvatar(IconData icon, String label, {required VoidCallback onTap}) {
    return SizedBox(
      width: 56,
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider, width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildGroupInfoSection() {
    final name = _detail?['name']?.toString() ?? '';
    final notice = _detail?['notice']?.toString();
    final hasNotice = notice != null && notice.isNotEmpty;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildSettingCell(
            icon: Icons.edit_outlined,
            iconColor: AppColors.primary,
            title: '群名称',
            trailing: name,
            onTap: (_isOwner || _isAdmin) ? _editGroupName : null,
          ),
          const Divider(height: 0.5, indent: 56),
          _buildSettingCell(
            icon: Icons.campaign_outlined,
            iconColor: const Color(0xFFE6A800),
            title: '群公告',
            trailing: hasNotice ? '已设置' : '未设置',
            onTap: (_isOwner || _isAdmin) ? _editGroupNotice : null,
          ),
          const Divider(height: 0.5, indent: 56),
          _buildSettingCell(
            icon: Icons.tag,
            iconColor: AppColors.textSecondary,
            title: '群ID',
            trailing: widget.conversationId,
            onTap: _copyGroupId,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildSwitchCell(
            icon: Icons.push_pin_outlined,
            iconColor: const Color(0xFF42A5F5),
            title: '置顶聊天',
            value: _isPinned,
            onChanged: (v) => _toggleSetting('isPinned', v),
          ),
          const Divider(height: 0.5, indent: 56),
          _buildSwitchCell(
            icon: Icons.notifications_off_outlined,
            iconColor: const Color(0xFF9E9E9E),
            title: '消息免打扰',
            subtitle: _isDisturb ? '开启后，将不会接收此群的消息通知' : null,
            value: _isDisturb,
            onChanged: (v) => _toggleSetting('isDisturb', v),
          ),
          const Divider(height: 0.5, indent: 56),
          _buildSettingCell(
            icon: Icons.delete_outline,
            iconColor: AppColors.textSecondary,
            title: '清空聊天记录',
            onTap: _clearMessages,
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerSection() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildSettingCell(
            icon: Icons.shield_outlined,
            iconColor: AppColors.warning,
            title: '群管理员',
            trailing: '$_adminCount / 5',
            onTap: _showAdminManagement,
          ),
          const Divider(height: 0.5, indent: 56),
          _buildSettingCell(
            icon: Icons.swap_horiz_rounded,
            iconColor: const Color(0xFF9C27B0),
            title: '转让群主',
            onTap: _transferOwnership,
          ),
        ],
      ),
    );
  }

  Widget _buildDangerSection() {
    return Container(
      color: Colors.white,
      child: InkWell(
        onTap: _isOwner ? _dismissGroup : _quitGroup,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: Text(
              _isOwner ? '解散群聊' : '退出群聊',
              style: const TextStyle(color: AppColors.danger, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingCell({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 14),
            Text(title, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 12),
            if (trailing != null)
              Expanded(
                child: Text(
                  trailing,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchCell({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  void _showAllMembers({bool removeMode = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    removeMode ? '移除成员' : '全部成员 (${_members.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, size: 22),
                  ),
                ],
              ),
            ),
            const Divider(height: 0.5),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _members.length,
                itemBuilder: (ctx, i) {
                  final m = _members[i];
                  if (m is! Map) return const SizedBox.shrink();
                  final nickname = m['nickname']?.toString() ?? '';
                  final avatarUrl = m['avatarUrl']?.toString();
                  final role = m['role'] ?? 0;
                  final userId = m['userId'];
                  final isMe = userId == _currentUserId;

                  return ListTile(
                    leading: UserAvatar(name: nickname, url: avatarUrl, size: 40, radius: 8),
                    title: Row(
                      children: [
                        Flexible(child: Text(nickname, overflow: TextOverflow.ellipsis)),
                        if (role == 2) ...[
                          const SizedBox(width: 6),
                          _roleBadge('群主', AppColors.primary),
                        ],
                        if (role == 1) ...[
                          const SizedBox(width: 6),
                          _roleBadge('管理员', AppColors.warning),
                        ],
                        if (isMe) ...[
                          const SizedBox(width: 6),
                          const Text('(我)', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ],
                    ),
                    trailing: removeMode && !isMe && role < _myRole
                        ? IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _removeMember(userId, nickname);
                            },
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}

/// Dialog for selecting friends to add to group
class _AddMemberDialog extends StatefulWidget {
  final List<Map<String, dynamic>> friends;
  const _AddMemberDialog({required this.friends});

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择好友'),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView.builder(
          itemCount: widget.friends.length,
          itemBuilder: (_, i) {
            final f = widget.friends[i];
            final id = f['userId'] as int;
            final name = (f['remark'] ?? f['nickname'] ?? '').toString();
            final checked = _selected.contains(id);
            return CheckboxListTile(
              value: checked,
              onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
              title: Row(
                children: [
                  UserAvatar(name: name, url: f['avatarUrl']?.toString(), size: 36, radius: 8),
                  const SizedBox(width: 12),
                  Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                ],
              ),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.primary,
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected.toList()),
          child: Text('确定 (${_selected.length})'),
        ),
      ],
    );
  }
}

/// Full-page field editor for group name / notice
class _EditFieldPage extends StatefulWidget {
  final String title;
  final String initialValue;
  final int maxLength;
  final int maxLines;
  final String hintText;

  const _EditFieldPage({
    required this.title,
    required this.initialValue,
    required this.maxLength,
    this.maxLines = 1,
    required this.hintText,
  });

  @override
  State<_EditFieldPage> createState() => _EditFieldPageState();
}

class _EditFieldPageState extends State<_EditFieldPage> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: () {
                final text = _controller.text.trim();
                Navigator.pop(context, text);
              },
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('保存', style: TextStyle(fontSize: 14)),
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child: Divider(height: 0.5, thickness: 0.5, color: Color(0xFFE0E0E0)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(14),
          child: TextField(
            controller: _controller,
            autofocus: true,
            maxLength: widget.maxLength,
            maxLines: widget.maxLines,
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: const TextStyle(color: AppColors.textLight),
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }
}
