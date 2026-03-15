import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/sync_v2/playback_sync/sync_controller.dart';
import '../../core/sync_v2/room_discovery/discovered_room.dart';
import '../../core/sync_v2/transport/transport_interface.dart';
import '../../core/sync_v2/distributor/track_meta.dart';
import '../../core/sync_v2/distributor/audio_cache.dart';
import '../../core/sync_v2/future_start/future_start_controller.dart';
import '../../core/sync_v2/diagnostics/sync_diagnostics.dart';

/// 延迟元素（用于延迟分解面板）
class _LatencyItem {
  final String name;
  final int valueMs;
  final String impact; // high, medium, low, info
  final String description;

  const _LatencyItem({
    required this.name,
    required this.valueMs,
    required this.impact,
    required this.description,
  });
}

/// Sync Lab 页面 - 同步实验室
/// 提供完整的同步测试和诊断功能
class SyncLabPage extends StatefulWidget {
  const SyncLabPage({super.key});

  @override
  State<SyncLabPage> createState() => _SyncLabPageState();
}

class _SyncLabPageState extends State<SyncLabPage> {
  final SyncV2Controller _controller = SyncV2Controller();

  String? _lastExportPath;

  // 手动输入 IP 控制器
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '8765');

  // 延迟校准控制器
  final _latencyController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _latencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Lab / 同步实验室'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: AnimatedBuilder(
        animation: _controller.throttledNotifier,
        builder: (context, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 连接状态区块
              _buildConnectionSection(),
              const Divider(),

              // 角色选择
              _buildRoleSection(),
              const Divider(),

              // 房间控制
              _buildRoomControlSection(),
              const Divider(),

              // 房间列表（Client）
              if (_controller.role == SyncRole.none ||
                  _controller.role == SyncRole.client)
                _buildRoomListSection(),
              const Divider(),

              // 音源控制（Host）
              if (_controller.role == SyncRole.host) _buildAudioSourceSection(),
              const Divider(),

              // Client 曲目卡片
              if (_controller.role == SyncRole.client)
                _buildClientTrackSection(),
              const Divider(),

              // FutureStart 同起开播
              _buildFutureStartSection(),
              const Divider(),

              // 同步控制
              _buildSyncControlSection(),
              const Divider(),

              // 校准按钮
              _buildCalibrationSection(),
              const Divider(),

              // Catch-up 追帧（Client）
              if (_controller.role == SyncRole.client) _buildCatchUpSection(),
              const Divider(),

              // KeepSync 持续同步（Client）
              if (_controller.role == SyncRole.client) _buildKeepSyncSection(),
              const Divider(),

              // 延迟分解面板（Client）
              if (_controller.role == SyncRole.client)
                _buildLatencyBreakdownSection(),
              const Divider(),

              // Clock 区块
              _buildClockSection(),
              const Divider(),

              // 诊断面板
              _buildDiagnosticsPanel(),
            ],
          );
        },
      ),
    );
  }

  /// 连接状态区块
  Widget _buildConnectionSection() {
    final connState = _controller.connectionState;
    final connStateStr = _connectionStateToString(connState);
    final peerCount = _controller.peerCount;
    final diag = _controller.diagnostics;

    // 根据状态选择颜色
    Color stateColor;
    switch (connState) {
      case TransportState.connected:
        stateColor = Colors.green;
        break;
      case TransportState.hosting:
        stateColor = Colors.blue;
        break;
      case TransportState.connecting:
        stateColor = Colors.orange;
        break;
      case TransportState.error:
        stateColor = Colors.red;
        break;
      default:
        stateColor = Colors.grey;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '连接状态',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: stateColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '状态: $connStateStr',
                  style: TextStyle(
                    fontSize: 16,
                    color: stateColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Text('已连接 Peer 数量: $peerCount'),
            Text('心跳 RTT: ${diag.lastPingRtt}ms'),
            Text('重连次数: ${diag.reconnectCount}'),

            // Host 显示本机 IP（热点环境手动输入用）
            if (_controller.role == SyncRole.host) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本机 IP: ${_controller.hostLocalIp}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '端口: 8765',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Text(
                      '热点环境请告知 Client 手动输入此 IP',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // 断开/重连按钮
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Host 关闭房间按钮
                if (_controller.role == SyncRole.host)
                  ElevatedButton.icon(
                    onPressed: connState == TransportState.hosting
                        ? () => _closeRoom()
                        : null,
                    icon: const Icon(Icons.close),
                    label: const Text('关闭房间'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                // Client 重新连接按钮
                if (_controller.role == SyncRole.client)
                  ElevatedButton.icon(
                    onPressed: connState == TransportState.disconnected
                        ? () => _triggerReconnect()
                        : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新连接'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _connectionStateToString(TransportState state) {
    switch (state) {
      case TransportState.disconnected:
        return 'disconnected';
      case TransportState.connecting:
        return 'connecting';
      case TransportState.connected:
        return 'connected';
      case TransportState.hosting:
        return 'hosting';
      case TransportState.error:
        return 'error';
    }
  }

  /// 角色选择区块
  Widget _buildRoleSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '角色选择',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _controller.role == SyncRole.none
                        ? () => _createRoom()
                        : null,
                    icon: const Icon(Icons.router),
                    label: const Text('Host'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _controller.role == SyncRole.none
                        ? () => _startScanning()
                        : null,
                    icon: const Icon(Icons.devices),
                    label: const Text('Client'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('当前角色: ${_controller.role.name}'),
          ],
        ),
      ),
    );
  }

  /// 房间控制区块
  Widget _buildRoomControlSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '房间控制',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_controller.role == SyncRole.host) ...[
              Text('房间 ID: ${_controller.roomId ?? "未创建"}'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => _closeRoom(),
                child: const Text('关闭房间'),
              ),
            ],
            if (_controller.role == SyncRole.client) ...[
              Text('已加入房间: ${_controller.roomId ?? "未加入"}'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => _leaveRoom(),
                child: const Text('离开房间'),
              ),
            ],
            if (_controller.role == SyncRole.none) ...[const Text('请先选择角色')],
          ],
        ),
      ),
    );
  }

  /// 房间列表区块
  Widget _buildRoomListSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '发现的房间',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '提示: 热点环境下 mDNS 可能无法发现，请使用手动输入 IP',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),

            // 扫描按钮
            ElevatedButton.icon(
              onPressed: () => _startScanning(),
              icon: const Icon(Icons.search),
              label: const Text('扫描房间'),
            ),
            const SizedBox(height: 12),

            // 房间列表
            StreamBuilder<List<DiscoveredRoom>>(
              stream: _controller.roomsStream,
              builder: (context, snapshot) {
                final rooms = snapshot.data ?? _controller.discoveredRooms;
                if (rooms.isEmpty) {
                  return const Text('未发现房间');
                }
                return Column(
                  children: rooms
                      .map(
                        (room) => ListTile(
                          title: Text(room.roomName),
                          subtitle: Text('${room.hostIp}:${room.hostWsPort}'),
                          trailing: ElevatedButton(
                            onPressed: () => _joinRoom(room),
                            child: const Text('加入'),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),

            const SizedBox(height: 16),
            const Divider(),
            const Text('手动输入 IP 加入（Fallback）'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'Host IP',
                      hintText: '192.168.1.100',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _portController,
                    decoration: const InputDecoration(
                      labelText: '端口',
                      hintText: '8765',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _joinByIp(),
                  child: const Text('加入'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 音源控制区块（Host）
  Widget _buildAudioSourceSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '音源控制（Host）',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // 选择 MP3 按钮
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _selectMp3File(),
                  icon: const Icon(Icons.audio_file),
                  label: const Text('选择 MP3 文件'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _selectMusicFolder(),
                  icon: const Icon(Icons.folder),
                  label: const Text('选择音乐文件夹'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _selectMp3File(allowMultiple: true),
                  icon: const Icon(Icons.library_music),
                  label: const Text('多选音乐文件'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 曲目状态
            StreamBuilder<TrackState>(
              stream: _controller.trackStateStream,
              initialData: _controller.trackState,
              builder: (context, snapshot) {
                final state = snapshot.data!;
                return _buildTrackStateUI(state);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 构建曲目状态 UI
  Widget _buildTrackStateUI(TrackState state) {
    switch (state.status) {
      case TrackStatus.idle:
        return const Text('当前音源: 未选择');

      case TrackStatus.selecting:
        return const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('选择中...'),
          ],
        );

      case TrackStatus.hashing:
        return const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('计算 Hash 中...'),
          ],
        );

      case TrackStatus.ready:
        final meta = state.meta!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('曲目已就绪:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('trackId: ${meta.trackId}'),
            Text('文件名: ${meta.fileName ?? "未知"}'),
            Text('大小: ${meta.formattedSize}'),
            Text('时长: ${meta.formattedDuration}'),
            Text('Hash: ${meta.fileHash.substring(0, 16)}...'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _startServingTrack(),
              icon: const Icon(Icons.cloud_upload),
              label: const Text('开始分发'),
            ),
          ],
        );

      case TrackStatus.serving:
        final meta = state.meta!;
        return StreamBuilder<Duration>(
          stream: _controller.positionStream,
          builder: (context, snapshot) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '正在分发:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 8),
                Text('trackId: ${meta.trackId}'),
                Text('HTTP 端口: 8787'),
                const SizedBox(height: 8),
                // Host 端进度条
                _buildProgressBar(true),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _stopServingTrack(),
                  icon: const Icon(Icons.stop),
                  label: const Text('停止分发'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            );
          },
        );

      case TrackStatus.error:
        return Text('错误: ${state.error}', style: TextStyle(color: Colors.red));

      default:
        return const Text('未知状态');
    }
  }

  /// Client 曲目卡片区块
  Widget _buildClientTrackSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '曲目缓存（Client）',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // 曲目状态
            StreamBuilder<TrackState>(
              stream: _controller.trackStateStream,
              initialData: _controller.trackState,
              builder: (context, snapshot) {
                final state = snapshot.data!;
                return _buildClientTrackStateUI(state);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 构建 Client 曲目状态 UI
  Widget _buildClientTrackStateUI(TrackState state) {
    switch (state.status) {
      case TrackStatus.idle:
        return const Text('等待曲目公告...');

      case TrackStatus.announcing:
        final meta = state.meta;
        if (meta == null) return const Text('收到公告，准备下载...');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('收到曲目: ${meta.trackId}'),
            Text('大小: ${meta.formattedSize}'),
            const SizedBox(height: 8),
            const Text('准备下载...'),
          ],
        );

      case TrackStatus.selecting:
      case TrackStatus.hashing:
        // Client 端下载中显示进度
        return _buildDownloadProgressUI();

      case TrackStatus.serving:
        // 下载完成，可以播放
        final meta = state.meta!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '缓存完成',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text('trackId: ${meta.trackId}'),
            Text('本地路径: ${meta.localPath}'),
            const SizedBox(height: 12),

            // 播放控制
            _buildPlayerControls(),

            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _clearCache(meta.trackId),
              icon: const Icon(Icons.delete),
              label: const Text('清除缓存'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        );

      case TrackStatus.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('错误: ${state.error}', style: TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _retryDownload(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        );

      default:
        return Text('状态: ${state.status}');
    }
  }

  /// 构建下载进度 UI
  Widget _buildDownloadProgressUI() {
    final progress = _controller.downloadProgress;
    if (progress.status == DownloadStatus.idle) {
      return const Text('下载中...');
    }

    final percent = progress.totalBytes > 0
        ? (progress.progress * 100).toStringAsFixed(1)
        : '0.0';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('下载中: $percent%'),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress.totalBytes > 0 ? progress.progress : null,
        ),
        const SizedBox(height: 8),
        Text(progress.formattedProgress),
        if (progress.status == DownloadStatus.verifying)
          const Text('正在校验 Hash...', style: TextStyle(color: Colors.orange)),
      ],
    );
  }

  /// 构建播放控制 UI
  Widget _buildPlayerControls() {
    final playerState = _controller.playerState;
    final isPlaying = playerState?.playing ?? false;
    final position = _controller.position ?? Duration.zero;
    final duration = _controller.duration ?? Duration.zero;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 播放/暂停按钮
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: isPlaying
                  ? () => _pausePlayer()
                  : () => _resumePlayer(),
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              label: Text(isPlaying ? '暂停' : '播放'),
            ),
            const SizedBox(width: 8),
            if (!isPlaying && duration == Duration.zero)
              ElevatedButton.icon(
                onPressed: () {
                  final meta = _controller.trackState.meta;
                  if (meta != null) {
                    _playCachedFile(meta.localPath);
                  }
                },
                icon: const Icon(Icons.play_circle),
                label: const Text('开始播放'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // 播放进度
        if (duration > Duration.zero)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: duration.inMilliseconds > 0
                    ? position.inMilliseconds / duration.inMilliseconds
                    : 0,
              ),
              const SizedBox(height: 4),
              Text(
                '${_formatDuration(position)} / ${_formatDuration(duration)}',
              ),
            ],
          ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 构建进度条
  Widget _buildProgressBar(bool isHost) {
    final position = _controller.position ?? Duration.zero;
    final duration = _controller.duration ?? Duration.zero;
    final durationMs = duration.inMilliseconds;
    final positionMs = position.inMilliseconds.clamp(0, durationMs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              _formatDuration(position),
              style: const TextStyle(fontSize: 12),
            ),
            Expanded(
              child: Slider(
                value: durationMs > 0 ? positionMs.toDouble() : 0,
                max: durationMs > 0 ? durationMs.toDouble() : 1,
                onChanged: isHost
                    ? (value) {
                        // Host 拖动进度条时广播给 Client
                        _controller.seekToAndBroadcast(value.toInt());
                        setState(() {});
                      }
                    : null, // Client 不能拖动进度条
              ),
            ),
            Text(
              _formatDuration(duration),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        if (isHost)
          Text(
            '拖动进度条可同步调整所有 Client 播放位置',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
      ],
    );
  }

  void _playCachedFile(String localPath) async {
    final success = await _controller.playCachedTrack(localPath);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(success ? '正在播放' : '播放失败')));
    setState(() {});
  }

  void _pausePlayer() async {
    await _controller.pausePlayer();
    if (mounted) setState(() {});
  }

  void _resumePlayer() async {
    await _controller.resumePlayer();
    if (mounted) setState(() {});
  }

  void _clearCache(String trackId) {
    _controller.clearTrackCache(trackId);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已清除缓存: $trackId')));
  }

  void _retryDownload() async {
    final success = await _controller.retryDownload();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(success ? '重试下载成功' : '重试下载失败')));
    setState(() {});
  }

  /// 上一首
  void _previousTrack() async {
    final success = await _controller.previousTrack();
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已切换到上一首 (${_controller.playlistIndex}/${_controller.playlistCount})',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有上一首')));
    }
    setState(() {});
  }

  /// 下一首
  void _nextTrack() async {
    final success = await _controller.nextTrack();
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已切换到下一首 (${_controller.playlistIndex}/${_controller.playlistCount})',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有下一首')));
    }
    setState(() {});
  }

  /// 显示播放列表底部弹窗
  void _showPlaylistSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '播放列表 (${_controller.playlistCount}首)',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      _controller.clearPlaylist();
                      Navigator.pop(context);
                      setState(() {});
                    },
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            const Divider(),
            // 歌曲列表
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _controller.playlistCount,
                itemBuilder: (context, index) {
                  final track = _controller.playlist[index];
                  final isCurrentTrack = index == _controller.currentIndex;
                  final fileName = track.fileName ?? '未知曲目';

                  return ListTile(
                    leading: Icon(
                      isCurrentTrack ? Icons.play_circle : Icons.music_note,
                      color: isCurrentTrack ? Colors.green : null,
                    ),
                    title: Text(
                      fileName,
                      style: TextStyle(
                        fontWeight: isCurrentTrack ? FontWeight.bold : null,
                        color: isCurrentTrack ? Colors.green : null,
                      ),
                    ),
                    subtitle: Text(
                      '${(track.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB • ${track.durationMs ~/ 1000}s',
                    ),
                    trailing: isCurrentTrack
                        ? const Text(
                            '正在播放',
                            style: TextStyle(color: Colors.green),
                          )
                        : null,
                    onTap: () async {
                      if (!isCurrentTrack) {
                        Navigator.pop(context);
                        await _controller.playTrackAtIndex(index);
                        setState(() {});
                      }
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

  /// FutureStart 同起开播区块
  Widget _buildFutureStartSection() {
    // 使用 AnimatedBuilder 监听 throttledNotifier，确保 isPlaying 状态实时更新
    return AnimatedBuilder(
      animation: _controller.throttledNotifier,
      builder: (context, child) {
        final trackState = _controller.trackState;
        final isHost = _controller.role == SyncRole.host;
        final state = _controller.futureStartState;
        final stateStr = state.toString().split('.').last;
        final canStart = _canStartAtFuture(trackState);
        final isPlaying = _controller.isPlaying;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '播放控制',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // leadMs 调节（Host）
                if (isHost) ...[
                  Row(
                    children: [
                      const Text('提前量: '),
                      Expanded(
                        child: Slider(
                          value: _controller.leadMs.toDouble(),
                          min: 800,
                          max: 3000,
                          divisions: 22,
                          label: '${_controller.leadMs}ms',
                          onChanged: (value) {
                            _controller.leadMs = value.toInt();
                            setState(() {});
                          },
                        ),
                      ),
                      Text('${_controller.leadMs}ms'),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // 状态显示
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('状态: $stateStr'),
                    Text('T: ${_controller.startAtRoomTimeMs}'),
                    Text('roomNow: ${_controller.roomNowMs}'),
                    if (state == FutureStartState.waiting)
                      Text(
                        '剩余: ${_controller.startAtRoomTimeMs - _controller.roomNowMs}ms',
                      ),
                    if (state == FutureStartState.started)
                      Text('误差: ${_controller.startErrorMs}ms'),
                    Text(
                      'trackStatus: ${trackState.status.toString().split('.').last}',
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 播放/暂停按钮（Host）
                if (isHost)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 上一首按钮
                      Opacity(
                        opacity: _controller.hasPreviousTrack ? 1.0 : 0.5,
                        child: IconButton(
                          onPressed: _controller.hasPreviousTrack
                              ? () => _previousTrack()
                              : null,
                          icon: const Icon(Icons.skip_previous),
                          tooltip: '上一首',
                        ),
                      ),
                      // 播放/暂停按钮
                      Opacity(
                        opacity: canStart || isPlaying ? 1.0 : 0.5,
                        child: ElevatedButton.icon(
                          onPressed: (canStart || isPlaying)
                              ? _toggleFutureStartOrPause
                              : null,
                          icon: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                          label: Text(isPlaying ? '暂停' : '同起开播'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isPlaying
                                ? Colors.orange
                                : Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      // 下一首按钮
                      Opacity(
                        opacity: _controller.hasNextTrack ? 1.0 : 0.5,
                        child: IconButton(
                          onPressed: _controller.hasNextTrack
                              ? () => _nextTrack()
                              : null,
                          icon: const Icon(Icons.skip_next),
                          tooltip: '下一首',
                        ),
                      ),
                      // 播放列表按钮
                      IconButton(
                        onPressed: _controller.playlistCount > 0
                            ? _showPlaylistSheet
                            : null,
                        icon: const Icon(Icons.queue_music),
                        tooltip: '播放列表 (${_controller.playlistCount})',
                      ),
                    ],
                  ),

                // 进度条（Host 和 Client 都显示）
                if (isHost || _controller.role == SyncRole.client)
                  _buildProgressBar(isHost),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _canStartAtFuture(TrackState trackState) {
    final role = _controller.role;
    final trackStatus = trackState.status;
    // 调试日志
    debugPrint(
      '[SyncLab] _canStartAtFuture: role=$role, trackStatus=$trackStatus',
    );
    if (role != SyncRole.host) return false;
    if (trackStatus != TrackStatus.serving) return false;
    // Host 作为时钟源，不需要检查 isClockLocked
    return true;
  }

  /// 播放/暂停切换（同起开播或暂停）
  void _toggleFutureStartOrPause() async {
    debugPrint(
      '[SyncLab] _toggleFutureStartOrPause called, isPlaying=${_controller.isPlaying}',
    );
    if (_controller.isPlaying) {
      // 暂停并同步给 Client
      debugPrint('[SyncLab] 执行暂停并广播');
      await _controller.pauseAndBroadcast();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已暂停并同步给所有 Client')));
    } else {
      // 检查是否已经播放过（从暂停位置恢复）
      if (_controller.futureStartState == FutureStartState.started) {
        debugPrint('[SyncLab] 执行恢复播放并广播');
        await _controller.resumeAndBroadcast();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已恢复播放并同步给所有 Client')));
      } else {
        // 首次播放，执行同起开播
        debugPrint('[SyncLab] 执行同起开播');
        final success = await _controller.startAtFuture();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success ? '同起开播已发送' : '同起开播失败')));
      }
    }
    setState(() {});
  }

  /// Catch-up 追帧区块（Client）
  Widget _buildCatchUpSection() {
    return StreamBuilder<SyncDiagnosticsData>(
      stream: _controller.diagnosticsStream,
      initialData: _controller.diagnostics,
      builder: (context, snapshot) {
        final diag = snapshot.data!;
        final isClient = _controller.role == SyncRole.client;
        final isClockLocked = _controller.isClockLocked;
        final trackState = _controller.trackState;
        final hasCache =
            trackState.status == TrackStatus.serving &&
            trackState.meta?.localPath.isNotEmpty == true;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Catch-up 追帧',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // 状态显示
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('Host pos: ${diag.lastHostPosMs}ms'),
                    Text('采样时间: ${diag.lastHostStateAtRoomTimeMs}'),
                    Text('目标位置: ${diag.computedTargetPosMs}ms'),
                    Text('追帧差: ${diag.catchUpDeltaMs}ms'),
                    Text('已追帧: ${diag.catchUpPerformed}'),
                    Text('时钟锁定: $isClockLocked'),
                    Text('已缓存: $hasCache'),
                  ],
                ),
                const SizedBox(height: 12),

                // 手动追帧按钮
                if (isClient)
                  Opacity(
                    opacity: (isClockLocked && hasCache) ? 1.0 : 0.5,
                    child: ElevatedButton.icon(
                      onPressed: (isClockLocked && hasCache)
                          ? () => _manualCatchUp()
                          : null,
                      icon: const Icon(Icons.fast_forward),
                      label: const Text('立即追帧'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _manualCatchUp() async {
    final success = await _controller.manualCatchUp();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(success ? '追帧成功' : '追帧失败')));
  }

  /// KeepSync 持续同步区块（Client）
  Widget _buildKeepSyncSection() {
    return StreamBuilder<SyncDiagnosticsData>(
      stream: _controller.diagnosticsStream,
      builder: (context, snapshot) {
        final diag = snapshot.data ?? _controller.diagnostics;
        final isEnabled = diag.keepSyncEnabled;
        final deltaMs = diag.keepSyncDeltaMs;
        final predictedDeltaMs = diag.keepSyncPredictedDeltaMs;
        final speed = diag.keepSyncSpeed;
        final speedEma = diag.keepSyncSpeedEma;
        final speedCmd = diag.keepSyncSpeedCmd;
        final holdRemainingMs = diag.keepSyncHoldRemainingMs;
        final lastAction = diag.keepSyncLastAction;
        final seekCount = diag.keepSyncSeekCount;
        final speedSetCount = diag.keepSyncSpeedSetCount;
        final droppedCount = diag.keepSyncDroppedCount;
        final reason = diag.keepSyncReason ?? '-';
        final latencyCompMs = diag.latencyCompMs;

        // 计算实际听感延迟（Delta + 延迟补偿）
        // 注意：deltaMs 已经减去了 latencyCompMs，所以实际听感延迟 = deltaMs + latencyCompMs
        // 但如果同步正确，deltaMs 应该接近 0，实际听感延迟主要是 latencyCompMs
        // 更准确的计算：实际听感延迟 = |deltaMs| + latencyCompMs（如果 delta 为正表示落后）
        final audibleLatencyMs = deltaMs + latencyCompMs;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'KeepSync 持续同步',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Switch(
                      value: isEnabled,
                      onChanged: (v) => _toggleKeepSync(v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('Delta: ${deltaMs}ms'),
                    Text(
                      '听感延迟: ${audibleLatencyMs}ms',
                      style: TextStyle(
                        color: audibleLatencyMs.abs() > 150
                            ? Colors.red
                            : audibleLatencyMs.abs() > 80
                            ? Colors.orange
                            : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('补偿: ${latencyCompMs}ms'),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('Pred: ${predictedDeltaMs}ms'),
                    Text('Speed: ${speed.toStringAsFixed(3)}'),
                    Text('EMA: ${speedEma.toStringAsFixed(3)}'),
                    Text('Cmd: ${speedCmd.toStringAsFixed(3)}'),
                    if (holdRemainingMs > 0)
                      Text(
                        'HOLD: ${holdRemainingMs}ms',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('Action: $lastAction'),
                    Text('Seeks: $seekCount'),
                    Text('SpeedSets: $speedSetCount'),
                    Text('Dropped: $droppedCount'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Reason: $reason',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                // Delta 指示器（使用预测 delta）
                LinearProgressIndicator(
                  value: (predictedDeltaMs.abs() / 500).clamp(0.0, 1.0),
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation(
                    predictedDeltaMs.abs() <= 30
                        ? Colors.green
                        : predictedDeltaMs.abs() <= 500
                        ? Colors.orange
                        : Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '预测 Delta: |${predictedDeltaMs}ms| ${predictedDeltaMs.abs() <= 30
                      ? "✓ 在死区内"
                      : predictedDeltaMs.abs() <= 500
                      ? "→ 速度调整中"
                      : "⚠ 偏差较大"}',
                  style: TextStyle(
                    color: predictedDeltaMs.abs() <= 30
                        ? Colors.green
                        : predictedDeltaMs.abs() <= 500
                        ? Colors.orange
                        : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleKeepSync(bool enabled) {
    _controller.setKeepSyncEnabled(enabled);
    setState(() {});
  }

  /// 延迟分解面板（Client）- 按影响程度排序
  Widget _buildLatencyBreakdownSection() {
    return StreamBuilder<SyncDiagnosticsData>(
      stream: _controller.diagnosticsStream,
      builder: (context, snapshot) {
        final diag = snapshot.data ?? _controller.diagnostics;

        // 延迟元素（按影响程度排序）
        final latencyItems = <_LatencyItem>[
          _LatencyItem(
            name: 'RTT (网络往返)',
            valueMs: diag.rttMs,
            impact: diag.rttMs > 100
                ? 'high'
                : diag.rttMs > 50
                ? 'medium'
                : 'low',
            description: '网络延迟，影响时钟同步精度',
          ),
          _LatencyItem(
            name: 'Jitter (抖动)',
            valueMs: diag.jitterMs,
            impact: diag.jitterMs > 40
                ? 'high'
                : diag.jitterMs > 20
                ? 'medium'
                : 'low',
            description: '网络不稳定，影响同步稳定性',
          ),
          _LatencyItem(
            name: 'Clock Offset',
            valueMs: diag.offsetEmaMs.abs(),
            impact: diag.offsetEmaMs.abs() > 100
                ? 'high'
                : diag.offsetEmaMs.abs() > 50
                ? 'medium'
                : 'low',
            description: '时钟偏移，影响位置计算',
          ),
          _LatencyItem(
            name: 'Delta (播放偏差)',
            valueMs: diag.keepSyncDeltaMs.abs(),
            impact: diag.keepSyncDeltaMs.abs() > 100
                ? 'high'
                : diag.keepSyncDeltaMs.abs() > 30
                ? 'medium'
                : 'low',
            description: '当前播放位置偏差',
          ),
          _LatencyItem(
            name: 'Predicted Delta',
            valueMs: diag.keepSyncPredictedDeltaMs.abs(),
            impact: diag.keepSyncPredictedDeltaMs.abs() > 100
                ? 'high'
                : diag.keepSyncPredictedDeltaMs.abs() > 30
                ? 'medium'
                : 'low',
            description: '预测的未来偏差',
          ),
          _LatencyItem(
            name: 'Latency Comp',
            valueMs: diag.latencyCompMs,
            impact: 'info',
            description: '手动校准的延迟补偿',
          ),
        ];

        // 按影响程度排序：high > medium > low > info
        final impactOrder = {'high': 0, 'medium': 1, 'low': 2, 'info': 3};
        latencyItems.sort(
          (a, b) => impactOrder[a.impact]!.compareTo(impactOrder[b.impact]!),
        );

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '延迟分解（按影响排序）',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...latencyItems.map((item) => _buildLatencyItemRow(item)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLatencyItemRow(_LatencyItem item) {
    Color valueColor;
    switch (item.impact) {
      case 'high':
        valueColor = Colors.red;
        break;
      case 'medium':
        valueColor = Colors.orange;
        break;
      case 'low':
        valueColor = Colors.green;
        break;
      default:
        valueColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              item.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Container(
            width: 60,
            alignment: Alignment.centerRight,
            child: Text(
              '${item.valueMs}ms',
              style: TextStyle(color: valueColor, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.description,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  /// 同步控制区块
  Widget _buildSyncControlSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '同步控制',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // 说明文字
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '说明：控制 KeepSync 自动追帧功能。\n'
                '• 开始同步：启动自动追帧，Client 会自动调整播放位置对齐 Host\n'
                '• 停止同步：停止自动追帧，Client 不再自动调整\n'
                '与播放控制不同：播放控制控制本地播放器，同步控制控制是否自动对齐。',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _startSync(),
                  icon: const Icon(Icons.sync),
                  label: const Text('开始同步'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _stopSync(),
                  icon: const Icon(Icons.sync_disabled),
                  label: const Text('停止同步'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '当前速度: ${_controller.diagnostics.speedSet.toStringAsFixed(2)}x',
            ),
          ],
        ),
      ),
    );
  }

  /// 校准区块
  Widget _buildCalibrationSection() {
    final calibration = _controller.calibration;
    final calibrationOffset = calibration.calibrationOffsetMs;
    final latencyComp = calibration.latencyCompMs;
    final totalComp = calibration.totalCompensationMs;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '耳朵校准',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '调整滑条直到耳朵听到的同步为止',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),

            if (Platform.isIOS) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [_buildPresetButton('iOS 默认(65/100)', 100, 65)],
              ),
              const SizedBox(height: 12),
            ],

            // 校准偏移滑条 + 精细调节
            Row(
              children: [
                Tooltip(
                  message:
                      '偏移：调整本机播放时间\n正值=让本机更晚播放（延迟）\n负值=让本机更早播放（提前）\n用于补偿音频输出延迟',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('偏移: '),
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                ),
                // 减少 10ms
                IconButton(
                  icon: const Icon(Icons.fast_rewind),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () {
                    _controller.calibration.setCalibrationOffset(
                      calibrationOffset - 10,
                    );
                    setState(() {});
                  },
                ),
                // 减少 1ms
                IconButton(
                  icon: const Icon(Icons.remove),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () {
                    _controller.calibration.setCalibrationOffset(
                      calibrationOffset - 1,
                    );
                    setState(() {});
                  },
                ),
                Expanded(
                  child: Slider(
                    value: calibrationOffset.toDouble(),
                    min: -300,
                    max: 300,
                    divisions: 600,
                    label: '${calibrationOffset}ms',
                    onChanged: (value) {
                      _controller.calibration.setCalibrationOffset(
                        value.round(),
                      );
                      setState(() {});
                    },
                  ),
                ),
                // 增加 1ms
                IconButton(
                  icon: const Icon(Icons.add),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () {
                    _controller.calibration.setCalibrationOffset(
                      calibrationOffset + 1,
                    );
                    setState(() {});
                  },
                ),
                // 增加 10ms
                IconButton(
                  icon: const Icon(Icons.fast_forward),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () {
                    _controller.calibration.setCalibrationOffset(
                      calibrationOffset + 10,
                    );
                    setState(() {});
                  },
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '${calibrationOffset}ms',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '正值=让本机更晚播放，负值=让本机更早播放',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            const SizedBox(height: 12),

            // 延迟补偿滑条 + 精细调节
            Row(
              children: [
                Tooltip(
                  message: '补偿：网络+音频输出延迟补偿\n用于补偿网络传输延迟和音频输出延迟\n让同步更加准确',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('补偿: '),
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                ),
                // 减少 10ms
                IconButton(
                  icon: const Icon(Icons.fast_rewind),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () {
                    _controller.calibration.setLatencyComp(latencyComp - 10);
                    setState(() {});
                  },
                ),
                // 减少 1ms
                IconButton(
                  icon: const Icon(Icons.remove),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () {
                    _controller.calibration.setLatencyComp(latencyComp - 1);
                    setState(() {});
                  },
                ),
                Expanded(
                  child: Slider(
                    value: latencyComp.toDouble(),
                    min: 0,
                    max: 500,
                    divisions: 500,
                    label: '${latencyComp}ms',
                    onChanged: (value) {
                      _controller.calibration.setLatencyComp(value.round());
                      setState(() {});
                    },
                  ),
                ),
                // 增加 1ms
                IconButton(
                  icon: const Icon(Icons.add),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () {
                    _controller.calibration.setLatencyComp(latencyComp + 1);
                    setState(() {});
                  },
                ),
                // 增加 10ms
                IconButton(
                  icon: const Icon(Icons.fast_forward),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () {
                    _controller.calibration.setLatencyComp(latencyComp + 10);
                    setState(() {});
                  },
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '${latencyComp}ms',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 预设值按钮
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPresetButton('有线耳机', 80, 0),
                _buildPresetButton('蓝牙耳机', 150, 0),
                _buildPresetButton('蓝牙+延迟', 200, 50),
              ],
            ),
            const SizedBox(height: 12),

            // 总补偿值
            Row(
              children: [
                Text('总补偿: ${totalComp}ms'),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () {
                    _controller.calibration.reset();
                    setState(() {});
                  },
                  child: const Text('重置'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetButton(
    String label,
    int latencyCompMs,
    int calibrationOffsetMs,
  ) {
    return OutlinedButton(
      onPressed: () {
        _controller.calibration.setLatencyComp(latencyCompMs);
        _controller.calibration.setCalibrationOffset(calibrationOffsetMs);
        setState(() {});
      },
      child: Text(label),
    );
  }

  /// Clock 区块 - 使用 AnimatedBuilder 监听节流通知器
  Widget _buildClockSection() {
    return AnimatedBuilder(
      animation: _controller.throttledNotifier,
      builder: (context, child) {
        final isLocked = _controller.isClockLocked;
        final lockColor = isLocked ? Colors.green : Colors.orange;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '🕐 时钟同步状态',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: lockColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isLocked ? '已锁定 ✓' : '未锁定',
                        style: TextStyle(
                          color: lockColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 时钟数据 - 中文说明
                _buildDiagRowWithTooltip(
                  '往返延迟 (RTT)',
                  '${_controller.rttMs} ms',
                  'ping 消息从 Client 到 Host 再返回的总时间',
                ),
                _buildDiagRowWithTooltip(
                  '原始偏移',
                  '${_controller.offsetRawMs} ms',
                  '单次测量得到的客户端与服务器时间差',
                ),
                _buildDiagRowWithTooltip(
                  '平滑偏移 (EMA)',
                  '${_controller.offsetEmaMs} ms',
                  '使用指数移动平均平滑后的时间偏移，更稳定',
                ),
                _buildDiagRowWithTooltip(
                  '网络抖动 (Jitter)',
                  '${_controller.jitterMs} ms',
                  'RTT 的变化幅度，反映网络稳定性',
                ),
                _buildDiagRowWithTooltip(
                  '采样次数',
                  '${_controller.clockSampleCount}',
                  '已收集的有效时钟同步样本数量',
                ),

                const Divider(),
                const Text(
                  '样本过滤统计',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),

                _buildDiagRowWithTooltip(
                  '丢弃样本数',
                  '${_controller.diagnostics.droppedSamplesCount}',
                  '因 RTT 过高或 offset 跳跃过大而被丢弃的样本数',
                ),
                _buildDiagRowWithTooltip(
                  '最近丢弃原因',
                  _controller.diagnostics.lastDroppedReason ?? '-',
                  '最近一次样本被丢弃的原因',
                ),
                _buildDiagRowWithTooltip(
                  '最近合格 RTT',
                  '${_controller.diagnostics.lastGoodRttMs} ms',
                  '最近通过过滤的样本的 RTT 值',
                ),

                const Divider(),
                const Text(
                  'EMA 平滑系数调整',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                const Text(
                  'α 越小越平滑（响应慢），越大越灵敏（噪声多）',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),

                // Alpha 滑条
                Row(
                  children: [
                    const Text('0.05'),
                    Expanded(
                      child: Slider(
                        value: _controller.emaAlpha.clamp(0.05, 0.3),
                        min: 0.05,
                        max: 0.3,
                        divisions: 25,
                        label: _controller.emaAlpha.toStringAsFixed(2),
                        onChanged: (value) {
                          _controller.setEmaAlpha(value);
                        },
                      ),
                    ),
                    const Text('0.30'),
                  ],
                ),
                Text('当前 α = ${_controller.emaAlpha.toStringAsFixed(2)}'),

                const SizedBox(height: 12),

                // 重置按钮
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _resetClock(keepHistory: false),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重置时钟'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _resetClock(keepHistory: true),
                      icon: const Icon(Icons.history),
                      label: const Text('保留历史重置'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建带说明的诊断行
  Widget _buildDiagRowWithTooltip(String label, String value, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 14)),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  void _resetClock({required bool keepHistory}) {
    _controller.resetClock(keepHistory: keepHistory);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Clock 已重置 (keepHistory=$keepHistory)')),
      );
      setState(() {});
    }
  }

  /// 诊断面板 - 使用 AnimatedBuilder 监听节流通知器
  Widget _buildDiagnosticsPanel() {
    return AnimatedBuilder(
      animation: _controller.throttledNotifier,
      builder: (context, child) {
        final diag = _controller.diagnostics;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📊 诊断面板',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _copyDebugBundle(),
                      icon: const Icon(Icons.copy),
                      label: const Text('复制日志'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _exportDebugBundle(),
                      icon: const Icon(Icons.upload_file),
                      label: const Text('导出日志'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _clearDebugLogs(),
                      icon: const Icon(Icons.delete),
                      label: const Text('清空日志'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    if (Platform.isIOS)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('iOS 安全模式'),
                          Switch(
                            value: _controller.isIosSafeMode,
                            onChanged: (v) {
                              _controller.setIosSafeMode(v);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                  ],
                ),

                if (_lastExportPath != null) ...[
                  const SizedBox(height: 8),
                  _buildDiagRowWithTooltip(
                    '导出路径',
                    _lastExportPath!,
                    'debug bundle 已写入临时目录，可复制路径从设备取出',
                  ),
                ],

                // 状态信息
                _buildDiagRowWithTooltip('状态', diag.state, '当前同步状态机状态'),
                _buildDiagRowWithTooltip(
                  '角色',
                  diag.role,
                  '当前设备角色 (host/client/none)',
                ),
                _buildDiagRowWithTooltip(
                  '房间 ID',
                  diag.roomId ?? '-',
                  '当前所在房间标识',
                ),
                _buildDiagRowWithTooltip(
                  '设备 ID',
                  diag.peerId ?? '-',
                  '本设备在网络中的唯一标识',
                ),

                const Divider(),
                const Text(
                  '🕐 时钟同步',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                _buildDiagRowWithTooltip(
                  '房间时间',
                  '${diag.roomNowMs} ms',
                  '同步后的房间统一时间戳',
                ),
                _buildDiagRowWithTooltip('往返延迟', '${diag.rttMs} ms', '网络往返时间'),
                _buildDiagRowWithTooltip(
                  '时间偏移',
                  '${diag.offsetEmaMs} ms',
                  '客户端与服务器的时间差',
                ),
                _buildDiagRowWithTooltip(
                  '网络抖动',
                  '${diag.jitterMs} ms',
                  '延迟变化幅度',
                ),

                const Divider(),
                const Text(
                  '🎵 播放位置',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                _buildDiagRowWithTooltip(
                  'Host 位置',
                  '${diag.hostPosMs} ms',
                  'Host 当前播放位置',
                ),
                _buildDiagRowWithTooltip(
                  'Client 位置',
                  '${diag.clientPosMs} ms',
                  'Client 当前播放位置',
                ),
                _buildDiagRowWithTooltip(
                  '延迟补偿',
                  '${diag.latencyCompMs} ms',
                  '人为设置的延迟补偿值',
                ),

                const Divider(),
                const Text(
                  '⚙️ 同步控制',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                _buildDiagRowWithTooltip(
                  '位置差',
                  '${diag.deltaMs} ms',
                  'Client 与 Host 的播放位置差距',
                ),
                _buildDiagRowWithTooltip(
                  '播放速度',
                  diag.speedSet.toStringAsFixed(3),
                  '为追赶/等待而调整的播放速度',
                ),
                _buildDiagRowWithTooltip(
                  '是否 Seek',
                  diag.seekPerformed.toString(),
                  '是否执行了跳转操作',
                ),
                _buildDiagRowWithTooltip(
                  '上次 Seek',
                  diag.lastSeekAt?.toString() ?? '-',
                  '最近一次跳转的时间',
                ),

                if (diag.errorMessage != null) ...[
                  const Divider(),
                  Text(
                    '❌ 错误: ${diag.errorMessage}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ========== 操作方法 ==========

  Future<void> _createRoom() async {
    // 如果已经在房间中，不重复创建
    if (_controller.role != SyncRole.none) {
      return;
    }
    final success = await _controller.createRoom(roomName: 'Test Room');
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success ? '房间已创建' : '创建房间失败')));
      setState(() {});
    }
  }

  Future<void> _closeRoom() async {
    await _controller.closeRoom();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _startScanning() async {
    await _controller.startScanning();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _joinRoom(DiscoveredRoom room) async {
    // 加入房间前先停止扫描
    await _controller.stopScanning();
    final result = await _controller.joinRoom(room);
    if (mounted) {
      final message = result == true
          ? '已加入房间'
          : (result == null ? '已在房间中' : '加入房间失败');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      setState(() {});
    }
  }

  Future<void> _joinByIp() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text) ?? 8765;

    if (ip.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 Host IP')));
      return;
    }

    // 加入房间前先停止扫描
    await _controller.stopScanning();
    final result = await _controller.joinByIp(ip, port);
    if (mounted) {
      final message = result == true
          ? '已加入房间'
          : (result == null ? '已在房间中' : '加入房间失败');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      setState(() {});
    }
  }

  Future<void> _leaveRoom() async {
    await _controller.leaveRoom();
    if (mounted) {
      setState(() {});
    }
  }

  /// 选择 MP3 文件（使用 file_picker，支持多选）
  Future<void> _selectMp3File({bool allowMultiple = true}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'aac', 'm4a', 'wav'],
        allowMultiple: allowMultiple,
      );

      if (result != null && result.files.isNotEmpty) {
        // 直接批量处理选中的文件
        int successCount = 0;
        for (final file in result.files) {
          final success = await _processSelectedFile(file);
          if (success) successCount++;
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

  /// 处理单个选中的文件
  Future<bool> _processSelectedFile(PlatformFile file) async {
    String? filePath = file.path;

    // Android: 处理 content:// URI，需要复制到缓存目录
    if (filePath != null && filePath.startsWith('content://')) {
      debugPrint('[SyncLab] Android content URI: $filePath');
      filePath = await _copyContentUriToCache(filePath, file.name);
      if (filePath == null) {
        return false;
      }
    }

    if (filePath != null) {
      return await _controller.selectMp3File(filePath);
    }
    return false;
  }

  /// 将 Android content:// URI 文件复制到缓存目录
  Future<String?> _copyContentUriToCache(
    String contentUri,
    String fileName,
  ) async {
    try {
      // 使用 MethodChannel 读取 content:// URI
      const channel = MethodChannel('com.example.sync_music/content_resolver');

      final bytes = await channel.invokeMethod<Uint8List>('readContentUri', {
        'uri': contentUri,
      });

      if (bytes == null) {
        debugPrint('[SyncLab] Failed to read content URI: bytes is null');
        return null;
      }

      // 保存到缓存目录
      final cacheDir = await getApplicationCacheDirectory();
      final localFile = File('${cacheDir.path}/$fileName');
      await localFile.writeAsBytes(bytes);

      debugPrint('[SyncLab] Copied content URI to: ${localFile.path}');
      return localFile.path;
    } catch (e) {
      debugPrint('[SyncLab] Error copying content URI: $e');
      return null;
    }
  }

  /// 选择音乐文件夹（扫描 MP3 和 AAC 文件）
  Future<void> _selectMusicFolder() async {
    try {
      // 请求存储权限
      final status = await Permission.audio.request();
      debugPrint('[SyncLab] 音频权限状态: $status');

      if (!status.isGranted) {
        // 尝试请求存储权限（Android 10 及以下）
        final storageStatus = await Permission.storage.request();
        debugPrint('[SyncLab] 存储权限状态: $storageStatus');

        if (!storageStatus.isGranted && !status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('需要存储权限才能读取音乐文件')));
          }
          // 打开设置页面
          await openAppSettings();
          return;
        }
      }

      final folderPath = await FilePicker.platform.getDirectoryPath();
      if (folderPath == null) return;

      debugPrint('[SyncLab] 选择的文件夹路径: $folderPath');

      // Android: 处理 content:// URI 文件夹
      if (folderPath.startsWith('content://')) {
        debugPrint('[SyncLab] Android content URI 文件夹: $folderPath');
        await _selectMusicFromContentTree(folderPath);
        return;
      }

      // 尝试读取文件夹
      final dir = Directory(folderPath);

      // 检查文件夹是否存在
      bool exists = false;
      bool hasAccess = false;
      try {
        exists = await dir.exists();
        debugPrint('[SyncLab] 文件夹存在: $exists');

        // 尝试列出文件来验证访问权限
        if (exists) {
          try {
            await for (final _ in dir.list().take(1)) {
              hasAccess = true;
              break;
            }
            if (!hasAccess) {
              // 空文件夹也算有访问权限
              hasAccess = true;
            }
          } catch (e) {
            debugPrint('[SyncLab] 无访问权限: $e');
            hasAccess = false;
          }
        }
      } catch (e) {
        debugPrint('[SyncLab] 检查文件夹存在失败: $e');
        exists = false;
        hasAccess = false;
      }

      // 如果无法访问真实路径，自动切换到 SAF 文件选择
      if (!exists || !hasAccess) {
        debugPrint('[SyncLab] 无法访问真实路径，切换到 SAF 文件选择');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('正在使用系统文件选择器...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        // 自动切换到 SAF 文件选择
        await _selectMp3File();
        return;
      }

      // 扫描 MP3 和 AAC 文件（支持中文路径）
      final musicFiles = <FileSystemEntity>[];
      try {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            final ext = entity.path.toLowerCase();
            if (ext.endsWith('.mp3') ||
                ext.endsWith('.aac') ||
                ext.endsWith('.m4a') ||
                ext.endsWith('.wav')) {
              musicFiles.add(entity);
              debugPrint('[SyncLab] 找到音乐文件: ${entity.path}');
            }
          }
        }
      } catch (e) {
        debugPrint('[SyncLab] 扫描文件夹失败: $e');
        // 权限问题，提示用户使用其他方式
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('无法扫描该文件夹: $e\n请使用"选择单个文件"按钮'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      debugPrint('[SyncLab] 找到 ${musicFiles.length} 个音乐文件');

      if (musicFiles.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('未找到 MP3 或 AAC 文件')));
        }
        return;
      }

      // 显示文件列表供选择
      if (!mounted) return;
      final selectedFile = await showDialog<File>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择音乐文件'),
          children: musicFiles.map((f) {
            final file = f as File;
            final fileName = file.path.split(Platform.pathSeparator).last;
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, file),
              child: Text(fileName),
            );
          }).toList(),
        ),
      );

      if (selectedFile != null && mounted) {
        final success = await _controller.selectMp3File(selectedFile.path);
        if (mounted) {
          final fileName = selectedFile.path.split(Platform.pathSeparator).last;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(success ? '已选择: $fileName' : '选择失败')),
          );
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择文件夹失败: $e')));
      }
    }
  }

  /// 从 Android content tree URI 选择音乐文件
  Future<void> _selectMusicFromContentTree(String treeUri) async {
    try {
      // 使用 MethodChannel 列出文件夹中的音乐文件
      const channel = MethodChannel('com.example.sync_music/content_resolver');

      final files = await channel.invokeMethod<List<dynamic>>(
        'listContentTree',
        {'treeUri': treeUri},
      );

      if (files == null || files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('未找到音乐文件')));
        }
        return;
      }

      // 显示文件列表供选择
      if (!mounted) return;
      final selectedFileInfo = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择音乐文件'),
          children: files.map((f) {
            final fileMap = Map<String, dynamic>.from(f as Map);
            final fileName = fileMap['name'] as String? ?? '未知文件';
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, fileMap),
              child: Text(fileName),
            );
          }).toList(),
        ),
      );

      if (selectedFileInfo != null && mounted) {
        final fileUri = selectedFileInfo['uri'] as String;
        final fileName = selectedFileInfo['name'] as String;

        // 复制到缓存目录
        final localPath = await _copyContentUriToCache(fileUri, fileName);
        if (localPath != null) {
          final success = await _controller.selectMp3File(localPath);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(success ? '已选择: $fileName' : '选择失败')),
            );
            setState(() {});
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('无法读取文件')));
          }
        }
      }
    } catch (e) {
      debugPrint('[SyncLab] Error listing content tree: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('读取文件夹失败: $e')));
      }
    }
  }

  /// 开始分发曲目
  Future<void> _startServingTrack() async {
    final success = await _controller.startServingTrack();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success ? '已开始分发曲目' : '分发失败')));
      setState(() {});
    }
  }

  /// 停止分发曲目
  Future<void> _stopServingTrack() async {
    await _controller.stopServingTrack();
    if (mounted) {
      setState(() {});
    }
  }

  void _startSync() {
    _controller.startPlaybackSync();
    if (mounted) {
      setState(() {});
    }
  }

  void _stopSync() {
    _controller.stopPlaybackSync();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _triggerReconnect() async {
    try {
      await _controller.triggerReconnect();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('正在重新连接...')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('重连失败: $e')));
      }
    }
  }

  Future<void> _copyDebugBundle() async {
    try {
      final text = _controller.buildDebugBundleText();
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制日志到剪贴板')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('复制失败: $e')));
    }
  }

  Future<void> _exportDebugBundle() async {
    try {
      final path = await _controller.exportDebugBundleToFile();
      if (!mounted) return;
      setState(() {
        _lastExportPath = path;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导出: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  void _clearDebugLogs() {
    _controller.clearDebugLogs();
    if (mounted) {
      setState(() {
        _lastExportPath = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('日志已清空')));
    }
  }
}
