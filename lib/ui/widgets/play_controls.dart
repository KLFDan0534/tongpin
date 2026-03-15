import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 播放控制组件
/// 包含上一首、播放/暂停、下一首按钮
class PlayControls extends StatelessWidget {
  const PlayControls({
    super.key,
    required this.isPlaying,
    this.canPlayPrevious = false,
    this.canPlayNext = false,
    this.isDarkMode = true,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
  });

  final bool isPlaying;
  final bool canPlayPrevious;
  final bool canPlayNext;
  final bool isDarkMode;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 上一首按钮
        _buildControlButton(
          icon: Icons.skip_previous_rounded,
          onTap: canPlayPrevious ? onPrevious : null,
          size: 40,
          iconSize: 28,
        ),
        const SizedBox(width: 44),
        // 播放/暂停按钮 (主按钮)
        _buildPlayPauseButton(),
        const SizedBox(width: 44),
        // 下一首按钮
        _buildControlButton(
          icon: Icons.skip_next_rounded,
          onTap: canPlayNext ? onNext : null,
          size: 40,
          iconSize: 28,
        ),
      ],
    );
  }

  /// 普通控制按钮
  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback? onTap,
    required double size,
    required double iconSize,
  }) {
    final bgColor = isDarkMode ? AppColors.darkSurface : AppColors.lightSurface;
    final fgColor = isDarkMode ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final borderColor = isDarkMode ? AppColors.darkBorder : AppColors.lightBorder;
    final isDisabled = onTap == null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(size / 2),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Icon(
          icon,
          color: isDisabled ? fgColor.withValues(alpha: 0.3) : fgColor,
          size: iconSize,
        ),
      ),
    );
  }

  /// 播放/暂停按钮 (主按钮，带渐变和阴影)
  Widget _buildPlayPauseButton() {
    return GestureDetector(
      onTap: onPlayPause,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(36),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryShadow,
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
          size: 36,
        ),
      ),
    );
  }
}
