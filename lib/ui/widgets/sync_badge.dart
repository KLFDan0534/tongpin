import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 同步状态徽章
/// 显示当前同步状态 (SYNCED / SYNCING / OFFLINE)
class SyncBadge extends StatelessWidget {
  const SyncBadge({
    super.key,
    required this.isConnected,
    this.isSynced = false,
    this.isDarkMode = true,
  });

  final bool isConnected;
  final bool isSynced;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    final (text, color) = _getStatusInfo();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.125),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getIcon(),
            size: 11,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color) _getStatusInfo() {
    if (isSynced) {
      return ('已同步', AppColors.success);
    } else if (isConnected) {
      return ('同步中', AppColors.warning);
    } else {
      return ('离线', AppColors.lightTextSecondary);
    }
  }

  IconData _getIcon() {
    if (isSynced) {
      return Icons.sync_rounded;
    } else if (isConnected) {
      return Icons.sync_problem_rounded;
    } else {
      return Icons.sync_disabled_rounded;
    }
  }
}
