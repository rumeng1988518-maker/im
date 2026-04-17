import 'package:flutter/material.dart';
import 'package:im_client/config/theme.dart';

class UserAvatar extends StatelessWidget {
  final String? name;
  final String? url;
  final double size;
  final double radius;

  const UserAvatar({
    super.key,
    this.name,
    this.url,
    this.size = 42,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          url!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildInitials(),
        ),
      );
    }
    return _buildInitials();
  }

  Widget _buildInitials() {
    final ch = (name ?? '?').isNotEmpty ? name![0] : '?';
    final color = AppColors.avatarColors[ch.codeUnitAt(0) % AppColors.avatarColors.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        ch,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
