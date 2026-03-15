import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 歌曲信息组件
/// 显示歌曲标题和艺术家名称
class SongInfo extends StatelessWidget {
  const SongInfo({
    super.key,
    required this.title,
    required this.artist,
    this.isDarkMode = true,
  });

  final String title;
  final String artist;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    final primaryColor = isDarkMode ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryColor = isDarkMode ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      children: [
        // 歌曲标题
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: primaryColor,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        // 艺术家名称
        Text(
          artist,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: secondaryColor,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
