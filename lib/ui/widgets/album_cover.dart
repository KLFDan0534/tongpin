import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 专辑封面组件
/// 显示当前播放曲目的封面图片
class AlbumCover extends StatelessWidget {
  const AlbumCover({
    super.key,
    this.coverUrl,
    this.size = 320,
    this.isDarkMode = true,
  });

  final String? coverUrl;
  final double size;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          // 第一层阴影
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
          // 第二层阴影 (绿色光晕)
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.15),
            blurRadius: 42,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _buildCoverImage(),
      ),
    );
  }

  Widget _buildCoverImage() {
    if (coverUrl != null && coverUrl!.isNotEmpty) {
      return Image.network(
        coverUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    // MOCK_DATA: 项目未实现封面提取，使用默认占位图
    final bgColor = isDarkMode ? AppColors.darkSurface : AppColors.lightSurface;
    final iconColor = isDarkMode ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Container(
      color: bgColor,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * 0.4,
          color: iconColor,
        ),
      ),
    );
  }
}
