import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/sync_v2/playback_sync/sync_controller.dart';
import '../../core/services/bundled_music_service.dart';
import '../theme/app_colors.dart';
import 'now_playing_page.dart';

/// 音乐库页面
/// 显示播放列表和曲目管理
/// 使用响应式布局，符合苹果设计准则
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final SyncV2Controller _controller = SyncV2Controller();

  @override
  Widget build(BuildContext context) {
    // 获取屏幕尺寸用于响应式布局
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller.throttledNotifier,
          builder: (context, child) {
            final playlist = _controller.playlist;
            final currentIndex = _controller.currentIndex;
            final bundledService = BundledMusicService();
            final hasBundled = bundledService.hasBundledMusic;

            return Column(
              children: [
                // 顶部标题栏
                _buildHeader(screenWidth),
                // 曲目列表
                Expanded(
                  child: playlist.isEmpty
                      ? _buildEmptyState(screenWidth)
                      : (hasBundled
                            ? _buildCombinedList(
                                playlist,
                                currentIndex,
                                screenWidth,
                              )
                            : _buildTrackList(
                                playlist,
                                currentIndex,
                                screenWidth,
                              )),
                ),
              ],
            );
          },
        ),
      ),
      // 添加音乐按钮
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _selectMusic(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('添加音乐', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  /// 顶部标题栏 - 响应式布局
  Widget _buildHeader(double screenWidth) {
    final buttonSize = screenWidth * 0.09;
    final iconSize = buttonSize * 0.55;
    final paddingH = screenWidth * 0.05;

    return Container(
      padding: EdgeInsets.fromLTRB(
        paddingH,
        screenWidth * 0.04,
        paddingH,
        screenWidth * 0.04,
      ),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border(
          bottom: BorderSide(color: AppColors.lightBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // 返回按钮
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                color: AppColors.lightBackground.withValues(alpha: 0.23),
                borderRadius: BorderRadius.circular(buttonSize / 2),
              ),
              child: Icon(Icons.arrow_back_rounded, size: iconSize),
            ),
          ),
          SizedBox(width: screenWidth * 0.04),
          // 标题
          Expanded(
            child: Text(
              '播放列表',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: screenWidth * 0.04,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 更多按钮
          GestureDetector(
            onTap: () => _showMoreOptions(),
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                color: AppColors.lightBackground.withValues(alpha: 0.23),
                borderRadius: BorderRadius.circular(buttonSize / 2),
              ),
              child: Icon(Icons.more_horiz_rounded, size: iconSize * 0.9),
            ),
          ),
        ],
      ),
    );
  }

  /// 曲目列表 - 响应式布局
  Widget _buildTrackList(List playlist, int currentIndex, double screenWidth) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
      itemCount: playlist.length,
      itemBuilder: (context, index) {
        final track = playlist[index];
        final isCurrentTrack = index == currentIndex;
        final isPlaying = isCurrentTrack && _controller.isPlaying;

        return _buildTrackItem(
          track,
          index,
          isCurrentTrack,
          isPlaying,
          screenWidth,
        );
      },
    );
  }

  /// 组合列表：播放列表 + 自带音乐
  Widget _buildCombinedList(
    List playlist,
    int currentIndex,
    double screenWidth,
  ) {
    final bundledTracks = BundledMusicService().tracks;

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
      children: [
        // 播放列表部分
        if (playlist.isNotEmpty) ...[
          _buildSectionTitle('播放列表 (${playlist.length})', screenWidth),
          ...List.generate(playlist.length, (index) {
            final track = playlist[index];
            final isCurrentTrack = index == currentIndex;
            final isPlaying = isCurrentTrack && _controller.isPlaying;
            return _buildTrackItem(
              track,
              index,
              isCurrentTrack,
              isPlaying,
              screenWidth,
            );
          }),
          SizedBox(height: screenWidth * 0.04),
        ],
        // 自带音乐部分
        if (bundledTracks.isNotEmpty) ...[
          _buildSectionTitle('自带音乐 (${bundledTracks.length})', screenWidth),
          ...List.generate(bundledTracks.length, (index) {
            final track = bundledTracks[index];
            return _buildBundledTrackItem(track, index, screenWidth);
          }),
        ],
      ],
    );
  }

  /// 分区标题
  Widget _buildSectionTitle(String title, double screenWidth) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: screenWidth * 0.03),
      child: Text(
        title,
        style: TextStyle(
          fontSize: screenWidth * 0.035,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }

  /// 曲目项 - 响应式布局
  Widget _buildTrackItem(
    track,
    int index,
    bool isCurrentTrack,
    bool isPlaying,
    double screenWidth,
  ) {
    final iconSize = screenWidth * 0.12;
    final fontSize = screenWidth * 0.035;
    final indexWidth = screenWidth * 0.06;

    return Container(
      margin: EdgeInsets.symmetric(vertical: screenWidth * 0.01),
      decoration: BoxDecoration(
        color: isCurrentTrack
            ? AppColors.primary.withValues(alpha: 0.05)
            : null,
        border: Border(
          bottom: BorderSide(
            color: AppColors.lightBorder.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: 0,
          vertical: screenWidth * 0.02,
        ),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 序号或播放指示
            SizedBox(
              width: indexWidth,
              child: isCurrentTrack
                  ? Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: AppColors.primary,
                      size: fontSize * 1.5,
                    )
                  : Text(
                      '${index + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.lightTextSecondary,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
            SizedBox(width: screenWidth * 0.04),
            // 封面
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: isCurrentTrack
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(iconSize * 0.15),
              ),
              child: Icon(
                Icons.music_note_rounded,
                color: isCurrentTrack
                    ? AppColors.primary
                    : AppColors.lightTextSecondary,
                size: iconSize * 0.5,
              ),
            ),
          ],
        ),
        title: Text(
          _parseTitle(track.fileName),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isCurrentTrack ? FontWeight.w600 : FontWeight.w400,
            color: isCurrentTrack
                ? AppColors.primary
                : AppColors.lightTextPrimary,
            fontSize: fontSize,
          ),
        ),
        subtitle: Text(
          _parseArtist(track.fileName),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.lightTextSecondary,
            fontSize: fontSize * 0.85,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              track.formattedDuration ?? '0:00',
              style: TextStyle(
                color: AppColors.lightTextSecondary,
                fontSize: fontSize * 0.85,
              ),
            ),
            SizedBox(width: screenWidth * 0.04),
            // 当前播放指示
            if (isCurrentTrack)
              Container(
                width: screenWidth * 0.08,
                height: screenWidth * 0.08,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(screenWidth * 0.04),
                ),
                child: Icon(
                  Icons.volume_up_rounded,
                  color: AppColors.primary,
                  size: screenWidth * 0.045,
                ),
              ),
          ],
        ),
        onTap: () => _playTrack(index),
      ),
    );
  }

  /// 空状态 - 响应式布局
  /// 如果有自带音乐，显示自带音乐列表
  Widget _buildEmptyState(double screenWidth) {
    final bundledService = BundledMusicService();
    final bundledTracks = bundledService.tracks;

    // 如果有自带音乐，显示自带音乐列表
    if (bundledService.hasBundledMusic) {
      return _buildBundledMusicList(bundledTracks, screenWidth);
    }

    // 没有自带音乐，显示空状态提示
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music_outlined,
            size: screenWidth * 0.2,
            color: AppColors.lightTextSecondary,
          ),
          SizedBox(height: screenWidth * 0.06),
          Text(
            '播放列表为空',
            style: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.w500,
              color: AppColors.lightTextSecondary,
            ),
          ),
          SizedBox(height: screenWidth * 0.02),
          Text(
            '点击下方按钮添加音乐文件',
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 自带音乐列表
  Widget _buildBundledMusicList(List<BundledMusic> tracks, double screenWidth) {
    return Column(
      children: [
        // 标题栏
        Container(
          padding: EdgeInsets.all(screenWidth * 0.04),
          color: AppColors.primary.withValues(alpha: 0.05),
          child: Row(
            children: [
              Icon(
                Icons.library_music,
                color: AppColors.primary,
                size: screenWidth * 0.05,
              ),
              SizedBox(width: screenWidth * 0.02),
              Expanded(
                child: Text(
                  '自带音乐 (${tracks.length} 首)',
                  style: TextStyle(
                    fontSize: screenWidth * 0.035,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _loadAllBundledMusic(tracks),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('全部添加'),
              ),
            ],
          ),
        ),
        // 曲目列表
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return _buildBundledTrackItem(track, index, screenWidth);
            },
          ),
        ),
      ],
    );
  }

  /// 自带音乐条目
  Widget _buildBundledTrackItem(
    BundledMusic track,
    int index,
    double screenWidth,
  ) {
    final iconSize = screenWidth * 0.12;
    final fontSize = screenWidth * 0.035;

    return Container(
      margin: EdgeInsets.symmetric(vertical: screenWidth * 0.01),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.lightBorder.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: 0,
          vertical: screenWidth * 0.02,
        ),
        leading: Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(iconSize * 0.15),
          ),
          child: Icon(
            Icons.music_note_rounded,
            color: AppColors.primary,
            size: iconSize * 0.5,
          ),
        ),
        title: Text(
          track.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: AppColors.lightTextPrimary,
            fontSize: fontSize,
          ),
        ),
        subtitle: Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.lightTextSecondary,
            fontSize: fontSize * 0.85,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add_circle_outline),
          color: AppColors.primary,
          onPressed: () => _loadBundledTrack(track),
        ),
        onTap: () => _loadBundledTrack(track),
      ),
    );
  }

  /// 加载单首自带音乐到播放列表并播放
  Future<void> _loadBundledTrack(BundledMusic track) async {
    final meta = await BundledMusicService().toTrackMeta(track);
    if (meta != null && mounted) {
      _controller.addToPlaylist(meta);

      // 获取刚添加的曲目索引并播放
      final newIndex = _controller.playlist.length - 1;
      final success = await _controller.playTrackAtIndex(newIndex);

      if (success) {
        // 跳转到播放页面
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const NowPlayingPage()),
        );
      }
      setState(() {});
    }
  }

  /// 加载所有自带音乐到播放列表
  Future<void> _loadAllBundledMusic(List<BundledMusic> tracks) async {
    for (final track in tracks) {
      final meta = await BundledMusicService().toTrackMeta(track);
      if (meta != null) {
        _controller.addToPlaylist(meta);
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  // ========== 业务逻辑方法 ==========

  /// 解析标题 (从文件名)
  String _parseTitle(String? fileName) {
    if (fileName == null || fileName.isEmpty) return '未知曲目';
    final parts = fileName.replaceAll('.mp3', '').split(' - ');
    if (parts.length >= 2) {
      return parts[1]; // 返回标题部分
    }
    return fileName.replaceAll('.mp3', '');
  }

  /// 解析艺术家 (从文件名)
  String _parseArtist(String? fileName) {
    if (fileName == null || fileName.isEmpty) return '未知艺术家';
    final parts = fileName.replaceAll('.mp3', '').split(' - ');
    if (parts.length >= 2) {
      return parts[0]; // 返回艺术家部分
    }
    return '未知艺术家';
  }

  void _playTrack(int index) async {
    debugPrint(
      '[LibraryPage] 点击播放: index=$index, playlist.length=${_controller.playlist.length}',
    );

    final success = await _controller.playTrackAtIndex(index);
    debugPrint('[LibraryPage] 播放结果: $success');

    if (success) {
      // 跳转到播放页面
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const NowPlayingPage()),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('播放失败')));
      }
    }
    setState(() {});
  }

  Future<void> _selectMusic() async {
    try {
      // 检查角色，必须是 host 才能添加音乐
      if (_controller.role != SyncRole.host) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请先创建房间后再添加音乐')));
        }
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'aac', 'm4a', 'wav'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        int successCount = 0;
        for (final file in result.files) {
          if (file.path != null) {
            final success = await _controller.selectMp3File(file.path!);
            if (success) successCount++;
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已添加 $successCount/${result.files.length} 个文件'),
            ),
          );
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择文件失败: $e')));
      }
    }
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('清空播放列表'),
              onTap: () {
                Navigator.pop(context);
                _clearPlaylist();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('播放列表信息'),
              subtitle: Text('共 ${_controller.playlist.length} 首曲目'),
            ),
          ],
        ),
      ),
    );
  }

  void _clearPlaylist() {
    // TODO: 实现清空播放列表功能
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('清空播放列表功能开发中')));
  }
}
