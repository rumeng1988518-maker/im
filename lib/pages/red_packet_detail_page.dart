import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/utils/time_utils.dart';
import 'package:im_client/widgets/user_avatar.dart';

class RedPacketDetailPage extends StatefulWidget {
  final String redPacketId;
  const RedPacketDetailPage({super.key, required this.redPacketId});

  @override
  State<RedPacketDetailPage> createState() => _RedPacketDetailPageState();
}

class _RedPacketDetailPageState extends State<RedPacketDetailPage> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiClient>();
      final data = await api.get('/red-packets/${widget.redPacketId}');
      if (!mounted) return;
      setState(() {
        _detail = data is Map<String, dynamic> ? data : {};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.show(context, ErrorMessage.from(e, fallback: '加载失败'));
    }
  }

  Future<void> _claim() async {
    setState(() => _claiming = true);
    try {
      final api = context.read<ApiClient>();
      await api.post('/red-packets/${widget.redPacketId}/claim');
      if (!mounted) return;
      AppToast.show(context, '领取成功');
      _loadDetail();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '领取失败'));
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = context.read<AuthService>().userId;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        title: const Text('红包详情'),
        backgroundColor: const Color(0xFFE03131),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _detail == null
              ? const Center(child: Text('红包不存在'))
              : _buildContent(myUserId),
    );
  }

  Widget _buildContent(int? myUserId) {
    final d = _detail!;
    final status = d['status'] ?? 0;
    final senderNickname = d['senderNickname']?.toString() ?? '未知';
    final senderAvatar = d['senderAvatarUrl']?.toString();
    final greeting = d['greeting']?.toString() ?? '恭喜发财，大吉大利';
    final totalAmount = double.tryParse(d['totalAmount']?.toString() ?? '0') ?? 0;
    final totalCount = d['totalCount'] ?? 0;
    final claimedCount = d['claimedCount'] ?? 0;
    final claimedAmount = double.tryParse(d['claimedAmount']?.toString() ?? '0') ?? 0;
    final records = (d['records'] is List) ? d['records'] as List : [];
    final isSender = d['senderId'] == myUserId;
    final myClaimed = records.any((r) => r is Map && r['userId'] == myUserId);
    final canClaim = status == 1 && !myClaimed && !isSender;

    return ListView(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE03131), Color(0xFFFA5252)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          child: Column(
            children: [
              UserAvatar(name: senderNickname, url: senderAvatar, size: 56),
              const SizedBox(height: 10),
              Text(
                '$senderNickname的红包',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(greeting, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 16),
              Text(
                '${totalAmount.toStringAsFixed(2)} USDT',
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '已领 $claimedCount/$totalCount 个，共 ${claimedAmount.toStringAsFixed(2)} USDT',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              if (canClaim) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: 180,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _claiming ? null : _claim,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD43B),
                      foregroundColor: const Color(0xFFE03131),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    ),
                    child: _claiming
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('开', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
              if (status == 2)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('红包已领完', style: TextStyle(color: Colors.white60, fontSize: 14)),
                ),
              if (status == 3)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('红包已过期', style: TextStyle(color: Colors.white60, fontSize: 14)),
                ),
            ],
          ),
        ),
        // Records
        if (records.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('领取记录', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          ),
          ...records.map((r) {
            if (r is! Map) return const SizedBox.shrink();
            final nickname = r['nickname']?.toString() ?? '未知';
            final avatar = r['avatarUrl']?.toString();
            final amt = double.tryParse(r['amount']?.toString() ?? '0') ?? 0;
            final isBest = r['isBest'] == true || r['isBest'] == 1;
            final claimedAt = r['claimedAt']?.toString();

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  UserAvatar(name: nickname, url: avatar, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(nickname, style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            if (isBest)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD43B).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('手气最佳', style: TextStyle(fontSize: 10, color: Color(0xFFE03131))),
                              ),
                          ],
                        ),
                        if (claimedAt != null)
                          Text(formatTime(claimedAt), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Text(
                    '${amt.toStringAsFixed(2)} USDT',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 30),
      ],
    );
  }
}
