import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/utils/clipboard_util.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/utils/time_utils.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  Map<String, dynamic>? _wallet;
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiClient>();
      _wallet = Map<String, dynamic>.from(await api.get('/wallet'));
      try {
        final txData = await api.get('/wallet/transactions');
        _transactions = List<Map<String, dynamic>>.from(txData?['list'] ?? txData ?? []);
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        final message = ErrorMessage.from(e, fallback: '加载钱包信息失败，请稍后重试');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('钱包'),
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                children: [
                  // Balance header
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('账户余额 (USDT)', style: TextStyle(color: Colors.white60, fontSize: 14)),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatBalance(_wallet?['balance']),
                              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: 1),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 6, left: 4),
                              child: Text('USDT', style: TextStyle(color: Colors.white60, fontSize: 14)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _actionBtn(Icons.add, '充值', onTap: _showRecharge),
                            _actionBtn(Icons.arrow_upward, '提现', onTap: _showWithdraw),
                            _actionBtn(Icons.lock_outline, '支付密码', onTap: _showPayPassword),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Transactions
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                    child: Text('交易记录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                  ),
                  if (_transactions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 8),
                            Text('暂无交易记录', style: TextStyle(color: Colors.grey[400])),
                          ],
                        ),
                      ),
                    )
                  else
                    ...List.generate(_transactions.length, (i) => _buildTxTile(_transactions[i])),
                ],
              ),
            ),
    );
  }

  Widget _actionBtn(IconData icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  void _showRecharge() async {
    try {
      final api = context.read<ApiClient>();
      final data = await api.get('/wallet/recharge/address');
      if (!mounted) return;
      final address = data is Map ? data['address']?.toString() ?? '' : '';
      final chain = data is Map ? data['chain']?.toString() ?? 'TRC20' : 'TRC20';

      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('充值地址', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('链类型: $chain', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  address.isNotEmpty ? address : '暂无充值地址',
                  style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制地址'),
                  onPressed: () async {
                    if (address.isNotEmpty) {
                      await ClipboardUtil.copy(address);
                      if (context.mounted) AppToast.show(context, '地址已复制');
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '获取充值地址失败'));
    }
  }

  void _showWithdraw() {
    final amountCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final pwdCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('提现', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '提现金额 (USDT)', hintText: '0.00'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressCtrl,
              decoration: const InputDecoration(labelText: '提现地址', hintText: '输入USDT钱包地址'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '支付密码'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text.trim());
                  if (amount == null || amount <= 0) {
                    AppToast.show(context, '请输入有效金额');
                    return;
                  }
                  if (addressCtrl.text.trim().isEmpty) {
                    AppToast.show(context, '请输入提现地址');
                    return;
                  }
                  if (pwdCtrl.text.trim().isEmpty) {
                    AppToast.show(context, '请输入支付密码');
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    final api = context.read<ApiClient>();
                    await api.post('/wallet/withdraw', data: {
                      'amount': amount.toString(),
                      'address': addressCtrl.text.trim(),
                      'payPassword': pwdCtrl.text.trim(),
                    });
                    if (mounted) {
                      AppToast.show(context, '提现申请已提交');
                      _loadData();
                    }
                  } catch (e) {
                    if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '提现失败'));
                  }
                },
                child: const Text('提交申请'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPayPassword() {
    final hasPayPwd = _wallet?['hasPayPassword'] == true;
    if (hasPayPwd) {
      _showChangePayPassword();
    } else {
      _showSetPayPassword();
    }
  }

  void _showSetPayPassword() {
    final pwdCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置支付密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: pwdCtrl, obscureText: true, maxLength: 6, decoration: const InputDecoration(labelText: '支付密码 (6位)', counterText: '')),
            const SizedBox(height: 8),
            TextField(controller: confirmCtrl, obscureText: true, maxLength: 6, decoration: const InputDecoration(labelText: '确认密码', counterText: '')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              if (pwdCtrl.text.length < 6) {
                AppToast.show(context, '密码长度为6位');
                return;
              }
              if (pwdCtrl.text != confirmCtrl.text) {
                AppToast.show(context, '两次密码不一致');
                return;
              }
              Navigator.pop(ctx);
              try {
                final api = context.read<ApiClient>();
                await api.post('/wallet/pay-password', data: {'payPassword': pwdCtrl.text});
                if (mounted) {
                  AppToast.show(context, '支付密码已设置');
                  _loadData();
                }
              } catch (e) {
                if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '设置失败'));
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showChangePayPassword() {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改支付密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: oldCtrl, obscureText: true, maxLength: 6, decoration: const InputDecoration(labelText: '原支付密码', counterText: '')),
            const SizedBox(height: 8),
            TextField(controller: newCtrl, obscureText: true, maxLength: 6, decoration: const InputDecoration(labelText: '新支付密码', counterText: '')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              if (newCtrl.text.length < 6) {
                AppToast.show(context, '密码长度为6位');
                return;
              }
              Navigator.pop(ctx);
              try {
                final api = context.read<ApiClient>();
                await api.put('/wallet/pay-password', data: {'oldPayPassword': oldCtrl.text, 'newPayPassword': newCtrl.text});
                if (mounted) AppToast.show(context, '支付密码已修改');
              } catch (e) {
                if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '修改失败'));
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildTxTile(Map<String, dynamic> tx) {
    final type = tx['type'];
    const typeMap = {1: '充值', 2: '提现', 3: '发红包', 4: '收红包', 5: '转账收入', 6: '转账支出'};
    const iconMap = {1: Icons.add_circle, 2: Icons.arrow_circle_up, 3: Icons.card_giftcard, 4: Icons.card_giftcard, 5: Icons.swap_horiz, 6: Icons.swap_horiz};
    const colorMap = {1: AppColors.primary, 2: AppColors.danger, 3: AppColors.danger, 4: AppColors.primary, 5: AppColors.primary, 6: AppColors.danger};

    final amount = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0;
    final isPositive = amount > 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (colorMap[type] ?? Colors.grey).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(iconMap[type] ?? Icons.swap_horiz, color: colorMap[type] ?? Colors.grey, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(typeMap[type] ?? '其他', style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(formatTime(tx['createdAt']?.toString()), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(
            '${isPositive ? '+' : ''}${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isPositive ? AppColors.primary : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBalance(dynamic balance) {
    final val = double.tryParse(balance?.toString() ?? '0') ?? 0;
    return val.toStringAsFixed(2);
  }
}
