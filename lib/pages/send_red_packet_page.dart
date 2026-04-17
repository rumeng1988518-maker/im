import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';

class SendRedPacketPage extends StatefulWidget {
  final String conversationId;
  const SendRedPacketPage({super.key, required this.conversationId});

  @override
  State<SendRedPacketPage> createState() => _SendRedPacketPageState();
}

class _SendRedPacketPageState extends State<SendRedPacketPage> {
  final _amountController = TextEditingController();
  final _countController = TextEditingController(text: '1');
  final _greetingController = TextEditingController(text: '恭喜发财，大吉大利');
  final _passwordController = TextEditingController();
  int _type = 1; // 1=普通 2=拼手气
  bool _sending = false;

  @override
  void dispose() {
    _amountController.dispose();
    _countController.dispose();
    _greetingController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final amount = double.tryParse(_amountController.text.trim());
    final count = int.tryParse(_countController.text.trim()) ?? 0;
    final password = _passwordController.text.trim();

    if (amount == null || amount <= 0) {
      AppToast.show(context, '请输入有效金额');
      return;
    }
    if (count < 1) {
      AppToast.show(context, '红包个数至少为1');
      return;
    }
    if (password.isEmpty) {
      AppToast.show(context, '请输入支付密码');
      return;
    }

    setState(() => _sending = true);
    try {
      final api = context.read<ApiClient>();
      await api.post('/red-packets', data: {
        'conversationId': widget.conversationId,
        'type': _type,
        'totalAmount': amount.toString(),
        'totalCount': count,
        'greeting': _greetingController.text.trim(),
        'payPassword': password,
      });
      if (!mounted) return;
      AppToast.show(context, '红包已发送');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '发送失败'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发红包'),
        backgroundColor: const Color(0xFFE03131),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Type selector
          Row(
            children: [
              _typeChip('普通红包', 1),
              const SizedBox(width: 12),
              _typeChip('拼手气红包', 2),
            ],
          ),
          const SizedBox(height: 24),
          // Amount
          _field(
            label: _type == 2 ? '总金额 (USDT)' : '单个金额 (USDT)',
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            hint: '0.00',
          ),
          const SizedBox(height: 16),
          // Count
          _field(
            label: '红包个数',
            controller: _countController,
            keyboardType: TextInputType.number,
            hint: '1',
          ),
          const SizedBox(height: 16),
          // Greeting
          _field(
            label: '祝福语',
            controller: _greetingController,
            hint: '恭喜发财，大吉大利',
          ),
          const SizedBox(height: 16),
          // Pay password
          _field(
            label: '支付密码',
            controller: _passwordController,
            obscure: true,
            hint: '请输入支付密码',
          ),
          const SizedBox(height: 32),
          // Send button
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE03131),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_buildAmountLabel()),
            ),
          ),
        ],
      ),
    );
  }

  String _buildAmountLabel() {
    final amount = double.tryParse(_amountController.text.trim());
    final count = int.tryParse(_countController.text.trim()) ?? 1;
    if (amount == null || amount <= 0) return '塞钱进红包';
    final total = _type == 2 ? amount : amount * count;
    return '塞入 ${total.toStringAsFixed(2)} USDT';
  }

  Widget _typeChip(String label, int value) {
    final selected = _type == value;
    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE03131) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? hint,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF9F9F9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE03131))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
