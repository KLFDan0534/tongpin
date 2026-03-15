import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../core/sync_v2/playback_sync/sync_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/create_room_card.dart';
import 'now_playing_page.dart';
import 'room_discovery_page.dart';
import 'settings_page.dart';

/// 发现页面 - 首页
/// 包含创建房间、推荐播放列表、最近播放等功能
/// 使用响应式布局，符合苹果设计准则
class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage>
    with SingleTickerProviderStateMixin {
  final SyncV2Controller _controller = SyncV2Controller();
  Duration? _currentPosition; // 当前播放位置
  Timer? _positionTimer; // 进度更新定时器
  AnimationController? _rotationController; // 旋转动画控制器

  @override
  void initState() {
    super.initState();
    // 旋转动画控制器
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12), // 放慢旋转速度
    );
    // 使用定时器定期更新进度（每500ms）
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() {
          _currentPosition = _controller.position;
        });
        // 控制旋转动画
        if (_controller.isPlaying) {
          _rotationController?.repeat();
        } else {
          _rotationController?.stop();
        }
      }
    });
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _rotationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 获取屏幕尺寸用于响应式布局
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      body: SafeArea(
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: _controller.throttledNotifier,
              builder: (context, child) {
                return CustomScrollView(
                  slivers: [
                    _buildHeader(),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.05, // 动态边距
                        ),
                        child: Column(
                          children: [
                            // 创建房间卡片
                            CreateRoomCard(
                              onCreateRoom: () => _createRoom(),
                              onJoinRoom: () => _showJoinRoomDialog(),
                              onLeaveRoom: () => _leaveRoom(),
                              role: _controller.role,
                            ),
                            SizedBox(height: screenHeight * 0.03), // 动态间距
                            // 推荐播放列表
                            _buildRecommendedPlaylists(
                              screenWidth,
                              screenHeight,
                            ),
                            SizedBox(height: screenHeight * 0.03),
                            // 最近播放
                            _buildRecentlyPlayed(),
                            SizedBox(height: screenHeight * 0.15), // 底部悬浮播放器空间
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            // 悬浮迷你播放栏（药丸形状 + 毛玻璃）
            _buildFloatingMiniPlayer(screenWidth),
          ],
        ),
      ),
    );
  }

  /// 顶部标题栏
  Widget _buildHeader() {
    return SliverAppBar(
      floating: true,
      backgroundColor: AppColors.lightBackground,
      elevation: 0,
      title: const Text(
        '同频 SyncTune',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      centerTitle: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => _showSettings(),
        ),
      ],
    );
  }

  /// 推荐播放列表 - 响应式布局
  Widget _buildRecommendedPlaylists(double screenWidth, double screenHeight) {
    // 动态计算卡片尺寸：宽度为屏幕宽度的 40%，高度为宽度的 1.1 倍
    final cardWidth = screenWidth * 0.4;
    final cardHeight = cardWidth * 1.1;
    final cardSpacing = screenWidth * 0.025;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '推荐播放列表',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: screenHeight * 0.02),
        SizedBox(
          height: cardHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildPlaylistCard('流行精选', '50首热门单曲', cardWidth, cardHeight),
              SizedBox(width: cardSpacing),
              _buildPlaylistCard('轻音乐', '放松心情', cardWidth, cardHeight),
              SizedBox(width: cardSpacing),
              _buildPlaylistCard('经典老歌', '回忆经典', cardWidth, cardHeight),
            ],
          ),
        ),
      ],
    );
  }

  /// 播放列表卡片 - 响应式尺寸
  Widget _buildPlaylistCard(
    String title,
    String subtitle,
    double cardWidth,
    double cardHeight,
  ) {
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.lightCard,
          borderRadius: BorderRadius.circular(cardWidth * 0.08), // 动态圆角
          border: Border.all(color: AppColors.lightBorder, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(cardWidth * 0.08),
          child: Column(
            children: [
              // 封面占位 - 使用 Expanded 自动填充剩余空间
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: ColoredBox(
                    color: AppColors.lightSurface,
                    child: Icon(
                      Icons.music_note_rounded,
                      size: cardWidth * 0.25, // 动态图标大小
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ),
              ),
              // 文字信息
              Padding(
                padding: EdgeInsets.all(cardWidth * 0.08), // 动态内边距
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: cardWidth * 0.08, // 动态字体大小
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: cardWidth * 0.065,
                          color: AppColors.lightTextSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 最近播放 - 响应式布局
  Widget _buildRecentlyPlayed() {
    final playlist = _controller.playlist;
    final hasTracks = playlist.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '最近播放',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (hasTracks)
              TextButton(
                onPressed: () => _showAllTracks(),
                child: const Text('查看全部'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (hasTracks)
          Column(
            children: playlist.take(5).map((track) {
              final index = playlist.indexOf(track);
              final isCurrentTrack = index == _controller.currentIndex;
              return _buildTrackItem(track, index, isCurrentTrack);
            }).toList(),
          )
        else
          _buildEmptyState(),
      ],
    );
  }

  /// 曲目项 - 响应式布局
  Widget _buildTrackItem(track, int index, bool isCurrentTrack) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final iconSize = screenWidth * 0.1; // 动态图标大小

    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.02,
        vertical: 4,
      ),
      leading: Container(
        width: iconSize,
        height: iconSize,
        decoration: BoxDecoration(
          color: isCurrentTrack
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(iconSize * 0.15),
        ),
        child: Icon(
          isCurrentTrack ? Icons.play_arrow : Icons.music_note_rounded,
          color: isCurrentTrack
              ? AppColors.primary
              : AppColors.lightTextSecondary,
          size: iconSize * 0.5,
        ),
      ),
      title: Text(
        track.fileName ?? '未知曲目',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isCurrentTrack ? FontWeight.w600 : FontWeight.w400,
          color: isCurrentTrack
              ? AppColors.primary
              : AppColors.lightTextPrimary,
        ),
      ),
      subtitle: Text(
        track.formattedDuration,
        style: TextStyle(color: AppColors.lightTextSecondary),
      ),
      onTap: () => _playTrack(index),
    );
  }

  /// 空状态 - 响应式布局
  Widget _buildEmptyState() {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Container(
      padding: EdgeInsets.all(screenWidth * 0.08),
      child: Column(
        children: [
          Icon(
            Icons.library_music_outlined,
            size: screenWidth * 0.15,
            color: AppColors.lightTextSecondary,
          ),
          SizedBox(height: screenWidth * 0.04),
          Text(
            '暂无播放记录',
            style: TextStyle(
              fontSize: screenWidth * 0.04,
              color: AppColors.lightTextSecondary,
            ),
          ),
          SizedBox(height: screenWidth * 0.02),
          Text(
            '选择音乐文件开始播放',
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 悬浮迷你播放栏 - 药丸形状 + 毛玻璃效果
  Widget _buildFloatingMiniPlayer(double screenWidth) {
    final trackMeta = _controller.trackState.meta;
    if (trackMeta == null) return const SizedBox.shrink();

    final isPlaying = _controller.isPlaying;
    final position = _currentPosition ?? _controller.position ?? Duration.zero;
    final duration = _controller.duration;
    final durationMs = duration?.inMilliseconds ?? 0;
    final progress = durationMs > 0
        ? (position.inMilliseconds / durationMs).clamp(0.0, 1.0)
        : 0.0;

    // 药丸尺寸
    final pillHeight = 64.0;
    final pillWidth = screenWidth * 0.9;
    final iconSize = 36.0;

    return Positioned(
      left: (screenWidth - pillWidth) / 2,
      bottom: MediaQuery.of(context).padding.bottom + 16,
      child: GestureDetector(
        onTap: () => _openNowPlaying(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(pillHeight / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              width: pillWidth,
              height: pillHeight,
              decoration: BoxDecoration(
                // 磨砂玻璃卡片：降低透明度，增加磨砂质感
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(pillHeight / 2),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 进度环图标（播放时旋转）
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: CustomPaint(
                        painter: _ProgressRingPainter(
                          progress: progress,
                          color: AppColors.primary,
                          backgroundColor: AppColors.lightBorder,
                          strokeWidth: 2.5,
                        ),
                        child: Center(
                          child: RotationTransition(
                            turns:
                                _rotationController ??
                                const AlwaysStoppedAnimation(0),
                            child: Icon(
                              Icons.music_note_rounded,
                              color: AppColors.primary,
                              size: iconSize * 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 曲目信息
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trackMeta.fileName ?? '未知曲目',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.lightTextPrimary,
                          ),
                        ),
                        Text(
                          '${_formatDuration(position)} / ${_formatDuration(duration)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 播放/暂停按钮（无背景）
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _togglePlay(),
                      child: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                  ),
                  // 下一首按钮（无背景）
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _nextTrack(),
                      child: Icon(
                        Icons.skip_next_rounded,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ========== 业务逻辑方法 ==========

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 下一首（循环播放）
  void _nextTrack() {
    final playlist = _controller.playlist;
    if (playlist.isEmpty) return;

    int newIndex = _controller.currentIndex + 1;
    if (newIndex >= playlist.length) {
      newIndex = 0;
    }
    _controller.playTrackAtIndex(newIndex);
    setState(() {});
  }

  Future<void> _createRoom() async {
    // 如果已经在房间中，不重复创建
    if (_controller.role != SyncRole.none) {
      return;
    }
    final success = await _controller.createRoom(roomName: 'SyncTune Room');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '房间已创建，ID: ${_controller.roomId}' : '创建房间失败'),
        ),
      );
      setState(() {});
    }
  }

  /// 退出房间
  Future<void> _leaveRoom() async {
    final role = _controller.role;
    if (role == SyncRole.host) {
      await _controller.closeRoom();
    } else if (role == SyncRole.client) {
      await _controller.leaveRoom();
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已退出房间')));
      setState(() {});
    }
  }

  void _showJoinRoomDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.wifi_find),
              title: const Text('自动发现房间'),
              subtitle: const Text('扫描局域网内的 SyncTune 房间'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RoomDiscoveryPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('手动输入 IP'),
              subtitle: const Text('输入房主设备的 IP 地址'),
              onTap: () {
                Navigator.pop(context);
                _showManualJoinDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showManualJoinDialog() {
    final ipController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手动加入房间'),
        content: TextField(
          controller: ipController,
          decoration: const InputDecoration(
            labelText: 'Host IP 地址',
            hintText: '例如: 192.168.1.100',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final result = await _controller.joinByIp(
                ipController.text,
                8765,
              );
              if (mounted) {
                final message = result == true
                    ? '已加入房间'
                    : (result == null ? '已在房间中' : '加入房间失败');
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(message)));
              }
            },
            child: const Text('加入'),
          ),
        ],
      ),
    );
  }

  void _playTrack(int index) {
    _controller.playTrackAtIndex(index);
    setState(() {});
  }

  void _togglePlay() {
    if (_controller.isPlaying) {
      _controller.pauseAndBroadcast();
    } else {
      // 如果没有当前曲目但有播放列表，播放第一首
      if (_controller.currentIndex < 0 && _controller.playlist.isNotEmpty) {
        _controller.playTrackAtIndex(0);
      } else {
        _controller.resumeAndBroadcast();
      }
    }
    setState(() {});
  }

  void _openNowPlaying() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NowPlayingPage()),
    );
  }

  void _showAllTracks() {
    // TODO: 跳转到音乐库页面
  }

  void _showSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
  }
}

/// 进度环绘制器 - 圆形进度条
class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;

  _ProgressRingPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // 背景圆环
    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // 进度圆环
    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * 3.141592653589793 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.141592653589793 / 2, // 从顶部开始
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
