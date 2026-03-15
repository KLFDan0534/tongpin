import 'package:flutter/material.dart';
import '../../core/services/bundled_music_service.dart';
import '../theme/app_colors.dart';

/// 自带音乐管理面板
/// 显示内置示例音乐列表，支持播放和添加到播放列表
class BundledMusicSheet extends StatefulWidget {
  const BundledMusicSheet({super.key});

  @override
  State<BundledMusicSheet> createState() => _BundledMusicSheetState();
}

class _BundledMusicSheetState extends State<BundledMusicSheet> {
  final BundledMusicService _service = BundledMusicService();
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final tracks = _service.tracks;

    return Container(
      height: screenHeight * 0.6,
      decoration: const BoxDecoration(
        color: AppColors.lightBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 顶部拖拽条
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.lightBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.library_music,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '自带音乐',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.lightTextPrimary,
                    ),
                  ),
                ),
                Text(
                  '${tracks.length} 首',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 内容区域
          Expanded(child: _buildContent(tracks)),
          // 状态提示
          if (_statusMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: AppColors.primary.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(List<BundledMusic> tracks) {
    if (!_service.hasBundledMusic) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return _buildTrackItem(track, index);
      },
    );
  }

  /// 空状态提示
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_note_outlined,
            size: 64,
            color: AppColors.lightTextSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            '暂无自带音乐',
            style: TextStyle(fontSize: 16, color: AppColors.lightTextSecondary),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '将 MP3 文件放入 assets/audio/ 目录\n并在 bundled_music_service.dart 中配置',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.lightTextSecondary.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 查看配置说明按钮
          OutlinedButton.icon(
            onPressed: () => _showConfigGuide(),
            icon: const Icon(Icons.help_outline),
            label: const Text('查看配置说明'),
          ),
        ],
      ),
    );
  }

  /// 音乐条目
  Widget _buildTrackItem(BundledMusic track, int index) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.music_note, color: AppColors.primary),
      ),
      title: Text(
        track.displayName,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          color: AppColors.lightTextPrimary,
        ),
      ),
      subtitle: Text(
        track.artist,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.lightTextSecondary,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.play_circle_outline),
        color: AppColors.primary,
        onPressed: () => _playTrack(track),
      ),
      onTap: () => _showTrackOptions(track),
    );
  }

  /// 播放曲目
  Future<void> _playTrack(BundledMusic track) async {
    setState(() {
      _statusMessage = '正在加载 ${track.displayName}...';
    });

    try {
      final fileName = track.assetPath.split('/').last;
      final localPath = await _service.copyAssetToCache(
        track.assetPath,
        fileName,
      );

      if (localPath != null && mounted) {
        // TODO: 将 localPath 传递给 SyncController 进行播放
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已加载: ${track.displayName}')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _statusMessage = null;
        });
      }
    }
  }

  /// 显示曲目选项
  void _showTrackOptions(BundledMusic track) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('播放'),
              onTap: () {
                Navigator.pop(context);
                _playTrack(track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('添加到播放列表'),
              onTap: () {
                Navigator.pop(context);
                // TODO: 添加到播放列表
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已添加: ${track.displayName}')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('查看详情'),
              onTap: () {
                Navigator.pop(context);
                _showTrackInfo(track);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 显示曲目详情
  void _showTrackInfo(BundledMusic track) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(track.displayName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('艺术家: ${track.artist}'),
            Text('ID: ${track.id}'),
            Text('路径: ${track.assetPath}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 显示配置说明
  void _showConfigGuide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加自带音乐'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1. 将 MP3 文件复制到:'),
              SizedBox(height: 4),
              Text(
                '   assets/audio/',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text('2. 编辑文件:'),
              SizedBox(height: 4),
              Text(
                '   lib/core/services/bundled_music_service.dart',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text('3. 在 bundledTracks 列表中添加:'),
              SizedBox(height: 4),
              Text(
                '   BundledMusic(\n'
                '     id: \'my_track\',\n'
                '     assetPath: \'assets/audio/my_track.mp3\',\n'
                '     displayName: \'我的曲目\',\n'
                '     artist: \'艺术家\',\n'
                '   ),',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              SizedBox(height: 12),
              Text('4. 运行 flutter pub get'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
