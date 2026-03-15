import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 设备数量徽章
/// 显示当前连接的设备数量
class DeviceBadge extends StatelessWidget {
  const DeviceBadge({
    super.key,
    required this.deviceCount,
    this.isDarkMode = true,
  });

  final int deviceCount;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDarkMode ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDarkMode ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final borderColor = isDarkMode ? AppColors.darkBorder : AppColors.lightBorder;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10.5,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.devices_rounded,
            size: 16,
            color: textColor,
          ),
          const SizedBox(width: 6),
          Text(
            '$deviceCount 设备',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
