String formatTime(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '';
  final d = DateTime.tryParse(dateStr)?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  final diff = now.difference(d);

  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';

  final today = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(d.year, d.month, d.day);

  if (msgDay == today) return '${_pad(d.hour)}:${_pad(d.minute)}';
  if (today.difference(msgDay).inDays == 1) return '昨天';
  if (d.year == now.year) return '${d.month}/${d.day}';
  return '${d.year}/${d.month}/${d.day}';
}

String formatMsgTime(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '';
  final d = DateTime.tryParse(dateStr)?.toLocal();
  if (d == null) return '';
  return '${_pad(d.hour)}:${_pad(d.minute)}';
}

String _pad(int n) => n < 10 ? '0$n' : '$n';
