import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/sync_v2/playback_sync/sync_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/album_cover.dart';
import '../widgets/song_info.dart';
import '../widgets/progress_bar.dart';
import '../widgets/play_controls.dart';
import '../widgets/sync_badge.dart';
import '../widgets/device_badge.dart';

/// 正在播放页面 - 全屏播放界面
/// 完全还原 Pencil 设计稿布局
/// 使用响应式布局，符合苹果设计准则
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage>
    with TickerProviderStateMixin {
  final SyncV2Controller _controller = SyncV2Controller();
  bool _isFavorite = false; // MOCK_DATA: 收藏状态本地存储
  Duration? _currentPosition; // 当前播放位置
  Timer? _positionTimer; // 进度更新定时器

  @override
  void initState() {
    super.initState();
    // 使用定时器定期更新进度条（每250ms）
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _controller.isPlaying) {
        setState(() {
          _currentPosition = _controller.position;
        });
      }
    });
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 获取屏幕尺寸用于响应式布局
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    const isDarkMode = false; // 使用浅色模式

    return AnimatedBuilder(
      animation: _controller.throttledNotifier,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: isDarkMode
              ? AppColors.darkBackground
              : AppColors.lightBackground,
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(isDarkMode, screenWidth),
                Expanded(
                  child: _buildContent(isDarkMode, screenWidth, screenHeight),
                ),
                _buildBottomActions(isDarkMode, screenWidth),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 顶部导航栏 - 响应式布局
  Widget _buildHeader(bool isDarkMode, double screenWidth) {
    final buttonSize = screenWidth * 0.1; // 动态按钮大小
    final iconSize = buttonSize * 0.6;
    final paddingH = screenWidth * 0.06;

    return Container(
      padding: EdgeInsets.fromLTRB(
        paddingH,
        screenWidth * 0.04,
        paddingH,
        screenWidth * 0.08,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 关闭按钮
          _buildIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            onTap: () => Navigator.of(context).pop(),
            isDarkMode: isDarkMode,
            size: buttonSize,
            iconSize: iconSize,
          ),
          // 设备数量徽章
          DeviceBadge(
            deviceCount: _controller.peerCount,
            isDarkMode: isDarkMode,
          ),
          // 更多按钮
          _buildIconButton(
            icon: Icons.more_horiz_rounded,
            onTap: () => _showMoreOptions(),
            isDarkMode: isDarkMode,
            size: buttonSize,
            iconSize: iconSize,
          ),
        ],
      ),
    );
  }

  /// 图标按钮 - 响应式尺寸 + 点击动画
  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDarkMode,
    double? size,
    double? iconSize,
  }) {
    final bgColor = isDarkMode ? AppColors.darkSurface : AppColors.lightSurface;
    final fgColor = isDarkMode
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final borderColor = isDarkMode
        ? AppColors.darkBorder
        : AppColors.lightBorder;
    final btnSize = size ?? 40;
    final icSize = iconSize ?? 24;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: 1.0),
      duration: const Duration(milliseconds: 150),
      builder: (context, scale, child) {
        return GestureDetector(
          onTap: onTap,
          onTapDown: (_) => setState(() {}),
          onTapUp: (_) => setState(() {}),
          onTapCancel: () => setState(() {}),
          child: AnimatedScale(
            scale: 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            child: Container(
              width: btnSize,
              height: btnSize,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(btnSize / 2),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Icon(icon, color: fgColor, size: icSize),
            ),
          ),
        );
      },
    );
  }

  /// 主内容区 - 响应式布局
  Widget _buildContent(
    bool isDarkMode,
    double screenWidth,
    double screenHeight,
  ) {
    final trackMeta = _controller.trackState.meta;
    // 专辑封面大小为屏幕宽度的 80%
    final coverSize = screenWidth * 0.8;
    final paddingH = screenWidth * 0.06;

    return SingleChildScrollView(
      child: Column(
        children: [
          // 同步状态徽章
          SyncBadge(
            isConnected: _controller.connectionState.name == 'connected',
            isSynced: _controller.isClockLocked,
            isDarkMode: isDarkMode,
          ),
          SizedBox(height: screenHeight * 0.04),
          // 专辑封面
          AlbumCover(
            coverUrl: null, // MOCK_DATA: 项目未实现封面提取
            size: coverSize,
            isDarkMode: isDarkMode,
          ),
          SizedBox(height: screenHeight * 0.04),
          // 歌曲信息
          Padding(
            padding: EdgeInsets.symmetric(horizontal: paddingH),
            child: SongInfo(
              title: trackMeta?.fileName ?? '未选择歌曲', // 真实数据绑定
              artist: _parseArtist(trackMeta?.fileName), // MOCK_DATA: 解析文件名
              isDarkMode: isDarkMode,
            ),
          ),
          SizedBox(height: screenHeight * 0.03),
          // 进度条
          Padding(
            padding: EdgeInsets.symmetric(horizontal: paddingH),
            child: ProgressBar(
              position: _currentPosition ?? _controller.position,
              duration: _controller.duration,
              isPlaying: _controller.isPlaying,
              isDarkMode: isDarkMode,
              onChanged: (position) => _seekTo(position),
            ),
          ),
          SizedBox(height: screenHeight * 0.04),
          // 播放控制
          PlayControls(
            isPlaying: _controller.isPlaying,
            canPlayPrevious: true, // 始终允许上一首（循环）
            canPlayNext: true, // 始终允许下一首（循环）
            isDarkMode: isDarkMode,
            onPlayPause: () => _togglePlay(),
            onPrevious: () => _previousTrack(),
            onNext: () => _nextTrack(),
          ),
        ],
      ),
    );
  }

  /// 底部操作栏 - 直接放在界面上
  Widget _buildBottomActions(bool isDarkMode, double screenWidth) {
    final paddingH = screenWidth * 0.12;
    final iconSize = screenWidth * 0.065;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        paddingH,
        screenWidth * 0.02,
        paddingH,
        screenWidth * 0.04,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 收藏按钮
          _buildActionButton(
            icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
            isActive: _isFavorite,
            onTap: () => _toggleFavorite(),
            isDarkMode: isDarkMode,
            iconSize: iconSize,
          ),
          // 播放模式按钮
          _buildActionButton(
            icon: _getPlayModeIcon(),
            isActive: true,
            onTap: () => _cyclePlayMode(),
            isDarkMode: isDarkMode,
            iconSize: iconSize,
          ),
          // 追帧按钮
          _buildActionButton(
            icon: Icons.fast_forward_rounded,
            isActive: false,
            onTap: () => _manualCatchUp(),
            isDarkMode: isDarkMode,
            iconSize: iconSize,
          ),
          // 歌单列表按钮
          _buildActionButton(
            icon: Icons.queue_music_rounded,
            isActive: false,
            onTap: () => _showPlaylist(),
            isDarkMode: isDarkMode,
            iconSize: iconSize,
          ),
        ],
      ),
    );
  }

  /// 操作按钮 - 仅图标
  Widget _buildActionButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required bool isDarkMode,
    double? iconSize,
  }) {
    final color = isActive
        ? AppColors.primary
        : (isDarkMode
              ? AppColors.darkTextSecondary
              : AppColors.lightTextSecondary);
    final icSize = iconSize ?? 24;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(icon, color: color, size: icSize),
      ),
    );
  }

  // ========== 业务逻辑方法 ==========

  /// 解析艺术家名称 (从文件名)
  String _parseArtist(String? fileName) {
    if (fileName == null || fileName.isEmpty) return '未知艺术家'; // MOCK_DATA
    // 尝试从文件名解析 "Artist - Title.mp3" 格式
    final parts = fileName.replaceAll('.mp3', '').split(' - ');
    if (parts.length >= 2) {
      return parts[0]; // 返回艺术家部分
    }
    return '未知艺术家'; // MOCK_DATA
  }

  /// 播放/暂停
  void _togglePlay() {
    if (_controller.role.name == 'host') {
      if (_controller.isPlaying) {
        _controller.pauseAndBroadcast();
      } else {
        _controller.resumeAndBroadcast();
      }
    } else {
      // Client 模式下本地控制
      if (_controller.isPlaying) {
        _controller.playerState?.playing ?? false
            ? _controller.pausePlayer()
            : null;
      }
    }
    setState(() {});
  }

  /// 跳转进度
  void _seekTo(Duration position) {
    if (_controller.role.name == 'host') {
      _controller.seekToAndBroadcast(position.inMilliseconds);
    }
    setState(() {});
  }

  /// 上一首（循环播放）
  void _previousTrack() {
    final playlist = _controller.playlist;
    if (playlist.isEmpty) return;

    int newIndex = _controller.currentIndex - 1;
    // 如果是第一首，跳到最后一首
    if (newIndex < 0) {
      newIndex = playlist.length - 1;
    }
    _controller.playTrackAtIndex(newIndex);
    _resetProgress();
    setState(() {});
  }

  /// 下一首（循环播放）
  void _nextTrack() {
    final playlist = _controller.playlist;
    if (playlist.isEmpty) return;

    int newIndex = _controller.currentIndex + 1;
    // 如果是最后一首，跳到第一首
    if (newIndex >= playlist.length) {
      newIndex = 0;
    }
    _controller.playTrackAtIndex(newIndex);
    _resetProgress();
    setState(() {});
  }

  /// 重置进度条
  void _resetProgress() {
    setState(() => _currentPosition = Duration.zero);
  }

  /// 切换收藏状态
  void _toggleFavorite() {
    setState(() => _isFavorite = !_isFavorite);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_isFavorite ? '已添加到收藏' : '已取消收藏')));
    // TODO: 实现收藏持久化
  }

  /// 手动追帧
  void _manualCatchUp() async {
    final success = await _controller.manualCatchUp();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(success ? '追帧成功' : '追帧失败')));
  }

  /// 获取播放模式图标
  IconData _getPlayModeIcon() {
    switch (_controller.playMode) {
      case PlayMode.loop:
        return Icons.repeat_rounded;
      case PlayMode.single:
        return Icons.repeat_one_rounded;
      case PlayMode.shuffle:
        return Icons.shuffle_rounded;
    }
  }

  /// 切换播放模式
  void _cyclePlayMode() {
    final newMode = _controller.cyclePlayMode();
    String modeName;
    switch (newMode) {
      case PlayMode.loop:
        modeName = '列表循环';
        break;
      case PlayMode.single:
        modeName = '单曲循环';
        break;
      case PlayMode.shuffle:
        modeName = '随机播放';
        break;
    }
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('切换到$modeName')));
  }

  /// 显示歌单列表
  void _showPlaylist() {
    final playlist = _controller.playlist;
    final currentIndex = _controller.currentIndex;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.lightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '播放列表',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.lightTextPrimary,
                  ),
                ),
                Text(
                  '${playlist.length} 首',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 歌曲列表
            Flexible(
              child: playlist.isEmpty
                  ? Center(
                      child: Text(
                        '播放列表为空',
                        style: TextStyle(color: AppColors.lightTextSecondary),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: playlist.length,
                      itemBuilder: (context, index) {
                        final track = playlist[index];
                        final isPlaying = index == currentIndex;
                        return ListTile(
                          leading: Icon(
                            isPlaying
                                ? Icons.play_circle_filled
                                : Icons.music_note,
                            color: isPlaying
                                ? AppColors.primary
                                : AppColors.lightTextSecondary,
                          ),
                          title: Text(
                            track.fileName ?? '未知歌曲',
                            style: TextStyle(
                              color: isPlaying
                                  ? AppColors.primary
                                  : AppColors.lightTextPrimary,
                              fontWeight: isPlaying
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            track.formattedDuration,
                            style: TextStyle(
                              color: AppColors.lightTextSecondary,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _controller.playTrackAtIndex(index);
                            setState(() {});
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示同步选项
  void _showSyncOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.lightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.create, color: AppColors.primary),
              title: Text(
                '创建房间',
                style: TextStyle(color: AppColors.lightTextPrimary),
              ),
              subtitle: Text(
                _controller.role.name == 'host' ? '当前: 房主' : '成为房主',
                style: TextStyle(color: AppColors.lightTextSecondary),
              ),
              onTap: () {
                Navigator.pop(context);
                _createRoom();
              },
            ),
            ListTile(
              leading: Icon(Icons.search, color: AppColors.primary),
              title: Text(
                '加入房间',
                style: TextStyle(color: AppColors.lightTextPrimary),
              ),
              subtitle: Text(
                _controller.role.name == 'client' ? '当前: 成员' : '加入其他设备',
                style: TextStyle(color: AppColors.lightTextSecondary),
              ),
              onTap: () {
                Navigator.pop(context);
                // TODO: 跳转到房间发现页面
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 显示更多选项
  void _showMoreOptions() {
    Timer? refreshTimer;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.lightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          // 启动定时器实时刷新
          refreshTimer?.cancel();
          refreshTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
            if (mounted) {
              try {
                setModalState(() {});
              } catch (e) {
                // Modal 已关闭，忽略错误
              }
            }
          });

          // 实时获取延迟信息
          final diag = _controller.diagnostics;
          final rtt = diag.rttMs;
          final jitter = diag.jitterMs;
          final offset = diag.offsetEmaMs;
          final locked = rtt > 0;

          return Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 延迟信息卡片
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.lightBorder),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '网络延迟',
                            style: TextStyle(
                              color: AppColors.lightTextPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            locked ? '$rtt ms' : '-- ms',
                            style: TextStyle(
                              color: locked
                                  ? AppColors.primary
                                  : AppColors.lightTextSecondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '时钟抖动',
                            style: TextStyle(
                              color: AppColors.lightTextPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            locked ? '$jitter ms' : '-- ms',
                            style: TextStyle(
                              color: AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '时钟偏移',
                            style: TextStyle(
                              color: AppColors.lightTextPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            locked ? '$offset ms' : '-- ms',
                            style: TextStyle(
                              color: AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '时钟锁定',
                            style: TextStyle(
                              color: AppColors.lightTextPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Icon(
                            locked ? Icons.lock : Icons.lock_open,
                            color: locked
                                ? Colors.green
                                : AppColors.lightTextSecondary,
                            size: 20,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Icon(Icons.tune, color: AppColors.primary),
                  title: Text(
                    '音频校准',
                    style: TextStyle(color: AppColors.lightTextPrimary),
                  ),
                  onTap: () {
                    refreshTimer?.cancel();
                    Navigator.pop(context);
                    _showCalibrationDialog();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.info_outline, color: AppColors.primary),
                  title: Text(
                    '歌曲信息',
                    style: TextStyle(color: AppColors.lightTextPrimary),
                  ),
                  onTap: () {
                    refreshTimer?.cancel();
                    Navigator.pop(context);
                    _showTrackInfo();
                  },
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      refreshTimer?.cancel();
    });
  }

  /// 显示音频校准弹窗（人耳校准）
  void _showCalibrationDialog() {
    final calibration = _controller.calibration;
    double calibrationOffset = calibration.calibrationOffsetMs.toDouble();
    double latencyComp = calibration.latencyCompMs.toDouble();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppColors.lightCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.lightBorder, width: 1),
            ),
            title: Text(
              '人耳校准',
              style: TextStyle(color: AppColors.lightTextPrimary),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '调整滑条直到耳朵听到的同步为止',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 偏移校准
                  Text(
                    '偏移: ${calibrationOffset.round()}ms',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.lightTextPrimary,
                    ),
                  ),
                  Text(
                    '正值=更晚播放，负值=更早播放',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: () {
                          calibrationOffset = (calibrationOffset - 10).clamp(
                            -300.0,
                            300.0,
                          );
                          _controller.calibration.setCalibrationOffset(
                            calibrationOffset.round(),
                          );
                          setState(() {});
                        },
                      ),
                      Expanded(
                        child: Slider(
                          value: calibrationOffset,
                          min: -300,
                          max: 300,
                          divisions: 600,
                          activeColor: AppColors.primary,
                          label: '${calibrationOffset.round()}ms',
                          onChanged: (value) {
                            calibrationOffset = value;
                            _controller.calibration.setCalibrationOffset(
                              value.round(),
                            );
                            setState(() {});
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: () {
                          calibrationOffset = (calibrationOffset + 10).clamp(
                            -300.0,
                            300.0,
                          );
                          _controller.calibration.setCalibrationOffset(
                            calibrationOffset.round(),
                          );
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 延迟补偿
                  Text(
                    '补偿: ${latencyComp.round()}ms',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.lightTextPrimary,
                    ),
                  ),
                  Text(
                    '网络+音频输出延迟补偿',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: () {
                          latencyComp = (latencyComp - 10).clamp(0.0, 500.0);
                          _controller.calibration.setLatencyComp(
                            latencyComp.round(),
                          );
                          setState(() {});
                        },
                      ),
                      Expanded(
                        child: Slider(
                          value: latencyComp,
                          min: 0,
                          max: 500,
                          divisions: 500,
                          activeColor: AppColors.primary,
                          label: '${latencyComp.round()}ms',
                          onChanged: (value) {
                            latencyComp = value;
                            _controller.calibration.setLatencyComp(
                              value.round(),
                            );
                            setState(() {});
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: () {
                          latencyComp = (latencyComp + 10).clamp(0.0, 500.0);
                          _controller.calibration.setLatencyComp(
                            latencyComp.round(),
                          );
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 总补偿
                  Text(
                    '总补偿: ${calibration.totalCompensationMs}ms',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _controller.calibration.reset();
                  Navigator.pop(context);
                },
                child: Text(
                  '重置',
                  style: TextStyle(color: AppColors.lightTextSecondary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('完成', style: TextStyle(color: AppColors.primary)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 显示歌曲信息
  void _showTrackInfo() {
    final trackMeta = _controller.trackState.meta;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.lightCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.lightBorder, width: 1),
        ),
        title: Text(
          '歌曲信息',
          style: TextStyle(color: AppColors.lightTextPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '文件名: ${trackMeta?.fileName ?? "未知"}',
              style: TextStyle(color: AppColors.lightTextPrimary),
            ),
            Text(
              '时长: ${trackMeta?.formattedDuration ?? "未知"}',
              style: TextStyle(color: AppColors.lightTextPrimary),
            ),
            Text(
              '大小: ${trackMeta?.formattedSize ?? "未知"}',
              style: TextStyle(color: AppColors.lightTextPrimary),
            ),
            Text(
              'ID: ${trackMeta?.trackId ?? "未知"}',
              style: TextStyle(color: AppColors.lightTextSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  /// 创建房间
  Future<void> _createRoom() async {
    // 如果已经在房间中，不重复创建
    if (_controller.role != SyncRole.none) {
      return;
    }
    final success = await _controller.createRoom(roomName: 'SyncTune Room');
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success ? '房间已创建' : '创建房间失败')));
      setState(() {});
    }
  }
}
