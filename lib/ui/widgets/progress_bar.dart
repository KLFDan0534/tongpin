import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 进度条组件
/// 显示播放进度，支持拖拽调整
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.isPlaying,
    this.isDarkMode = true,
    this.onChanged,
  });

  final Duration? position;
  final Duration? duration;
  final bool isPlaying;
  final bool isDarkMode;
  final ValueChanged<Duration>? onChanged;

  @override
  Widget build(BuildContext context) {
    final currentValue = position?.inMilliseconds.toDouble() ?? 0.0;
    final maxValue = duration?.inMilliseconds.toDouble() ?? 1.0;
    final effectiveMax = maxValue > 0 ? maxValue : 1.0;
    // 确保 value 在 [0, max] 范围内
    final clampedValue = currentValue.clamp(0.0, effectiveMax);

    return Column(
      children: [
        // 进度条
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: isDarkMode
                ? AppColors.darkBorder
                : AppColors.lightBorder,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withValues(alpha: 0.2),
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: clampedValue,
            min: 0,
            max: effectiveMax,
            onChanged: (value) {
              onChanged?.call(Duration(milliseconds: value.round()));
            },
          ),
        ),
        const SizedBox(height: 8),
        // 时间标签
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(position),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isDarkMode
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            Text(
              _formatDuration(duration),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isDarkMode
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
