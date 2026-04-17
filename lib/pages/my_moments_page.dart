import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/utils/time_utils.dart';
import 'package:im_client/widgets/user_avatar.dart';

class MyMomentsPage extends StatefulWidget {
  final int userId;

  const MyMomentsPage({super.key, required this.userId});

  @override
  State<MyMomentsPage> createState() => _MyMomentsPageState();
}

class _MyMomentsPageState extends State<MyMomentsPage> {
  List<Map<String, dynamic>> _moments = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  int _total = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMoments();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMoments() async {
    setState(() { _loading = true; _page = 1; });
    try {
      final api = context.read<ApiClient>();
      final data = await api.get('/moments/user/${widget.userId}', params: {'page': '1', 'pageSize': '20'});
      if (!mounted) return;
      setState(() {
        _moments = List<Map<String, dynamic>>.from(data['list'] ?? []);
        _total = data['pagination']?['total'] ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _moments.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final api = context.read<ApiClient>();
      final nextPage = _page + 1;
      final data = await api.get('/moments/user/${widget.userId}', params: {'page': '$nextPage', 'pageSize': '20'});
      if (!mounted) return;
      setState(() {
        _moments.addAll(List<Map<String, dynamic>>.from(data['list'] ?? []));
        _page = nextPage;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _deleteMoment(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除动态'),
        content: const Text('确定删除该条动态？'),
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
      final api = context.read<ApiClient>();
      await api.delete('/moments/${_moments[index]['momentId']}');
      if (!mounted) return;
      setState(() => _moments.removeAt(index));
      AppToast.show(context, '已删除');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '删除失败'));
    }
  }

  String _fullUrl(String url) {
    if (url.startsWith('http')) return url;
    final baseUrl = context.read<ApiClient>().baseUrl;
    final serverUrl = baseUrl.replaceAll('/api/v1', '');
    return '$serverUrl$url';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthService>().userId;
    final isOwn = widget.userId == currentUserId;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(isOwn ? '我的动态' : '他的动态', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _moments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      const Text('暂无动态', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMoments,
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _moments.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _moments.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                        );
                      }
                      return _buildMomentItem(i, isOwn);
                    },
                  ),
                ),
    );
  }

  Widget _buildMomentItem(int index, bool isOwn) {
    final m = _moments[index];
    final media = List<dynamic>.from(m['media'] ?? []);

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 0.5),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name + time + delete
          Row(
            children: [
              UserAvatar(name: m['nickname'], url: m['avatarUrl'], size: 38, radius: 6),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((m['nickname'] ?? '').toString(), style: const TextStyle(color: Color(0xFF576B95), fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(formatTime(m['createdAt']?.toString()), style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                  ],
                ),
              ),
              if (isOwn)
                GestureDetector(
                  onTap: () => _deleteMoment(index),
                  child: const Icon(Icons.delete_outline, size: 18, color: AppColors.textLight),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Text content
          if (m['content'] != null && m['content'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(m['content'].toString(), style: const TextStyle(fontSize: 15, height: 1.4)),
            ),
          // Media grid
          if (media.isNotEmpty) _buildMediaGrid(media),
          // Stats row
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.favorite, size: 14, color: (m['isLiked'] == true) ? AppColors.danger : AppColors.textLight),
                const SizedBox(width: 4),
                Text('${m['likeCount'] ?? 0}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(width: 16),
                const Icon(Icons.chat_bubble_outline, size: 14, color: AppColors.textLight),
                const SizedBox(width: 4),
                Text('${m['commentCount'] ?? 0}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const Spacer(),
                // Visibility badge
                if (m['visibility'] == 1)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, size: 13, color: AppColors.textLight),
                      SizedBox(width: 2),
                      Text('好友可见', style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                    ],
                  )
                else if (m['visibility'] == 2)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 13, color: AppColors.textLight),
                      SizedBox(width: 2),
                      Text('仅自己', style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid(List<dynamic> media) {
    final count = media.length;
    final size = count == 1 ? 200.0 : (count <= 4 ? 120.0 : 90.0);

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: media.map((item) {
        final url = item is Map ? (item['url'] ?? '') : item.toString();
        return GestureDetector(
          onTap: () => _showFullImage(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              _fullUrl(url),
              width: size,
              height: size,
              fit: count == 1 ? BoxFit.contain : BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: size,
                height: size,
                color: const Color(0xFFF0F0F0),
                child: const Icon(Icons.broken_image_outlined, color: AppColors.textLight),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showFullImage(String url) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
        body: Center(
          child: InteractiveViewer(
            child: Image.network(_fullUrl(url), fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }
}
