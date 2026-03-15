import 'package:flutter/material.dart';
import '../../core/sync_v2/playback_sync/sync_controller.dart';
import '../theme/app_colors.dart';

/// 创建房间卡片
/// 渐变背景的主操作卡片
class CreateRoomCard extends StatelessWidget {
  const CreateRoomCard({
    super.key,
    required this.onCreateRoom,
    required this.onJoinRoom,
    this.onLeaveRoom,
    this.role = SyncRole.none,
  });

  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback? onLeaveRoom;
  final SyncRole role;

  @override
  Widget build(BuildContext context) {
    // 如果已经在房间中，禁用按钮
    final isInRoom = role != SyncRole.none;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: isInRoom ? null : onCreateRoom,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: isInRoom ? null : AppColors.createRoomGradient,
            color: isInRoom ? AppColors.lightSurface : null,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 21,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              // 背景装饰
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 113,
                  height: 113,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // 图标
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isInRoom
                            ? AppColors.lightBorder
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        isInRoom ? Icons.check : Icons.add_rounded,
                        color: isInRoom ? AppColors.primary : Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 文字
                    Expanded(
                      child: Text(
                        isInRoom
                            ? '已${role == SyncRole.host ? '创建' : '加入'}房间'
                            : '创建房间',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isInRoom
                              ? AppColors.lightTextSecondary
                              : Colors.white,
                        ),
                      ),
                    ),
                    // 右侧按钮区域
                    if (isInRoom) ...[
                      // 已连接标签
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.lightBorder,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '已连接',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.lightTextSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 退出房间按钮
                      GestureDetector(
                        onTap: onLeaveRoom,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            '退出',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ),
                    ] else
                      // 加入房间按钮
                      GestureDetector(
                        onTap: onJoinRoom,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            '加入房间',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
