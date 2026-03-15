import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';

import '../calibration/calibration_service.dart';
import '../diagnostics/sync_log.dart';
import '../diagnostics/sync_diagnostics.dart';
import '../diagnostics/sync_metrics.dart';
import '../diagnostics/throttled_notifier.dart';
import '../room_discovery/mdns_service.dart';
import '../room_discovery/discovered_room.dart';
import '../transport/transport_interface.dart';
import '../transport/websocket_transport.dart';
import '../transport/protocol.dart';
import '../clock/room_clock.dart';
import '../clock/clock_synchronizer.dart';
import '../distributor/audio_distributor.dart';
import '../distributor/audio_cache.dart';
import '../distributor/track_meta.dart';
import '../distributor/http_file_server.dart';
import '../utils/background_executor.dart';
import '../future_start/future_start_controller.dart';
import '../../services/playlist_persistence.dart';
import 'playback_synchronizer.dart';
import 'keep_sync_controller.dart';

/// 同步角色
enum SyncRole { none, host, client }

/// 播放模式
enum PlayMode {
  /// 列表循环
  loop,

  /// 单曲循环
  single,

  /// 随机播放
  shuffle,
}

Future<bool> _writeTextFileIsolate(Map<String, String> args) async {
  final path = args['path'];
  final content = args['content'];
  if (path == null || content == null) return false;
  final file = File(path);
  await file.writeAsString(content);
  return true;
}

/// 同步状态
class SyncV2State {
  final SyncRole role;
  final String? roomId;
  final String? peerId;
  final SyncDiagnosticsData diagnostics;

  const SyncV2State({
    this.role = SyncRole.none,
    this.roomId,
    this.peerId,
    required this.diagnostics,
  });
}

/// 同步控制器
/// 统一管理所有同步模块的 Facade
class SyncV2Controller {
  // 单例
  static final SyncV2Controller _instance = SyncV2Controller._internal();
  factory SyncV2Controller() => _instance;
  SyncV2Controller._internal();

  // 模块实例
  late final MdnsService _mdnsService;
  late final WebSocketTransport _transport;
  late final RoomClock _clock;
  late final ClockSynchronizer _clockSync;
  late final AudioDistributor _distributor;
  late final AudioCache _cache;
  late final HttpFileServer _httpFileServer;
  late final BackgroundExecutor _executor;
  late final FutureStartController _futureStart;
  late final PlaybackSynchronizer _playbackSync;
  late final SyncDiagnostics _diagnostics;
  late final ThrottledDiagnosticsNotifier _throttledNotifier;
  late final ThrottledLogNotifier _logNotifier;
  late final KeepSyncController _keepSync;
  late final SyncMetricsCollector _metrics;
  late final CalibrationService _calibration;
  final PlaylistPersistence _persistence = PlaylistPersistence();

  // 当前角色
  SyncRole _role = SyncRole.none;
  String? _roomId;
  String? _peerId;

  // 曲目状态
  TrackState _trackState = const TrackState();
  final _trackStateController = StreamController<TrackState>.broadcast();

  // 播放列表
  List<TrackMeta> _playlist = [];
  int _currentIndex = -1; // 当前播放索引，-1 表示无曲目
  PlayMode _playMode = PlayMode.loop; // 播放模式，默认列表循环
  List<int> _shuffleOrder = []; // 随机播放顺序

  // 下一首预缓存曲目（Client 端）
  TrackMeta? _nextTrackMeta;
  String? _nextTrackLocalPath;
  bool _nextTrackDownloading = false;

  // 下载进度
  // ignore: unused_field
  StreamSubscription<DownloadProgress>? _downloadProgressSub;

  // 状态订阅
  StreamSubscription<TransportState>? _transportStateSub;
  StreamSubscription<TransportMessage>? _transportMessageSub;

  // 心跳 RTT
  int _lastPingRtt = 0;

  // Client 播放器
  AudioPlayer? _player;
  final _playerStateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  // ignore: unused_field
  StreamSubscription<Duration>? _positionSub;
  // ignore: unused_field
  StreamSubscription<PlayerState>? _playerStateSub;

  // seek 后冷却期（跳过 host_state 处理直到 position 更新）
  int _lastSeekAtMs = 0;
  int _lastSeekTargetMs = 0;

  // Host 播放器（播放本地 MP3）
  AudioPlayer? _hostPlayer;
  StreamSubscription<PlayerState>? _hostPlayerStateSub;

  // FutureStart epoch 管理
  int _epoch = 0;
  int _seq = 0;
  int _leadMs = 1500; // 默认提前量

  // FutureStart 状态
  FutureStartState _futureStartState = FutureStartState.idle;
  int _startAtRoomTimeMs = 0;
  int _actualStartRoomTimeMs = 0;
  int _startErrorMs = 0;

  // Host 状态广播
  Timer? _hostStateTimer;
  int _hostStateSeq = 0;

  // Client 追帧状态
  HostStateMessage? _latestHostState;
  int _catchUpDoneEpoch = -1; // 已追帧的 epoch
  bool _catchUpInFlight = false; // 正在追帧中
  int _lastCatchUpAttemptAtMs = 0; // 上次尝试追帧的时间

  // 追帧条件状态
  bool _hasHostStatePlaying = false; // 收到 isPlaying=true 的 host_state
  bool _trackReadyForCatchUp = false; // 曲目已缓存就绪
  bool _clockLockedForCatchUp = false; // 时钟已锁定

  // 状态流
  final _stateController = StreamController<SyncV2State>.broadcast();

  /// 当前角色
  SyncRole get role => _role;

  /// 当前房间 ID
  String? get roomId => _roomId;

  /// 当前 Peer ID
  String? get peerId => _peerId;

  /// 状态流
  Stream<SyncV2State> get stateStream => _stateController.stream;

  /// 当前状态
  SyncV2State get state => SyncV2State(
    role: _role,
    roomId: _roomId,
    peerId: _peerId,
    diagnostics: _diagnostics.data,
  );

  /// 发现的房间列表
  List<DiscoveredRoom> get discoveredRooms => _mdnsService.rooms;

  /// 房间列表流
  Stream<List<DiscoveredRoom>> get roomsStream => _mdnsService.roomsStream;

  /// 诊断数据（节流后，UI 使用）
  SyncDiagnosticsData get diagnostics => _throttledNotifier.data;

  /// 节流诊断通知器（UI 监听此 notifier）
  ThrottledDiagnosticsNotifier get throttledNotifier => _throttledNotifier;

  /// 节流日志通知器（UI 监听此 notifier）
  ThrottledLogNotifier get logNotifier => _logNotifier;

  /// 指标收集器
  SyncMetricsCollector get metrics => _metrics;

  /// 校准服务
  CalibrationService get calibration => _calibration;

  /// Host 本机 IP（供热点环境手动输入）
  String get hostLocalIp => _httpFileServer.localIp;

  /// 诊断数据流
  Stream<SyncDiagnosticsData> get diagnosticsStream => _diagnostics.stream;

  /// Transport 日志
  List<String> get transportLogs => _transport.transportLogs;

  /// 连接状态
  TransportState get connectionState => _transport.state;

  /// 连接状态流
  Stream<TransportState> get connectionStateStream => _transport.stateStream;

  /// 播放列表
  List<TrackMeta> get playlist => List.unmodifiable(_playlist);

  /// 当前播放索引
  int get currentIndex => _currentIndex;

  /// 当前曲目索引（用于 UI 显示）
  int get playlistIndex => _currentIndex >= 0 ? _currentIndex + 1 : 0;

  /// 播放模式
  PlayMode get playMode => _playMode;

  /// 设置播放模式
  void setPlayMode(PlayMode mode) {
    _playMode = mode;
    if (mode == PlayMode.shuffle) {
      _generateShuffleOrder();
    }
    _updateState();
  }

  /// 切换到下一个播放模式
  PlayMode cyclePlayMode() {
    switch (_playMode) {
      case PlayMode.loop:
        _playMode = PlayMode.single;
        break;
      case PlayMode.single:
        _playMode = PlayMode.shuffle;
        _generateShuffleOrder();
        break;
      case PlayMode.shuffle:
        _playMode = PlayMode.loop;
        break;
    }
    _updateState();
    return _playMode;
  }

  /// 生成随机播放顺序
  void _generateShuffleOrder() {
    _shuffleOrder = List.generate(_playlist.length, (i) => i);
    _shuffleOrder.shuffle();
    // 确保当前播放的歌曲在随机列表的第一个
    if (_currentIndex >= 0 && _currentIndex < _shuffleOrder.length) {
      _shuffleOrder.remove(_currentIndex);
      _shuffleOrder.insert(0, _currentIndex);
    }
  }

  /// 播放列表总数
  int get playlistCount => _playlist.length;

  /// 是否有上一首
  bool get hasPreviousTrack => _currentIndex > 0;

  /// 是否有下一首（循环播放时总是有下一首）
  bool get hasNextTrack => _playlist.isNotEmpty && _currentIndex >= 0;

  /// 已连接的 peer 数量
  int get peerCount => _transport.connectedPeers.length;

  // ==================== RoomClock 属性 ====================

  /// 当前房间时间（毫秒）
  int get roomNowMs => _clock.roomNowMs;

  /// 原始偏移（最近一次样本）
  int get offsetRawMs => _clock.offsetRawMs;

  /// EMA 平滑后的偏移
  int get offsetEmaMs => _clock.offsetEmaMs;

  /// 最近一次 RTT
  int get rttMs => _clock.rttMs;

  /// Jitter（网络抖动）
  int get jitterMs => _clock.jitterMs;

  /// 是否已锁定（时钟同步稳定）
  bool get isClockLocked => _clock.isLocked;

  /// 样本计数
  int get clockSampleCount => _clock.sampleCount;

  /// EMA alpha 值
  double get emaAlpha => _clock.emaAlpha;

  // ==================== FutureStart 属性 ====================

  /// FutureStart 状态
  FutureStartState get futureStartState => _futureStartState;

  /// 目标启动时间
  int get startAtRoomTimeMs => _startAtRoomTimeMs;

  /// 实际启动时间
  int get actualStartRoomTimeMs => _actualStartRoomTimeMs;

  /// 启动误差
  int get startErrorMs => _startErrorMs;

  /// 提前量（ms）
  int get leadMs => _leadMs;
  set leadMs(int value) {
    if (value >= 800 && value <= 3000) {
      _leadMs = value;
    }
  }

  /// FutureStart 状态流
  Stream<FutureStartState> get futureStartStateStream =>
      _futureStart.stateStream;

  /// 重置时钟
  void resetClock({bool keepHistory = false}) {
    _clockSync.reset(keepHistory: keepHistory);
  }

  /// 设置 EMA alpha 值
  void setEmaAlpha(double alpha) {
    _clockSync.setEmaAlpha(alpha);
  }

  /// 进入后台模式
  void enterBackground() {
    if (_role == SyncRole.client) {
      _clockSync.enterBackground();
    }
  }

  /// 恢复前台模式
  void enterForeground() {
    if (_role == SyncRole.client) {
      _clockSync.enterForeground();
    }
  }

  /// 初始化
  Future<void> init() async {
    _mdnsService = MdnsService();
    _transport = WebSocketTransport();
    _clock = RoomClock();
    _clockSync = ClockSynchronizer(clock: _clock, transport: _transport);
    _distributor = AudioDistributor();
    _cache = AudioCache();
    _httpFileServer = HttpFileServer();
    _executor = BackgroundExecutor();
    _futureStart = FutureStartController(clock: _clock);
    _playbackSync = PlaybackSynchronizer(clock: _clock);
    _diagnostics = SyncDiagnostics();
    _throttledNotifier = ThrottledDiagnosticsNotifier(throttleIntervalMs: 250);
    _logNotifier = ThrottledLogNotifier(throttleIntervalMs: 500);
    _keepSync = KeepSyncController(
      config: Platform.isIOS ? KeepSyncConfig.iosSafe : const KeepSyncConfig(),
    );
    _metrics = SyncMetricsCollector();
    _calibration = CalibrationService();

    // 初始化校准服务
    _calibration.initialize();

    // 监听 Transport 状态变化
    _transportStateSub = _transport.stateStream.listen(
      _onTransportStateChanged,
    );

    // 监听 Transport 消息
    _transportMessageSub = _transport.messageStream.listen(_onTransportMessage);

    // 监听 Transport 日志并转发到节流日志通知器
    _transport.logStream.listen((log) {
      _logNotifier.addLog(log);
    });

    // 监听下载进度
    _downloadProgressSub = _cache.progressStream.listen(_onDownloadProgress);

    SyncLog.i('SyncV2Controller 初始化完成');
  }

  void setKeepSyncConfig(KeepSyncConfig config) {
    _keepSync.updateConfig(config);
    SyncLog.i('[KeepSync] config_updated: $config', role: _role.name);
  }

  void setIosSafeMode(bool enabled) {
    if (!Platform.isIOS) return;
    setKeepSyncConfig(
      enabled ? KeepSyncConfig.iosSafe : const KeepSyncConfig(),
    );
  }

  bool get isIosSafeMode {
    if (!Platform.isIOS) return false;
    final c = _keepSync.config;
    final s = KeepSyncConfig.iosSafe;
    return c.speedIntervalMs == s.speedIntervalMs &&
        c.speedMin == s.speedMin &&
        c.speedMax == s.speedMax &&
        c.maxSpeedStepPerUpdate == s.maxSpeedStepPerUpdate;
  }

  String buildDebugBundleText({int maxLines = 800}) {
    final sb = StringBuffer();
    sb.writeln('=== SyncMusic Debug Bundle ===');
    sb.writeln('exportedAt: ${DateTime.now().toIso8601String()}');
    sb.writeln('role: ${_role.name}');
    sb.writeln('roomId: ${_roomId ?? "-"}');
    sb.writeln('peerId: ${_peerId ?? "-"}');
    sb.writeln('platform: ${Platform.operatingSystem}');
    sb.writeln('');
    sb.writeln('--- Diagnostics ---');
    sb.writeln(_diagnostics.data.toFormattedString());
    sb.writeln('');
    sb.writeln('--- Metrics (samples json, last 120s) ---');
    sb.writeln(_metrics.exportSamplesJson());
    sb.writeln('');
    sb.writeln(
      '--- Transport logs (last ${_transport.transportLogs.length}) ---',
    );
    for (final l in _transport.transportLogs) {
      sb.writeln(l);
    }
    sb.writeln('');
    sb.writeln('--- SyncLog buffer (last $maxLines) ---');
    final lines = SyncLog.bufferedLines;
    final start = lines.length > maxLines ? lines.length - maxLines : 0;
    for (final l in lines.sublist(start)) {
      sb.writeln(l);
    }
    return sb.toString();
  }

  Future<String> exportDebugBundleToFile() async {
    final dir = await getTemporaryDirectory();
    final filePath =
        '${dir.path}/sync_debug_${DateTime.now().millisecondsSinceEpoch}.txt';
    final content = buildDebugBundleText();
    await _executor.runCpuTask(_writeTextFileIsolate, {
      'path': filePath,
      'content': content,
    });
    SyncLog.i('[Export] debug_bundle_written: $filePath');
    return filePath;
  }

  void clearDebugLogs() {
    SyncLog.clearBuffer();
    _logNotifier.clear();
    SyncLog.i('[Export] logs_cleared');
  }

  void _onTransportStateChanged(TransportState state) {
    final stateStr = state.toString().split('.').last;
    _throttledNotifier.updatePartial(connectionState: stateStr);

    if (state == TransportState.connected && _role == SyncRole.client) {
      // 连接成功后发送 hello
      _sendHello();
    }

    if (state == TransportState.hosting) {
      _throttledNotifier.updatePartial(connectionState: 'hosting');
    }

    // 当 Client 连接断开时，自动清理状态，避免残留导致无法创建房间
    if (state == TransportState.disconnected && _role == SyncRole.client) {
      SyncLog.w('[SyncV2] Client 连接断开，自动清理状态', role: 'client');
      _clockSync.stopSyncing();
      _playbackSync.stopSync();
      _role = SyncRole.none;
      _roomId = null;
      _peerId = null;
      _updateState();
      _throttledNotifier.updatePartial(
        role: 'none',
        state: 'disconnected',
        connectionState: 'disconnected',
      );
    }
  }

  void _onTransportMessage(TransportMessage message) async {
    final msg = parseMessage(message.payload);
    if (msg == null) return;

    switch (msg.type) {
      case SyncProtocol.pong:
        final pong = msg as PongMessage;
        final t2ClientMs = DateTime.now().millisecondsSinceEpoch;
        _lastPingRtt = t2ClientMs - pong.t0ClientMs;
        _throttledNotifier.updatePartial(
          lastPingRtt: _lastPingRtt,
          reconnectCount: _transport.reconnectCount,
        );
        break;

      case SyncProtocol.peerJoin:
        // Host 广播的 peer 加入通知
        _throttledNotifier.updatePartial(peerCount: peerCount);

        // 如果是 Host 且有当前曲目，发送 track_announce 给新 Client
        if (_role == SyncRole.host) {
          final joinMsg = msg as PeerJoinMessage;
          SyncLog.i(
            '[Host] 新成员加入: peerId=${joinMsg.peerId}, 有曲目=${_trackState.meta != null}, HTTP服务运行中=${_httpFileServer.isRunning}',
            role: 'host',
          );
          if (_trackState.meta != null) {
            // 如果 HTTP 服务未运行但正在播放，启动服务
            if (!_httpFileServer.isRunning &&
                _hostPlayer != null &&
                _hostPlayer!.playing) {
              SyncLog.i('[Host] 正在播放但 HTTP 服务未运行，启动服务...', role: 'host');
              final success = await startServingTrack();
              SyncLog.i(
                '[Host] HTTP 服务启动结果: $success, isRunning=${_httpFileServer.isRunning}',
                role: 'host',
              );
            }
            if (_httpFileServer.isRunning) {
              SyncLog.i(
                '[Host] 发送 track_announce 给新 Client: ${joinMsg.peerId}',
                role: 'host',
              );
              _sendTrackAnnounceToPeer(joinMsg.peerId);
            } else {
              SyncLog.w('[Host] HTTP 服务未运行，无法发送 track_announce', role: 'host');
            }
          } else {
            SyncLog.w(
              '[Host] 无曲目信息，无法发送 track_announce: meta=${_trackState.meta}',
              role: 'host',
            );
          }
        }
        break;

      case SyncProtocol.peerLeave:
        _throttledNotifier.updatePartial(peerCount: peerCount);
        break;

      case SyncProtocol.trackAnnounce:
        // Client 收到曲目公告，触发下载
        if (_role == SyncRole.client) {
          final announce = msg as TrackAnnounceMessage;
          _onTrackAnnounce(announce);
        }
        break;

      case SyncProtocol.clientReady:
        // Host 收到 Client 就绪通知
        if (_role == SyncRole.host) {
          final ready = msg as ClientReadyMessage;
          SyncLog.i(
            '[Host] Client 就绪: ${ready.peerId}, 已缓存=${ready.cached}',
            role: 'host',
          );

          // 如果 Host 正在播放，发送当前播放状态给新 Client
          if (_hostPlayer != null && _hostPlayer!.playing) {
            _sendCurrentStateToNewClient(ready.peerId);
          }
        }
        break;

      case SyncProtocol.clientReadyError:
        // Host 收到 Client 错误通知
        if (_role == SyncRole.host) {
          final error = msg as ClientReadyErrorMessage;
          SyncLog.e(
            '[Host] Client 错误: ${error.peerId}, 错误码=${error.errorCode}',
            role: 'host',
          );
        }
        break;

      case SyncProtocol.startAt:
        // Client 收到同起开播指令
        if (_role == SyncRole.client) {
          final startAt = msg as StartAtMessage;
          _onStartAt(startAt);
        }
        break;

      case SyncProtocol.clientStartReport:
        // Host 收到 Client 启动报告
        if (_role == SyncRole.host) {
          final report = msg as ClientStartReportMessage;
          SyncLog.i(
            '[Host] Client 启动报告: peer=${report.peerId}, 误差=${report.startErrorMs}ms',
            role: 'host',
          );
        }
        break;

      case SyncProtocol.hostState:
        // Client 收到 Host 状态广播
        if (_role == SyncRole.client) {
          final hostState = msg as HostStateMessage;
          _onHostState(hostState);
        }
        break;

      case SyncProtocol.pauseCommand:
        // Client 收到暂停指令
        if (_role == SyncRole.client) {
          final pauseCmd = msg as PauseCommandMessage;
          _onPauseCommand(pauseCmd);
        }
        break;

      case SyncProtocol.resumeCommand:
        // Client 收到恢复播放指令
        if (_role == SyncRole.client) {
          final resumeCmd = msg as ResumeCommandMessage;
          _onResumeCommand(resumeCmd);
        }
        break;

      case SyncProtocol.nextTrackAnnounce:
        // Client 收到下一首预缓存公告
        if (_role == SyncRole.client) {
          final nextAnnounce = msg as NextTrackAnnounceMessage;
          _onNextTrackAnnounce(nextAnnounce);
        }
        break;

      case SyncProtocol.seekCommand:
        // Client 收到进度跳转指令
        if (_role == SyncRole.client) {
          final seekCmd = msg as SeekCommandMessage;
          _onSeekCommand(seekCmd);
        }
        break;
    }
  }

  /// Client 收到曲目公告
  Future<void> _onTrackAnnounce(TrackAnnounceMessage announce) async {
    SyncLog.i(
      '[Client] 收到 track_announce: trackId=${announce.trackId}, url=${announce.url}, 大小=${announce.sizeBytes}',
      role: 'client',
    );

    // 检查 URL 是否有效
    if (announce.url.isEmpty) {
      SyncLog.e('[Client] track_announce URL 为空!', role: 'client');
      _trackState = TrackState(
        status: TrackStatus.error,
        error: 'Invalid track URL',
      );
      _trackStateController.add(_trackState);
      return;
    }

    // 检查是否是预缓存的下一首曲目
    if (_nextTrackMeta?.trackId == announce.trackId &&
        _nextTrackLocalPath != null) {
      SyncLog.i(
        '[Client] 使用预缓存的下一首: ${announce.trackId}, path=$_nextTrackLocalPath',
        role: 'client',
      );

      // 使用预缓存的曲目
      _trackState = TrackState(
        status: TrackStatus.serving,
        meta: TrackMeta(
          trackId: announce.trackId,
          localPath: _nextTrackLocalPath!,
          fileName: announce.fileName,
          sizeBytes: announce.sizeBytes,
          durationMs: announce.durationMs,
          fileHash: announce.fileHash,
          createdAt: DateTime.now(),
        ),
      );
      _trackStateController.add(_trackState);

      // 发送 ready 消息
      final readyMsg = ClientReadyMessage(
        roomId: announce.roomId,
        peerId: _peerId!,
        trackId: announce.trackId,
        cached: true,
        localPath: _nextTrackLocalPath!,
        prepareMs: 0,
      );
      _transport.send(
        TransportMessage.create(readyMsg.type, readyMsg.toJson()),
      );

      // 清除预缓存状态
      _nextTrackMeta = null;
      _nextTrackLocalPath = null;

      // 曲目就绪，检查是否需要追帧
      _onTrackReadyForCatchUp();
      return;
    }

    // 检查是否已经是当前曲目且已缓存
    if (_trackState.meta?.trackId == announce.trackId &&
        _trackState.status == TrackStatus.serving &&
        _trackState.meta?.localPath.isNotEmpty == true) {
      SyncLog.i('[Client] 曲目已缓存（当前曲目）: ${announce.trackId}', role: 'client');
      // 重新发送 ready 消息
      final readyMsg = ClientReadyMessage(
        roomId: announce.roomId,
        peerId: _peerId!,
        trackId: announce.trackId,
        cached: true,
        localPath: _trackState.meta!.localPath,
        prepareMs: 0,
      );
      _transport.send(
        TransportMessage.create(readyMsg.type, readyMsg.toJson()),
      );
      return;
    }

    // 检查本地缓存目录中是否已有该曲目
    final cachedTracks = await _cache.getCachedTracks();
    final existingCache = cachedTracks
        .where(
          (t) =>
              t.trackId == announce.trackId ||
              t.localPath.contains(announce.trackId),
        )
        .toList();

    if (existingCache.isNotEmpty) {
      final cached = existingCache.first;
      SyncLog.i(
        '[Client] 曲目已在本地缓存: ${announce.trackId} path=${cached.localPath}',
        role: 'client',
      );

      // 更新曲目状态
      _trackState = TrackState(
        status: TrackStatus.serving,
        meta: TrackMeta(
          trackId: announce.trackId,
          localPath: cached.localPath,
          fileName: announce.fileName,
          sizeBytes: announce.sizeBytes,
          durationMs: announce.durationMs,
          fileHash: announce.fileHash,
          createdAt: DateTime.now(),
        ),
      );
      _trackStateController.add(_trackState);

      // 发送 ready 消息
      final readyMsg = ClientReadyMessage(
        roomId: announce.roomId,
        peerId: _peerId!,
        trackId: announce.trackId,
        cached: true,
        localPath: cached.localPath,
        prepareMs: 0,
      );
      _transport.send(
        TransportMessage.create(readyMsg.type, readyMsg.toJson()),
      );

      SyncLog.i(
        '[Client] 已发送 client_ready（使用缓存）: ${announce.trackId}',
        role: 'client',
      );

      // 曲目就绪，检查是否需要追帧
      _onTrackReadyForCatchUp();
      return;
    }

    // 更新曲目状态
    _trackState = TrackState(
      status: TrackStatus.announcing,
      meta: TrackMeta(
        trackId: announce.trackId,
        localPath: '', // 还未下载
        url: announce.url, // 保存下载地址用于重试
        fileName: announce.fileName,
        sizeBytes: announce.sizeBytes,
        durationMs: announce.durationMs,
        fileHash: announce.fileHash,
        createdAt: DateTime.now(),
      ),
    );
    _trackStateController.add(_trackState);

    // 开始下载
    final result = await _cache.downloadAndCache(
      trackId: announce.trackId,
      url: announce.url,
      expectedHash: announce.fileHash,
      expectedSize: announce.sizeBytes,
    );

    // 发送结果给 Host
    if (result.success) {
      final readyMsg = ClientReadyMessage(
        roomId: announce.roomId,
        peerId: _peerId!,
        trackId: announce.trackId,
        cached: true,
        localPath: result.localPath!,
        prepareMs: result.prepareMs,
      );
      _transport.send(
        TransportMessage.create(readyMsg.type, readyMsg.toJson()),
      );

      SyncLog.i(
        '[Client] 已发送 client_ready: ${announce.trackId}',
        role: 'client',
      );

      _trackState = TrackState(
        status: TrackStatus.serving,
        meta: _trackState.meta!.copyWith(localPath: result.localPath!),
      );
      _trackStateController.add(_trackState);

      // 曲目就绪，检查是否需要追帧
      _onTrackReadyForCatchUp();

      // 预先初始化播放器（减少 start_at 时的准备时间）
      await _preInitPlayer(result.localPath!);
    } else {
      final errorMsg = ClientReadyErrorMessage(
        roomId: announce.roomId,
        peerId: _peerId!,
        trackId: announce.trackId,
        errorCode: result.errorCode ?? 'unknown',
        errorMessage: result.errorMessage ?? 'Unknown error',
      );
      _transport.send(
        TransportMessage.create(errorMsg.type, errorMsg.toJson()),
      );

      SyncLog.e(
        '[Client] 已发送 client_ready_error: ${result.errorCode}',
        role: 'client',
      );

      _trackState = TrackState(
        status: TrackStatus.error,
        error: result.errorMessage,
      );
    }
    _trackStateController.add(_trackState);
  }

  /// 预先初始化播放器（Client 缓存完成后调用）
  Future<void> _preInitPlayer(String localPath) async {
    try {
      if (_player == null) {
        _player = AudioPlayer();
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
      }
      await _player!.setFilePath(localPath);
      SyncLog.i('[Client] 播放器预初始化: $localPath', role: 'client');
    } catch (e) {
      SyncLog.w('[Client] 播放器预初始化失败: $e', role: 'client');
    }
  }

  /// Client 收到同起开播指令
  Future<void> _onStartAt(StartAtMessage startAt) async {
    SyncLog.i(
      '[Client] 收到 start_at: epoch=${startAt.epoch} seq=${startAt.seq} T=${startAt.startAtRoomTimeMs} trackId=${startAt.trackId}',
      role: 'client',
    );

    // 重置追帧状态（切换歌曲时需要重新追帧）
    _catchUpDoneEpoch = -1;
    _hasHostStatePlaying = false;
    _trackReadyForCatchUp = false;
    SyncLog.i('[Client] 切换歌曲，重置追帧状态', role: 'client');

    // 检查曲目是否已缓存
    final trackId = startAt.trackId;
    final localPath = _trackState.meta?.localPath;
    final currentTrackId = _trackState.meta?.trackId;

    SyncLog.i(
      '[Client] 曲目检查: 请求trackId=$trackId 当前trackId=$currentTrackId localPath=$localPath',
      role: 'client',
    );

    if (localPath == null || _trackState.meta?.trackId != trackId) {
      SyncLog.e('[Client] start_at: 曲目未缓存，无法播放', role: 'client');
      _futureStartState = FutureStartState.failed;
      return;
    }

    _startAtRoomTimeMs = startAt.startAtRoomTimeMs;

    // 使用 FutureStartController 执行两段式等待
    await _futureStart.schedule(
      params: FutureStartParams(
        epoch: startAt.epoch,
        seq: startAt.seq,
        trackId: trackId,
        startAtRoomTimeMs: startAt.startAtRoomTimeMs,
        startPosMs: startAt.startPosMs,
      ),
      onPrepare: (params) async {
        // 准备：加载新曲目文件
        _futureStartState = FutureStartState.preparing;

        try {
          // 始终重新加载文件（切换歌曲时需要）
          if (_player == null) {
            _player = AudioPlayer();
            final session = await AudioSession.instance;
            await session.configure(const AudioSessionConfiguration.music());
          }

          // 加载新曲目文件
          await _player!.setFilePath(localPath);
          SyncLog.i('[Client] 已加载曲目文件: $localPath', role: 'client');

          if (params.startPosMs > 0) {
            await _player!.seek(Duration(milliseconds: params.startPosMs));
          }
          return FutureStartResult(success: true);
        } catch (e) {
          SyncLog.e('[Client] FutureStart 准备失败: $e', role: 'client');
          _futureStartState = FutureStartState.failed;
          return FutureStartResult(success: false, failReason: e.toString());
        }
      },
      onStart: (params) {
        // 执行播放
        _player?.play();

        _actualStartRoomTimeMs = _futureStart.actualStartRoomTimeMs;
        _startErrorMs = _futureStart.startErrorMs;
        _futureStartState = FutureStartState.started;

        SyncLog.i(
          '[Client] FutureStart 已启动: 实际=$_actualStartRoomTimeMs 误差=$_startErrorMs',
          role: 'client',
        );

        // 上报给 Host
        final report = ClientStartReportMessage(
          peerId: _peerId!,
          epoch: params.epoch,
          seq: params.seq,
          actualStartRoomTimeMs: _actualStartRoomTimeMs,
          startErrorMs: _startErrorMs,
        );
        _transport.send(TransportMessage.create(report.type, report.toJson()));

        // 切换歌曲后标记状态，让后续 host_state 能通过 KeepSync 同步
        _trackReadyForCatchUp = true;
        _hasHostStatePlaying = true;
        // 不设置 _catchUpDoneEpoch，让后续 host_state 能触发追帧同步到 Host 位置
        SyncLog.i(
          '[Client] 切换歌曲完成: epoch=${params.epoch} _hasHostStatePlaying=$_hasHostStatePlaying',
          role: 'client',
        );
        SyncLog.i('[Client] 等待后续 host_state 进行追帧同步', role: 'client');
      },
    );
  }

  /// Client 收到 Host 状态广播
  Future<void> _onHostState(HostStateMessage hostState) async {
    // 更新最新 Host 状态
    _latestHostState = hostState;

    // 更新条件状态（先保存旧值，再更新）
    final wasPlaying = _hasHostStatePlaying;
    // 注意：这里先不更新 _hasHostStatePlaying，等恢复播放逻辑处理完再更新

    // 获取当前 Client 播放器状态
    final clientPosMs = _player?.position.inMilliseconds ?? -1;
    final clientPlaying = _player?.playing ?? false;
    final clientTrackId = _trackState.meta?.trackId ?? 'null';

    SyncLog.i(
      '[Client] 收到 host_state: isPlaying=${hostState.isPlaying} pos=${hostState.hostPosMs}ms epoch=${hostState.epoch} trackId=${hostState.trackId}',
      role: 'client',
    );
    SyncLog.i(
      '[Client] 当前状态: wasPlaying=$wasPlaying clientPos=$clientPosMs clientPlaying=$clientPlaying clientTrackId=$clientTrackId',
      role: 'client',
    );

    // 从暂停恢复播放 或 新 Client 加入正在播放
    // 或者 host 在播放但 client 播放器没有播放（异常恢复）
    final shouldResume =
        (!wasPlaying && hostState.isPlaying) ||
        (hostState.isPlaying && !clientPlaying);

    // 检查曲目是否匹配
    final trackMismatch =
        clientTrackId != hostState.trackId && hostState.trackId != 'null';

    if (shouldResume) {
      SyncLog.i(
        '[Client] 检测到需要恢复播放: wasPlaying=$wasPlaying hostPlaying=${hostState.isPlaying} clientPlaying=$clientPlaying trackMismatch=$trackMismatch',
        role: 'client',
      );

      // 如果曲目不匹配，不恢复播放，等待正确曲目下载
      if (trackMismatch) {
        SyncLog.i(
          '[Client] 曲目不匹配，跳过恢复播放: clientTrackId=$clientTrackId hostTrackId=${hostState.trackId}',
          role: 'client',
        );
        _hasHostStatePlaying = hostState.isPlaying;
        _runKeepSync(hostState);
        return;
      }

      // 标记当前 epoch 已追帧完成，避免 _performCatchUp 重新加载文件
      _catchUpDoneEpoch = hostState.epoch;

      final localPath = _trackState.meta?.localPath;
      if (localPath == null || localPath.isEmpty) {
        // 曲目还没下载完，跳过播放，等下载完成后会通过 _onTrackReadyForCatchUp 触发
        SyncLog.i('[Client] 曲目未就绪，跳过自动播放', role: 'client');
      } else if (_player != null && !_player!.playing) {
        // 播放器已初始化，seek 到 Host 位置并播放
        SyncLog.i(
          '[Client] 播放器已存在但未播放，准备 seek 到 ${hostState.hostPosMs}ms',
          role: 'client',
        );
        _player!.seek(Duration(milliseconds: hostState.hostPosMs));
        SyncLog.i('[Client] seek 完成，准备播放', role: 'client');
        await _player!.play();
        SyncLog.i('[Client] 恢复播放完成', role: 'client');
      } else if (_player == null) {
        // 播放器未初始化，需要初始化并播放
        SyncLog.i('[Client] 播放器未初始化，准备初始化并播放', role: 'client');
        try {
          _player = AudioPlayer();
          final session = await AudioSession.instance;
          await session.configure(const AudioSessionConfiguration.music());
          await _player!.setFilePath(localPath);
          _player!.seek(Duration(milliseconds: hostState.hostPosMs));
          await _player!.play();
          SyncLog.i(
            '[Client] 已初始化播放器并播放: pos=${hostState.hostPosMs}',
            role: 'client',
          );
        } catch (e) {
          SyncLog.e('[Client] 初始化播放器失败', error: e);
        }
      }
    }

    // 现在更新 _hasHostStatePlaying
    _hasHostStatePlaying = hostState.isPlaying;

    // 执行 KeepSync 持续同步
    _runKeepSync(hostState);
  }

  /// Client 收到暂停指令
  void _onPauseCommand(PauseCommandMessage pauseCmd) {
    SyncLog.i('[Client] 收到暂停指令: epoch=${pauseCmd.epoch}', role: 'client');

    // 暂停本地播放器
    _player?.pause();

    // 更新状态（保持 futureStartState 为 started，以便恢复播放）
    _hasHostStatePlaying = false;
  }

  /// Client 收到恢复播放指令
  void _onResumeCommand(ResumeCommandMessage resumeCmd) {
    SyncLog.i(
      '[Client] 收到恢复播放指令: epoch=${resumeCmd.epoch}, pos=${resumeCmd.resumePosMs}',
      role: 'client',
    );

    // 获取当前播放器状态
    final playerExists = _player != null;
    final playerPlaying = _player?.playing ?? false;
    final playerPos = _player?.position.inMilliseconds ?? -1;

    SyncLog.i(
      '[Client] 播放器状态: exists=$playerExists playing=$playerPlaying pos=$playerPos',
      role: 'client',
    );

    // 恢复本地播放器（从暂停位置继续）
    if (_player != null && !_player!.playing) {
      // 先 seek 到 Host 的播放位置
      if (resumeCmd.resumePosMs > 0) {
        SyncLog.i(
          '[Client] 准备 seek 到位置: ${resumeCmd.resumePosMs}',
          role: 'client',
        );
        _player!.seek(Duration(milliseconds: resumeCmd.resumePosMs));
        SyncLog.i('[Client] seek 完成', role: 'client');
      }
      _player!.play();
      SyncLog.i('[Client] 恢复播放完成', role: 'client');
    } else if (_player != null && _player!.playing) {
      SyncLog.w('[Client] 播放器已在播放中，跳过恢复', role: 'client');
    } else {
      SyncLog.e('[Client] 播放器不存在，无法恢复播放', role: 'client');
    }

    // 更新状态
    _hasHostStatePlaying = true;
    // 标记当前 epoch 已追帧完成，避免 host_state 触发追帧
    _catchUpDoneEpoch = resumeCmd.epoch;
    SyncLog.i(
      '[Client] 恢复播放状态更新: _hasHostStatePlaying=$_hasHostStatePlaying _catchUpDoneEpoch=$_catchUpDoneEpoch',
      role: 'client',
    );
  }

  /// Client 收到进度跳转指令
  void _onSeekCommand(SeekCommandMessage seekCmd) {
    SyncLog.i(
      '[Client] 收到进度跳转指令: epoch=${seekCmd.epoch}, pos=${seekCmd.seekPosMs}',
      role: 'client',
    );

    // 获取当前播放器状态
    final playerExists = _player != null;
    final playerPlaying = _player?.playing ?? false;
    final playerPos = _player?.position.inMilliseconds ?? -1;

    SyncLog.i(
      '[Client] 播放器状态: exists=$playerExists playing=$playerPlaying pos=$playerPos',
      role: 'client',
    );

    // 跳转到指定位置
    if (_player != null) {
      _player!.seek(Duration(milliseconds: seekCmd.seekPosMs));
      SyncLog.i('[Client] 已跳转到位置: ${seekCmd.seekPosMs}', role: 'client');
    } else {
      SyncLog.e('[Client] 播放器不存在，无法跳转', role: 'client');
    }

    // 标记当前 epoch 已追帧完成
    _catchUpDoneEpoch = seekCmd.epoch;
  }

  /// Client 收到下一首预缓存公告
  Future<void> _onNextTrackAnnounce(NextTrackAnnounceMessage announce) async {
    SyncLog.i(
      '[Client] 收到下一首预缓存公告: trackId=${announce.trackId}, url=${announce.url}',
      role: 'client',
    );

    // 检查 URL 是否有效
    if (announce.url.isEmpty) {
      SyncLog.w('[Client] 下一首预缓存 URL 为空', role: 'client');
      return;
    }

    // 检查是否已经在下载
    if (_nextTrackDownloading) {
      SyncLog.i('[Client] 下一首正在下载中，跳过', role: 'client');
      return;
    }

    // 检查本地是否已有缓存
    final cachedTracks = await _cache.getCachedTracks();
    final existingCache = cachedTracks
        .where(
          (t) =>
              t.trackId == announce.trackId ||
              t.localPath.contains(announce.trackId),
        )
        .toList();

    if (existingCache.isNotEmpty) {
      // 已有缓存，直接记录
      _nextTrackMeta = TrackMeta(
        trackId: announce.trackId,
        localPath: existingCache.first.localPath,
        fileName: announce.fileName,
        sizeBytes: announce.sizeBytes,
        durationMs: announce.durationMs,
        fileHash: announce.fileHash,
        createdAt: DateTime.now(),
      );
      _nextTrackLocalPath = existingCache.first.localPath;
      SyncLog.i(
        '[Client] 下一首已缓存: ${announce.trackId}, path=$_nextTrackLocalPath',
        role: 'client',
      );
      return;
    }

    // 开始后台下载
    _nextTrackDownloading = true;
    _nextTrackMeta = TrackMeta(
      trackId: announce.trackId,
      localPath: '', // 还未下载完成
      fileName: announce.fileName,
      sizeBytes: announce.sizeBytes,
      durationMs: announce.durationMs,
      fileHash: announce.fileHash,
      createdAt: DateTime.now(),
    );

    SyncLog.i('[Client] 开始后台下载下一首: ${announce.trackId}', role: 'client');

    try {
      final result = await _cache.downloadAndCache(
        url: announce.url,
        trackId: announce.trackId,
        expectedHash: announce.fileHash,
        expectedSize: announce.sizeBytes,
      );

      if (result.success && result.localPath != null) {
        _nextTrackLocalPath = result.localPath;
        SyncLog.i(
          '[Client] 下一首预缓存完成: ${announce.trackId}, path=$_nextTrackLocalPath',
          role: 'client',
        );
      } else {
        SyncLog.w(
          '[Client] 下一首预缓存失败: ${announce.trackId}, error=${result.errorMessage}',
          role: 'client',
        );
      }
    } catch (e) {
      SyncLog.e('[Client] 下一首预缓存异常: ${announce.trackId}', error: e);
    } finally {
      _nextTrackDownloading = false;
    }
  }

  /// 执行 KeepSync 持续同步
  void _runKeepSync(HostStateMessage hostState) {
    if (_player == null || _trackState.meta == null) {
      SyncLog.d(
        '[KeepSync] 跳过: player=${_player != null} trackMeta=${_trackState.meta != null}',
        role: 'client',
      );
      return;
    }

    final roomNowMs = _clock.roomNowMs;
    final clientPosMs = _player!.position.inMilliseconds;

    // seek 后冷却期检查（等待 player position 更新）
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final seekCooldownActive = (nowMs - _lastSeekAtMs < 800);
    if (seekCooldownActive && _lastSeekTargetMs > 0) {
      // 检查 player position 是否已更新到目标附近
      final posDelta = (clientPosMs - _lastSeekTargetMs).abs();
      if (posDelta > 300) {
        // position 还没更新，跳过本次处理
        SyncLog.d(
          '[KeepSync] seek 冷却期: pos=$clientPosMs target=$_lastSeekTargetMs delta=$posDelta ms',
          role: 'client',
        );
        return;
      }
      // position 已更新，清除冷却期
      _lastSeekAtMs = 0;
      _lastSeekTargetMs = 0;
    }

    final decision = _keepSync.decide(
      isPlaying: hostState.isPlaying,
      epoch: hostState.epoch,
      trackId: hostState.trackId,
      hostPosMs: hostState.hostPosMs,
      sampledAtRoomTimeMs: hostState.sampledAtRoomTimeMs,
      roomNowMs: roomNowMs,
      clientPosMs: clientPosMs,
      durationMs: _trackState.meta!.durationMs,
      latencyCompMs: _calibration.totalCompensationMs,
      isClockLocked: _clock.isLocked,
      jitterMs: _diagnostics.data.jitterMs,
      rttMs: _diagnostics.data.rttMs,
    );

    // 详细决策日志
    SyncLog.d(
      '[KeepSync] 决策: action=${decision.action.name} delta=${decision.deltaMs}ms reason=${decision.reason ?? "无"}',
      role: 'client',
    );

    // 如果 epoch 变化且偏差小，跳过本次处理（让下一次 host_state 再做决策）
    if (decision.reason == 'epoch_changed') {
      SyncLog.i('[KeepSync] epoch 变化且偏差小，跳过本次处理', role: 'client');
      return;
    }

    // epoch_changed_seek 需要执行 seek 同步

    // 记录样本到指标收集器
    _metrics.record(
      tsRoomNowMs: roomNowMs,
      deltaMs: decision.deltaMs,
      audiblePosMs: clientPosMs,
      targetPosMs: decision.targetPosMs,
      rttMs: _diagnostics.data.rttMs,
      jitterMs: _diagnostics.data.jitterMs,
      speed: _keepSync.currentSpeed,
      action: decision.action.name,
    );

    // 诊断日志：确认指标记录
    if (decision.action != KeepSyncAction.noop) {
      SyncLog.d(
        '[Metrics] 记录: delta=${decision.deltaMs} pos=$clientPosMs action=${decision.action.name}',
        role: 'client',
      );
    }

    // 记录 drop 原因
    if (decision.reason != null && decision.action == KeepSyncAction.noop) {
      _metrics.recordDrop(decision.reason!);
    }

    // 更新诊断数据
    _diagnostics.updatePartial(
      keepSyncEnabled: _keepSync.enabled,
      keepSyncDeltaMs: decision.deltaMs,
      keepSyncPredictedDeltaMs: decision.predictedDeltaMs,
      keepSyncTargetPosMs: decision.targetPosMs,
      keepSyncClientPosMs: decision.clientPosMs,
      keepSyncSpeed: _keepSync.currentSpeed,
      keepSyncSpeedEma: _keepSync.speedEma,
      keepSyncSpeedCmd: decision.speedCmd,
      keepSyncHoldRemainingMs: decision.holdRemainingMs,
      keepSyncLastAction: decision.action.name,
      keepSyncSeekCount: _keepSync.seekCount,
      keepSyncSpeedSetCount: _keepSync.speedSetCount,
      keepSyncDroppedCount: _keepSync.droppedHostStateCount,
      keepSyncDroppedReason: _keepSync.lastDroppedReason,
      keepSyncReason: decision.reason,
      // 实时更新延迟补偿值
      latencyCompMs: _calibration.totalCompensationMs,
    );

    // 检查保护模式
    final protectMode = _metrics.protectMode;

    // 执行决策（保护模式下限制）
    switch (decision.action) {
      case KeepSyncAction.noop:
        break;
      case KeepSyncAction.speed:
        if (Platform.isIOS) {
          SyncLog.i(
            '[KeepSync] iOS 禁止 speed 调整（避免追快追慢）: speed=${decision.speed} delta=${decision.deltaMs}',
            role: 'client',
          );
          break;
        }
        // 保护模式下检查是否允许速度调整
        if (protectMode == ProtectMode.protect) {
          // 保护模式下使用更保守的速度范围
          final clampedSpeed = decision.speed!.clamp(0.985, 1.015);
          _player!.setSpeed(clampedSpeed);
          SyncLog.i('[KeepSync] 设置速度（保护模式）: $clampedSpeed', role: 'client');
        } else {
          _player!.setSpeed(decision.speed!);
          SyncLog.i('[KeepSync] 设置速度: ${decision.speed}', role: 'client');
        }
      case KeepSyncAction.seek:
        // 保护模式下禁止小偏移 seek（除非 > 2000ms）
        if (protectMode == ProtectMode.protect &&
            decision.deltaMs.abs() < 2000) {
          SyncLog.w(
            '[KeepSync] 保护模式禁止 seek: delta=${decision.deltaMs}ms',
            role: 'client',
          );
        } else {
          // 记录 seek 时间和目标，用于冷却期检查
          _lastSeekAtMs = DateTime.now().millisecondsSinceEpoch;
          _lastSeekTargetMs = decision.seekMs!;
          _player!.seek(Duration(milliseconds: decision.seekMs!));
          SyncLog.i('[KeepSync] 跳转: ${decision.seekMs}ms', role: 'client');
        }
    }
  }

  /// 检查条件并可能触发追帧
  void _maybeTriggerCatchUp() {
    // 更新条件状态
    _trackReadyForCatchUp =
        _trackState.status == TrackStatus.serving &&
        _trackState.meta?.localPath.isNotEmpty == true;
    _clockLockedForCatchUp = _clock.isLocked;

    SyncLog.i(
      '[CatchUp] maybeTrigger: hostPlaying=$_hasHostStatePlaying trackReady=$_trackReadyForCatchUp clockLocked=$_clockLockedForCatchUp',
      role: 'client',
    );

    // 三条件同时满足才触发
    if (_hasHostStatePlaying &&
        _trackReadyForCatchUp &&
        _clockLockedForCatchUp) {
      _tryCatchUp();
    }
  }

  /// 尝试追帧（三重 gate）
  void _tryCatchUp() {
    if (_latestHostState == null) {
      SyncLog.d('[CatchUp] 跳过: 无 host_state', role: 'client');
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final epoch = _latestHostState!.epoch;

    SyncLog.i(
      '[CatchUp] 尝试追帧: epoch=$epoch _catchUpDoneEpoch=$_catchUpDoneEpoch _catchUpInFlight=$_catchUpInFlight',
      role: 'client',
    );

    // Gate 1: 已在追帧中
    if (_catchUpInFlight) {
      SyncLog.i('[CatchUp] Gate1 阻止: 正在追帧', role: 'client');
      return;
    }

    // Gate 2: 同一 epoch 已追帧
    if (_catchUpDoneEpoch == epoch) {
      SyncLog.i('[CatchUp] Gate2 阻止: epoch $epoch 已追帧完成', role: 'client');
      return;
    }

    // Gate 3: 1.5 秒内已尝试过
    if (nowMs - _lastCatchUpAttemptAtMs < 1500) {
      SyncLog.i(
        '[CatchUp] Gate3 阻止: 太频繁，距上次 ${nowMs - _lastCatchUpAttemptAtMs}ms',
        role: 'client',
      );
      return;
    }

    SyncLog.i('[CatchUp] 通过所有 Gate，开始执行追帧', role: 'client');

    // 通过 gate，标记尝试时间
    _lastCatchUpAttemptAtMs = nowMs;

    // 立即标记 in-flight 和 done（防止并发）
    _catchUpInFlight = true;
    _catchUpDoneEpoch = epoch;

    // 异步执行追帧
    _performCatchUp(_latestHostState!).whenComplete(() {
      _catchUpInFlight = false;
    });
  }

  /// 曲目缓存完成时检查是否需要追帧或自动播放
  void _onTrackReadyForCatchUp() {
    _trackReadyForCatchUp = true;

    // 如果 Host 正在播放且曲目已就绪，直接开始播放
    if (_hasHostStatePlaying && _latestHostState != null && _player == null) {
      final hostState = _latestHostState!;
      final localPath = _trackState.meta?.localPath;
      if (localPath != null && localPath.isNotEmpty) {
        // 异步初始化播放器并播放
        _initPlayerAndPlay(localPath, hostState.hostPosMs);
        return;
      }
    }

    _maybeTriggerCatchUp();
  }

  /// 初始化播放器并播放到指定位置
  Future<void> _initPlayerAndPlay(String localPath, int posMs) async {
    try {
      _player = AudioPlayer();
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await _player!.setFilePath(localPath);
      _player!.seek(Duration(milliseconds: posMs));
      await _player!.play();
      SyncLog.i('[Client] 曲目就绪后自动播放: pos=$posMs', role: 'client');
    } catch (e) {
      SyncLog.e('[Client] 初始化播放器失败', error: e);
    }
  }

  /// 时钟锁定时检查是否需要追帧
  void _onClockLockedForCatchUp() {
    _clockLockedForCatchUp = true;
    _maybeTriggerCatchUp();
  }

  /// 执行追帧（使用未来时刻精确播放）
  Future<void> _performCatchUp(HostStateMessage hostState) async {
    final localPath = _trackState.meta?.localPath;
    final durationMs = _trackState.meta?.durationMs ?? 0;
    final latencyCompMs = _calibration.totalCompensationMs;

    if (localPath == null || localPath.isEmpty) {
      SyncLog.e('[CatchUp] 无法追帧: localPath 为空', role: 'client');
      return;
    }

    SyncLog.i(
      '[CatchUp] 开始执行: localPath=$localPath durationMs=$durationMs latencyCompMs=$latencyCompMs',
      role: 'client',
    );

    // 计算未来播放时刻（当前时间 + 准备时间）
    const prepareMs = 300; // 预留 300ms 准备时间
    final targetRoomTimeMs = _clock.roomNowMs + prepareMs;

    // 计算在该时刻 Host 将会到达的位置
    // hostPosMs + (targetRoomTimeMs - sampledAtRoomTimeMs) - latencyCompMs
    final hostFuturePosMs =
        hostState.hostPosMs +
        (targetRoomTimeMs - hostState.sampledAtRoomTimeMs) -
        latencyCompMs;
    final clampedPosMs = hostFuturePosMs.clamp(0, durationMs);

    SyncLog.i(
      '[CatchUp] 计算结果: hostPosMs=${hostState.hostPosMs} 采样时间=${hostState.sampledAtRoomTimeMs} 目标房间时间=$targetRoomTimeMs hostFuturePosMs=$hostFuturePosMs 最终位置=$clampedPosMs',
      role: 'client',
    );

    try {
      // 确保播放器已初始化
      if (_player == null) {
        _player = AudioPlayer();
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
      }

      // 预加载并 seek 到目标位置
      await _player!.setFilePath(localPath);
      await _player!.seek(Duration(milliseconds: clampedPosMs));

      // 等待到目标时刻再播放
      final nowRoomMs = _clock.roomNowMs;
      final waitMs = targetRoomTimeMs - nowRoomMs;

      if (waitMs > 0) {
        SyncLog.i('[CatchUp] 等待 ${waitMs}ms 后在房间时间=$targetRoomTimeMs 播放');
        await Future.delayed(Duration(milliseconds: waitMs));
      }

      _player!.play();

      if (Platform.isIOS) {
        await _player!.setSpeed(1.0);
      }

      // 标记追帧完成
      _catchUpDoneEpoch = hostState.epoch;

      final actualStartRoomMs = _clock.roomNowMs;
      final startErrorMs = actualStartRoomMs - targetRoomTimeMs;

      // 更新诊断数据
      _diagnostics.updatePartial(
        lastHostStateAtRoomTimeMs: hostState.sampledAtRoomTimeMs,
        lastHostPosMs: hostState.hostPosMs,
        computedTargetPosMs: clampedPosMs,
        catchUpPerformed: true,
        catchUpDeltaMs: startErrorMs,
      );

      SyncLog.i(
        '[CatchUp] 成功: seekMs=$clampedPosMs 启动误差=$startErrorMs latencyComp=$latencyCompMs',
        role: 'client',
      );
    } catch (e) {
      SyncLog.e('[CatchUp] 失败: $e', role: 'client');
    }
  }

  /// 手动触发追帧（用于测试）
  Future<bool> manualCatchUp() async {
    if (_latestHostState == null) {
      SyncLog.w('[CatchUp] 尚未收到 host_state', role: 'client');
      return false;
    }

    // 检查条件
    _trackReadyForCatchUp =
        _trackState.status == TrackStatus.serving &&
        _trackState.meta?.localPath.isNotEmpty == true;
    _clockLockedForCatchUp = _clock.isLocked;

    if (!_trackReadyForCatchUp) {
      SyncLog.w('[CatchUp] 无法追帧: 曲目未就绪', role: 'client');
      return false;
    }
    if (!_clockLockedForCatchUp) {
      SyncLog.w('[CatchUp] 无法追帧: 时钟未锁定', role: 'client');
      return false;
    }

    // 临时重置 epoch 以允许手动触发
    _catchUpDoneEpoch = -1;
    _catchUpInFlight = false;

    await _performCatchUp(_latestHostState!);
    return true;
  }

  void _sendHello() {
    if (_roomId == null || _peerId == null) return;

    _transport.sendHello(
      roomId: _roomId!,
      peerId: _peerId!,
      deviceInfo: 'Flutter Client',
    );

    SyncLog.i('已发送 hello', role: 'client', roomId: _roomId);
  }

  void _onDownloadProgress(DownloadProgress progress) {
    _trackStateController.add(_trackState);
  }

  // ==================== Host 曲目管理 ====================

  /// 曲目状态流
  Stream<TrackState> get trackStateStream => _trackStateController.stream;

  /// 当前曲目状态
  TrackState get trackState => _trackState;

  /// 选择 MP3 文件（Host）
  Future<bool> selectMp3File(String filePath) async {
    if (_role != SyncRole.host) return false;

    _trackState = const TrackState(status: TrackStatus.selecting);
    _trackStateController.add(_trackState);

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _trackState = TrackState(
          status: TrackStatus.error,
          error: 'File not found: $filePath',
        );
        _trackStateController.add(_trackState);
        return false;
      }

      // 获取文件大小
      final sizeBytes = await file.length();

      // 计算 hash（在 isolate 中）
      _trackState = const TrackState(status: TrackStatus.hashing);
      _trackStateController.add(_trackState);

      final fileHash = await _executor.computeFileSha1(filePath);

      // 生成 trackId
      final trackId = TrackMeta.generateTrackId(fileHash);

      // 使用 AudioPlayer 获取音频时长
      int durationMs = 0;
      try {
        final tempPlayer = AudioPlayer();
        await tempPlayer.setFilePath(filePath);
        durationMs = tempPlayer.duration?.inMilliseconds ?? 0;
        await tempPlayer.dispose();
        SyncLog.i('[Host] Got audio duration: ${durationMs}ms', role: 'host');
      } catch (e) {
        SyncLog.w('[Host] Failed to get audio duration: $e', role: 'host');
      }

      // 创建曲目元数据
      final trackMeta = TrackMeta(
        trackId: trackId,
        localPath: filePath,
        fileName: filePath.split(Platform.pathSeparator).last,
        sizeBytes: sizeBytes,
        durationMs: durationMs,
        fileHash: fileHash,
        createdAt: DateTime.now(),
      );

      // 添加到播放列表
      addToPlaylist(trackMeta);

      _trackState = TrackState(status: TrackStatus.ready, meta: trackMeta);
      _trackStateController.add(_trackState);

      SyncLog.i(
        '[Host] MP3 selected: $trackId, size=$sizeBytes, hash=$fileHash',
        role: 'host',
      );

      // 自动开始分发曲目
      final serving = await startServingTrack();
      if (!serving) {
        SyncLog.w('[Host] 自动分发曲目失败', role: 'host');
      }

      return true;
    } catch (e) {
      _trackState = TrackState(status: TrackStatus.error, error: e.toString());
      _trackStateController.add(_trackState);
      return false;
    }
  }

  /// 启动 HTTP 文件服务并广播曲目（Host）
  Future<bool> startServingTrack() async {
    if (_role != SyncRole.host || _trackState.meta == null) {
      SyncLog.e(
        '[Host] startServingTrack: role=$_role, meta=${_trackState.meta}',
      );
      return false;
    }

    final meta = _trackState.meta!;
    SyncLog.i(
      '[Host] startServingTrack: trackId=${meta.trackId}, localPath=${meta.localPath}, size=${meta.sizeBytes}',
      role: 'host',
    );

    // 获取客户端 IP，用于确定正确的网络接口
    final clientIp = _transport.getFirstClientIp();
    String? preferredIp;
    if (clientIp != null) {
      // 根据客户端 IP 选择匹配的本地 IP
      preferredIp = await _selectMatchingLocalIp(clientIp);
      SyncLog.i(
        '[Host] Client IP: $clientIp, selected local IP: $preferredIp',
        role: 'host',
      );
    }

    // 启动 HTTP 文件服务器（使用选定的 IP）
    final started = await _httpFileServer.start(
      track: meta,
      preferredIp: preferredIp,
    );
    if (!started) {
      _trackState = TrackState(
        status: TrackStatus.error,
        meta: meta,
        error: 'Failed to start HTTP server',
      );
      _trackStateController.add(_trackState);
      return false;
    }

    // 获取 serviceUrl 并检查
    final serviceUrl = _httpFileServer.serviceUrl;
    SyncLog.i(
      '[Host] HTTP server started, serviceUrl=$serviceUrl',
      role: 'host',
    );

    if (serviceUrl.isEmpty) {
      SyncLog.e(
        '[Host] serviceUrl is empty after HTTP server started!',
        role: 'host',
      );
      _trackState = TrackState(
        status: TrackStatus.error,
        meta: meta,
        error: 'serviceUrl is empty',
      );
      _trackStateController.add(_trackState);
      return false;
    }

    _trackState = TrackState(status: TrackStatus.serving, meta: meta);
    _trackStateController.add(_trackState);

    // 广播曲目公告
    final announce = TrackAnnounceMessage(
      roomId: _roomId!,
      hostPeerId: _peerId!,
      trackId: meta.trackId,
      url: serviceUrl,
      fileHash: meta.fileHash,
      sizeBytes: meta.sizeBytes,
      durationMs: meta.durationMs,
      fileName: meta.fileName,
    );

    SyncLog.i(
      '[Host] Broadcasting track_announce: trackId=${announce.trackId}, url=${announce.url}, size=${announce.sizeBytes}',
      role: 'host',
    );

    _transport.broadcast(
      TransportMessage.create(announce.type, announce.toJson()),
    );

    return true;
  }

  /// 向指定 Client 发送曲目公告（新 Client 加入时调用）
  void _sendTrackAnnounceToPeer(String clientPeerId) {
    if (_trackState.meta == null) {
      SyncLog.w('[Host] _sendTrackAnnounceToPeer: 无曲目信息', role: 'host');
      return;
    }

    final meta = _trackState.meta!;
    final serviceUrl = _httpFileServer.serviceUrl;
    if (serviceUrl.isEmpty) {
      SyncLog.w(
        '[Host] _sendTrackAnnounceToPeer: HTTP 服务 URL 为空',
        role: 'host',
      );
      return;
    }

    if (_roomId == null) {
      SyncLog.w('[Host] _sendTrackAnnounceToPeer: roomId 为 null', role: 'host');
      return;
    }

    final announce = TrackAnnounceMessage(
      roomId: _roomId!,
      hostPeerId: _peerId!,
      trackId: meta.trackId,
      url: serviceUrl,
      fileHash: meta.fileHash,
      sizeBytes: meta.sizeBytes,
      durationMs: meta.durationMs,
      fileName: meta.fileName,
    );

    SyncLog.i(
      '[Host] Sending track_announce to new client: $clientPeerId, trackId=${announce.trackId}, url=$serviceUrl',
      role: 'host',
    );

    _transport.sendToPeer(
      clientPeerId,
      TransportMessage.create(announce.type, announce.toJson()),
    );
  }

  /// 向新 Client 发送当前播放状态（让它能自动跟随播放）
  void _sendCurrentStateToNewClient(String clientPeerId) {
    if (_hostPlayer == null || _trackState.meta == null) return;

    final isPlaying = _hostPlayer!.playing;
    final hostPosMs = _hostPlayer!.position.inMilliseconds;
    final sampledAtRoomTimeMs = _clock.roomNowMs;

    // 发送 host_state 给新 Client
    final hostState = HostStateMessage(
      roomId: _roomId ?? '',
      trackId: _trackState.meta?.trackId ?? '',
      isPlaying: isPlaying,
      hostPosMs: hostPosMs,
      sampledAtRoomTimeMs: sampledAtRoomTimeMs,
      epoch: _epoch,
      seq: 0,
    );

    _transport.sendToPeer(
      clientPeerId,
      TransportMessage.create(hostState.type, hostState.toJson()),
    );

    SyncLog.i(
      '[Host] 发送当前播放状态给新 Client: $clientPeerId, isPlaying=$isPlaying, pos=$hostPosMs',
      role: 'host',
    );
  }

  /// 停止曲目服务（Host）
  Future<void> stopServingTrack() async {
    await _httpFileServer.stop();
    _trackState = const TrackState();
    _trackStateController.add(_trackState);
  }

  // ==================== FutureStart 同起开播 ====================

  /// Host 发起 FutureStart 同起开播
  /// 条件：已选择 track、HTTP server running
  Future<bool> startAtFuture() async {
    SyncLog.i('[Host] startAtFuture called, role=$_role', role: 'host');

    if (_role != SyncRole.host) {
      SyncLog.e('[Host] startAtFuture: not host role');
      return false;
    }

    if (_trackState.meta == null) {
      SyncLog.e(
        '[Host] startAtFuture: no track selected, status=${_trackState.status}',
      );
      return false;
    }

    SyncLog.i(
      '[Host] startAtFuture: trackId=${_trackState.meta!.trackId}, httpRunning=${_httpFileServer.isRunning}',
    );

    if (!_httpFileServer.isRunning) {
      SyncLog.e('[Host] startAtFuture: HTTP server not running');
      return false;
    }

    // Host 作为时钟源，不需要检查 isClockLocked

    // 递增 epoch 和 seq
    _epoch++;
    _seq = 0;

    final trackId = _trackState.meta!.trackId;
    final startAtRoomTimeMs = _clock.roomNowMs + _leadMs;
    const startPosMs = 0;

    _startAtRoomTimeMs = startAtRoomTimeMs;
    _futureStartState = FutureStartState.waiting;

    SyncLog.i(
      '[Host] FutureStart: epoch=$_epoch seq=$_seq T=$startAtRoomTimeMs leadMs=$_leadMs',
      role: 'host',
    );

    // 广播 start_at 消息
    final message = StartAtMessage(
      epoch: _epoch,
      seq: _seq,
      trackId: trackId,
      startAtRoomTimeMs: startAtRoomTimeMs,
      startPosMs: startPosMs,
    );

    _transport.broadcast(
      TransportMessage.create(message.type, message.toJson()),
    );

    // Host 自己也执行 FutureStart
    await _executeHostFutureStart(
      trackId: trackId,
      startAtRoomTimeMs: startAtRoomTimeMs,
      startPosMs: startPosMs,
    );

    return true;
  }

  /// 初始化 Host 播放器并设置监听
  Future<void> _ensureHostPlayerInitialized() async {
    if (_hostPlayer == null) {
      _hostPlayer = AudioPlayer();
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      // 监听播放位置并分发
      _hostPlayer!.positionStream.listen((pos) {
        _positionController.add(pos);
      });

      // 监听播放状态并分发
      _hostPlayer!.playerStateStream.listen((state) {
        _playerStateController.add(state);
      });

      // 监听播放完成事件
      _hostPlayerStateSub?.cancel();
      _hostPlayerStateSub = _hostPlayer!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          SyncLog.i('[Host] 播放完成，自动播放下一首', role: 'host');
          nextTrack();
        }
      });
    }
  }

  /// Host 执行 FutureStart（播放本地 MP3）
  Future<void> _executeHostFutureStart({
    required String trackId,
    required int startAtRoomTimeMs,
    required int startPosMs,
  }) async {
    // 准备：初始化并加载播放器
    _futureStartState = FutureStartState.preparing;

    final localPath = _trackState.meta!.localPath;
    try {
      // 使用统一初始化方法确保监听被正确设置
      await _ensureHostPlayerInitialized();

      await _hostPlayer!.setFilePath(localPath);
      if (startPosMs > 0) {
        await _hostPlayer!.seek(Duration(milliseconds: startPosMs));
      }
    } catch (e) {
      SyncLog.e('[Host] FutureStart prepare failed: $e', role: 'host');
      _futureStartState = FutureStartState.failed;
      return;
    }

    SyncLog.i('[Host] FutureStart prepared: $trackId', role: 'host');

    // 两段式等待 - 重新计算剩余时间
    _futureStartState = FutureStartState.waiting;
    const fineWaitMs = 80;
    final nowAfterPrepareMs = _clock.roomNowMs;
    final remainingWaitMs = startAtRoomTimeMs - nowAfterPrepareMs;

    if (remainingWaitMs <= 0) {
      // 时间已过，立即启动
      SyncLog.w(
        '[Host] FutureStart target time passed during prepare',
        role: 'host',
      );
      _actualStartRoomTimeMs = _clock.roomNowMs;
      _startErrorMs = _actualStartRoomTimeMs - startAtRoomTimeMs;
      _futureStartState = FutureStartState.started;
      _hostPlayer?.play();
      return;
    }

    final coarseWaitMs = remainingWaitMs - fineWaitMs;

    Timer? coarseTimer;
    Timer? fineTimer;

    void executeStart() {
      coarseTimer?.cancel();
      fineTimer?.cancel();

      _actualStartRoomTimeMs = _clock.roomNowMs;
      _startErrorMs = _actualStartRoomTimeMs - startAtRoomTimeMs;
      _futureStartState = FutureStartState.started;

      SyncLog.i(
        '[Host] FutureStart started: actual=$_actualStartRoomTimeMs errorMs=$_startErrorMs',
        role: 'host',
      );

      _hostPlayer?.play();

      // 启动 Host 状态广播
      _startHostStateBroadcast();

      // 短暂延迟后回到 idle
      Timer(const Duration(seconds: 2), () {
        _futureStartState = FutureStartState.idle;
      });
    }

    void enterFineWait() {
      fineTimer = Timer.periodic(const Duration(milliseconds: 2), (timer) {
        final remainingMs = startAtRoomTimeMs - _clock.roomNowMs;
        if (remainingMs <= 0) {
          timer.cancel();
          executeStart();
        }
      });
    }

    if (coarseWaitMs > 0) {
      coarseTimer = Timer(Duration(milliseconds: coarseWaitMs), enterFineWait);
    } else {
      enterFineWait();
    }
  }

  // ==================== Client 下载管理 ====================

  /// 启动 Host 状态广播（每 200ms）
  void _startHostStateBroadcast() {
    _hostStateTimer?.cancel();
    _hostStateSeq = 0;

    _hostStateTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _broadcastHostState();
    });

    SyncLog.i('[Host] Started host_state broadcast', role: 'host');
  }

  /// 停止 Host 状态广播
  void _stopHostStateBroadcast() {
    _hostStateTimer?.cancel();
    _hostStateTimer = null;
    SyncLog.i('[Host] Stopped host_state broadcast', role: 'host');
  }

  /// 广播 Host 状态
  void _broadcastHostState() {
    if (_role != SyncRole.host || _hostPlayer == null) return;

    final isPlaying = _hostPlayer!.playing;
    final hostPosMs = _hostPlayer!.position.inMilliseconds;
    final sampledAtRoomTimeMs = _clock.roomNowMs;

    final message = HostStateMessage(
      roomId: _roomId ?? '',
      trackId: _trackState.meta?.trackId ?? '',
      isPlaying: isPlaying,
      hostPosMs: hostPosMs,
      sampledAtRoomTimeMs: sampledAtRoomTimeMs,
      epoch: _epoch,
      seq: _hostStateSeq++,
    );

    _transport.broadcast(
      TransportMessage.create(message.type, message.toJson()),
    );

    // 同时通知 Host 自身的 UI 更新进度
    _updateState();

    SyncLog.d(
      '[Host] Broadcast host_state: isPlaying=$isPlaying pos=$hostPosMs sampledAt=$sampledAtRoomTimeMs',
      role: 'host',
    );
  }

  // ==================== Client 下载管理 ====================

  /// 下载并缓存曲目（Client）
  Future<DownloadResult> downloadTrack({
    required String trackId,
    required String url,
    required String expectedHash,
    required int expectedSize,
  }) async {
    return await _cache.downloadAndCache(
      trackId: trackId,
      url: url,
      expectedHash: expectedHash,
      expectedSize: expectedSize,
    );
  }

  /// 获取下载进度
  DownloadProgress get downloadProgress => _cache.currentProgress;

  /// 获取下载进度流
  Stream<DownloadProgress> get cacheProgressStream => _cache.progressStream;

  /// 清除曲目缓存
  Future<void> clearTrackCache(String trackId) async {
    await _cache.clearCache();
    await _stopPlayer();
    _trackState = const TrackState();
    _trackStateController.add(_trackState);
  }

  /// 重试下载曲目（Client）
  /// 当下载失败时，使用保存的元数据重新下载
  Future<bool> retryDownload() async {
    if (_role != SyncRole.client) {
      SyncLog.w('[Client] retryDownload: not client role');
      return false;
    }

    final meta = _trackState.meta;
    if (meta == null || meta.url == null || meta.url!.isEmpty) {
      SyncLog.w('[Client] retryDownload: no track meta or url');
      return false;
    }

    SyncLog.i(
      '[Client] 重试下载: trackId=${meta.trackId} url=${meta.url}',
      role: 'client',
    );

    // 重置状态为下载中
    _trackState = TrackState(status: TrackStatus.announcing, meta: meta);
    _trackStateController.add(_trackState);

    // 重新下载
    final result = await _cache.downloadAndCache(
      trackId: meta.trackId,
      url: meta.url!,
      expectedHash: meta.fileHash,
      expectedSize: meta.sizeBytes,
    );

    if (result.success) {
      // 发送 ready 消息
      final readyMsg = ClientReadyMessage(
        roomId: _roomId ?? '',
        peerId: _peerId!,
        trackId: meta.trackId,
        cached: true,
        localPath: result.localPath!,
        prepareMs: result.prepareMs,
      );
      _transport.send(
        TransportMessage.create(readyMsg.type, readyMsg.toJson()),
      );

      SyncLog.i('[Client] 重试下载成功: ${meta.trackId}', role: 'client');

      _trackState = TrackState(
        status: TrackStatus.serving,
        meta: meta.copyWith(localPath: result.localPath!),
      );
      _trackStateController.add(_trackState);

      // 预先初始化播放器
      await _preInitPlayer(result.localPath!);
      return true;
    } else {
      // 发送错误消息
      final errorMsg = ClientReadyErrorMessage(
        roomId: _roomId ?? '',
        peerId: _peerId!,
        trackId: meta.trackId,
        errorCode: result.errorCode ?? 'unknown',
        errorMessage: result.errorMessage ?? 'Unknown error',
      );
      _transport.send(
        TransportMessage.create(errorMsg.type, errorMsg.toJson()),
      );

      SyncLog.e('[Client] 重试下载失败: ${result.errorCode}', role: 'client');

      _trackState = TrackState(
        status: TrackStatus.error,
        meta: meta,
        error: result.errorMessage,
      );
      _trackStateController.add(_trackState);
      return false;
    }
  }

  /// 获取已缓存的曲目列表
  Future<List<CachedTrack>> getCachedTracks() async {
    return await _cache.getCachedTracks();
  }

  // ==================== Client 播放器 ====================

  /// 播放缓存文件
  Future<bool> playCachedTrack(String localPath) async {
    if (_role != SyncRole.client) {
      SyncLog.w('[Client] playCachedTrack: not client role');
      return false;
    }

    try {
      // 初始化播放器
      if (_player == null) {
        _player = AudioPlayer();

        // 配置 audio session
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());

        // 监听 position
        _positionSub = _player!.positionStream.listen((position) {
          _positionController.add(position);
        });

        // 监听 player state
        _playerStateSub = _player!.playerStateStream.listen((state) {
          _playerStateController.add(state);
        });
      }

      // 停止当前播放
      await _player!.stop();

      // 设置文件路径并播放
      final duration = await _player!.setFilePath(localPath);
      SyncLog.i(
        '[Client] Playing cached track: $localPath, duration: $duration',
      );
      await _player!.play();
      return true;
    } catch (e, s) {
      SyncLog.e(
        '[Client] playCachedTrack failed: $localPath',
        error: e,
        stackTrace: s,
      );
      return false;
    }
  }

  /// 暂停播放
  Future<void> pausePlayer() async {
    await _player?.pause();
  }

  /// 继续播放
  Future<void> resumePlayer() async {
    await _player?.play();
  }

  /// 停止播放
  Future<void> _stopPlayer() async {
    await _player?.stop();
  }

  /// 播放状态流
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  /// 播放位置流
  Stream<Duration> get positionStream => _positionController.stream;

  /// 当前播放状态
  PlayerState? get playerState =>
      _player?.playerState ?? _hostPlayer?.playerState;

  /// 当前播放位置
  Duration? get position =>
      _role == SyncRole.host ? _hostPlayer?.position : _player?.position;

  /// 当前播放时长
  Duration? get duration =>
      _role == SyncRole.host ? _hostPlayer?.duration : _player?.duration;

  // ==================== 统一播放控制 ====================

  /// 播放（Host 播放本地 MP3，Client 播放缓存文件）
  Future<bool> play() async {
    if (_role == SyncRole.host) {
      return await _hostPlay();
    } else if (_role == SyncRole.client) {
      await resumePlayer();
      return _player?.playing ?? false;
    }
    return false;
  }

  /// 暂停
  Future<void> pause() async {
    if (_role == SyncRole.host) {
      await _hostPlayer?.pause();
      // Host 暂停时停止状态广播
      _stopHostStateBroadcast();
    } else if (_role == SyncRole.client) {
      await _player?.pause();
    }
  }

  /// Host 暂停并广播给所有 Client
  /// 本地播放模式（none）也可以使用
  Future<void> pauseAndBroadcast() async {
    // 暂停本地播放器
    await _hostPlayer?.pause();

    // 只有在房间内才广播
    if (_role == SyncRole.host && _roomId != null) {
      // 停止状态广播
      _stopHostStateBroadcast();

      // 广播暂停指令
      final message = PauseCommandMessage(
        roomId: _roomId ?? '',
        epoch: _epoch,
        pauseAtRoomTimeMs: _clock.roomNowMs,
      );

      _transport.broadcast(
        TransportMessage.create(message.type, message.toJson()),
      );

      SyncLog.i('[Host] Broadcast pause command, epoch=$_epoch', role: 'host');
    }

    // 通知 UI 更新
    _stateController.add(
      SyncV2State(
        role: _role,
        roomId: _roomId,
        peerId: _peerId,
        diagnostics: _diagnostics.data,
      ),
    );
  }

  /// Host 恢复播放并广播给所有 Client
  /// 本地播放模式（none）也可以使用
  Future<void> resumeAndBroadcast() async {
    // 获取当前播放位置
    final currentPosMs = _hostPlayer?.position.inMilliseconds ?? 0;

    // 恢复本地播放器（从暂停位置继续）
    await _hostPlayer?.play();

    // 只有在房间内才广播
    if (_role == SyncRole.host && _roomId != null) {
      // 启动状态广播
      _startHostStateBroadcast();

      // 广播恢复播放指令（让 Client 从暂停位置继续，包含当前播放位置）
      final message = ResumeCommandMessage(
        roomId: _roomId ?? '',
        epoch: _epoch,
        resumeAtRoomTimeMs: _clock.roomNowMs,
        resumePosMs: currentPosMs, // 添加播放位置
      );

      _transport.broadcast(
        TransportMessage.create(message.type, message.toJson()),
      );

      SyncLog.i(
        '[Host] Resume playback and broadcast, epoch=$_epoch, pos=$currentPosMs',
        role: 'host',
      );
    } else if (_role == SyncRole.none) {
      SyncLog.i('[Playlist] 本地播放恢复: pos=$currentPosMs');
    }

    // 通知 UI 更新
    _stateController.add(
      SyncV2State(
        role: _role,
        roomId: _roomId,
        peerId: _peerId,
        diagnostics: _diagnostics.data,
      ),
    );
  }

  /// Seek 到指定位置（用于模拟偏移测试）
  /// [deltaMs] 偏移量，正数向前跳，负数向后跳
  Future<void> seek(int deltaMs) async {
    final player = _role == SyncRole.host ? _hostPlayer : _player;
    if (player == null) {
      SyncLog.w('[Seek] No player available', role: _role.name);
      return;
    }

    final currentPos = player.position.inMilliseconds;
    final duration = player.duration?.inMilliseconds ?? 0;
    final targetPos = (currentPos + deltaMs).clamp(0, duration);

    SyncLog.i(
      '[Seek] delta=$deltaMs ms, current=$currentPos ms -> target=$targetPos ms',
      role: _role.name,
    );

    await player.seek(Duration(milliseconds: targetPos));

    // 记录 seek 时间（用于 Client 冷却期检查）
    if (_role == SyncRole.client) {
      _lastSeekAtMs = DateTime.now().millisecondsSinceEpoch;
      _lastSeekTargetMs = targetPos;
    }
  }

  /// Host 跳转进度并广播给所有 Client
  Future<void> seekToAndBroadcast(int targetPosMs) async {
    if (_role != SyncRole.host) return;

    final duration = _hostPlayer?.duration?.inMilliseconds ?? 0;
    final clampedPos = targetPosMs.clamp(0, duration);

    SyncLog.i('[Host] Seek to $clampedPos ms and broadcast', role: 'host');

    // 跳转本地播放器
    await _hostPlayer?.seek(Duration(milliseconds: clampedPos));

    // 广播跳转指令给所有 Client
    final message = SeekCommandMessage(
      roomId: _roomId ?? '',
      epoch: _epoch,
      seekPosMs: clampedPos,
      seekAtRoomTimeMs: _clock.roomNowMs,
    );

    _transport.broadcast(
      TransportMessage.create(message.type, message.toJson()),
    );

    SyncLog.i(
      '[Host] Broadcast seek command: epoch=$_epoch, pos=$clampedPos',
      role: 'host',
    );
  }

  /// Host 播放本地 MP3
  Future<bool> _hostPlay() async {
    if (_role != SyncRole.host) return false;

    final meta = _trackState.meta;
    if (meta == null) {
      SyncLog.w('[Host] No track selected');
      return false;
    }

    try {
      // 使用统一初始化方法确保监听被正确设置
      await _ensureHostPlayerInitialized();

      // 如果正在播放，继续播放
      if (_hostPlayer!.playing) {
        return true;
      }

      // 如果已加载文件，继续播放
      if (_hostPlayer!.duration != null) {
        await _hostPlayer!.play();
        // Host 恢复播放时启动状态广播（只有在房间内才广播）
        if (_roomId != null) {
          _startHostStateBroadcast();
        }
        return true;
      }

      // 加载文件并播放
      final duration = await _hostPlayer!.setFilePath(meta.localPath);
      SyncLog.i(
        '[Host] Playing local track: ${meta.localPath}, duration: $duration',
      );
      await _hostPlayer!.play();

      // Host 播放时启动状态广播（只有在房间内才广播）
      if (_roomId != null) {
        _startHostStateBroadcast();
      }

      return true;
    } catch (e, s) {
      SyncLog.e('[Host] _hostPlay failed', error: e, stackTrace: s);
      return false;
    }
  }

  /// 是否正在播放
  bool get isPlaying {
    if (_role == SyncRole.host) {
      return _hostPlayer?.playing ?? false;
    } else if (_role == SyncRole.client) {
      return _player?.playing ?? false;
    }
    return false;
  }

  // ==================== Host 操作 ====================

  /// 创建房间（Host）
  Future<bool> createRoom({
    required String roomName,
    int wsPort = 8765,
    int httpPort = 8080,
    bool autoSelectTrack = true, // 自动选择最近曲目
  }) async {
    if (_role != SyncRole.none) {
      SyncLog.w('Already in a room', role: 'host');
      return false;
    }

    _roomId = 'room_${DateTime.now().millisecondsSinceEpoch}';
    _peerId = 'host_${DateTime.now().millisecondsSinceEpoch}';
    _role = SyncRole.host;

    // 发布 mDNS 服务
    final published = await _mdnsService.publishRoom(
      roomId: _roomId!,
      roomName: roomName,
      wsPort: wsPort,
      httpPort: httpPort,
      appVersion: '1.0.0',
    );

    if (!published) {
      _role = SyncRole.none;
      _roomId = null;
      _peerId = null;
      return false;
    }

    // 启动 WebSocket 服务器
    await _transport.startServer(wsPort);

    // 启动 HTTP 分发服务
    await _distributor.start(port: httpPort);

    // 初始化时钟 epoch
    _clock.newEpoch();

    _updateState();

    SyncLog.i('Room created', role: 'host', roomId: _roomId);

    _throttledNotifier.updatePartial(
      role: 'host',
      roomId: _roomId,
      peerId: _peerId,
      state: 'hosting',
      connectionState: 'hosting',
    );

    // 自动选择最近曲目
    if (autoSelectTrack) {
      await _autoSelectRecentTrack();
    }

    return true;
  }

  /// 自动选择最近曲目（Host 创建房间后）
  Future<bool> _autoSelectRecentTrack() async {
    try {
      final cachedTracks = await _cache.getCachedTracks();
      if (cachedTracks.isNotEmpty) {
        final recent = cachedTracks.first; // 已按时间排序
        SyncLog.i(
          '[Host] 自动选择最近曲目: ${recent.trackId} path=${recent.localPath}',
          role: 'host',
        );
        return await selectMp3File(recent.localPath);
      }
    } catch (e) {
      SyncLog.w('[Host] 自动选择曲目失败: $e', role: 'host');
    }
    return false;
  }

  /// 关闭房间（Host）
  Future<void> closeRoom() async {
    if (_role != SyncRole.host) return;

    await _mdnsService.unpublishRoom();
    await _transport.stopServer();
    await _distributor.stop();

    _role = SyncRole.none;
    _roomId = null;
    _peerId = null;

    _updateState();
    _throttledNotifier.reset();

    SyncLog.i('Room closed', role: 'host');
  }

  /// 设置音源（Host）
  Future<bool> setAudioSource(String filePath) async {
    if (_role != SyncRole.host) return false;

    final info = await _distributor.registerSource(
      sourceId: 'main',
      filePath: filePath,
    );

    return info != null;
  }

  // ==================== Client 操作 ====================

  /// 开始扫描房间
  Future<void> startScanning() async {
    // 如果已经是 host 或 client，不允许扫描
    if (_role != SyncRole.none) {
      SyncLog.w('[SyncV2] Cannot scan: already in a room', role: _role.name);
      return;
    }
    await _mdnsService.startScanning();
    _throttledNotifier.updatePartial(state: 'discovering');
  }

  /// 停止扫描房间
  Future<void> stopScanning() async {
    await _mdnsService.stopScanning();
    if (_role == SyncRole.none) {
      _throttledNotifier.updatePartial(state: 'idle');
    }
  }

  /// 加入房间（Client）
  /// 返回值: true=成功加入, false=失败, null=已在房间中
  Future<bool?> joinRoom(DiscoveredRoom room) async {
    if (_role != SyncRole.none) {
      SyncLog.w(
        '[SyncV2] Cannot join: current role=${_role.name}, roomId=$_roomId, peerId=$_peerId',
        role: 'client',
      );
      return null; // 已在房间中
    }

    _roomId = room.roomId;
    _peerId = 'client_${DateTime.now().millisecondsSinceEpoch}';
    _role = SyncRole.client;

    _throttledNotifier.updatePartial(
      role: 'client',
      roomId: _roomId,
      peerId: _peerId,
      state: 'joining',
      connectionState: 'connecting',
    );

    // 连接到 Host
    try {
      await _transport.connect(room.hostIp, room.hostWsPort);
      // hello 消息会在连接成功后自动发送
    } catch (e, s) {
      SyncLog.e('Failed to join room', role: 'client', error: e, stackTrace: s);
      _role = SyncRole.none;
      _roomId = null;
      _peerId = null;
      _throttledNotifier.updatePartial(
        state: 'error',
        errorMessage: e.toString(),
      );
      return false;
    }

    // 开始时钟同步
    _clockSync.startSyncing();

    // 监听时钟锁定事件
    _clock.lockStream.listen((isLocked) {
      if (isLocked) {
        _onClockLockedForCatchUp();
      }
    });

    _updateState();

    SyncLog.i('Joined room', role: 'client', roomId: _roomId);

    _throttledNotifier.updatePartial(state: 'syncing');

    return true;
  }

  /// 离开房间（Client）
  Future<void> leaveRoom() async {
    if (_role != SyncRole.client) return;

    _clockSync.stopSyncing();
    _playbackSync.stopSync();
    await _transport.disconnect();

    _role = SyncRole.none;
    _roomId = null;
    _peerId = null;

    _updateState();
    _throttledNotifier.reset();

    SyncLog.i('Left room', role: 'client');
  }

  /// 手动断开连接
  Future<void> disconnect() async {
    if (_role == SyncRole.client) {
      await _transport.disconnect();
    }
  }

  /// 手动触发重连
  Future<void> triggerReconnect() async {
    await _transport.triggerReconnect();
  }

  /// 手动输入 Host IP 加入（fallback 方案）
  /// 返回值: true=成功加入, false=失败, null=已在房间中
  Future<bool?> joinByIp(String hostIp, int wsPort) async {
    // 创建临时房间信息
    final tempRoom = DiscoveredRoom(
      roomId: 'manual_${DateTime.now().millisecondsSinceEpoch}',
      roomName: 'Manual Join',
      hostIp: hostIp,
      hostWsPort: wsPort,
      hostHttpPort: 8080,
      appVersion: '1.0.0',
      codec: 'mp3',
      discoveredAt: DateTime.now(),
    );

    return joinRoom(tempRoom);
  }

  // ==================== 播放同步操作 ====================

  /// 开始播放同步
  void startPlaybackSync({
    void Function(int positionMs)? onSeek,
    void Function(double speed)? onSpeedChange,
    int Function()? onGetPosition,
  }) {
    if (_role != SyncRole.client) return;

    _playbackSync.setCallbacks(
      onSeek: onSeek,
      onSpeedChange: onSpeedChange,
      onGetPosition: onGetPosition,
    );
    _playbackSync.startSync();
  }

  /// 停止播放同步
  void stopPlaybackSync() {
    _playbackSync.stopSync();
  }

  /// 校准延迟
  void calibrateLatency(int latencyMs) {
    _playbackSync.calibrateLatency(latencyMs);
  }

  // ==================== 诊断操作 ====================

  /// 获取诊断数据字符串
  String getDiagnosticsString() {
    return _diagnostics.data.toFormattedString();
  }

  void _updateState() {
    _stateController.add(state);
  }

  /// 释放资源
  void dispose() {
    _transportStateSub?.cancel();
    _transportMessageSub?.cancel();
    _hostPlayerStateSub?.cancel();
    _stopHostStateBroadcast();
    closeRoom();
    leaveRoom();
    _mdnsService.dispose();
    _transport.dispose();
    _clockSync.dispose();
    _futureStart.dispose();
    _playbackSync.dispose();
    _keepSync.dispose();
    _diagnostics.dispose();
    _stateController.close();
  }

  // ==================== KeepSync 控制 ====================

  /// 设置 KeepSync 启用状态
  void setKeepSyncEnabled(bool enabled) {
    _keepSync.setEnabled(enabled);
    SyncLog.i('[KeepSync] ${enabled ? "Enabled" : "Disabled"}', role: 'client');
  }

  /// KeepSync 是否启用
  bool get keepSyncEnabled => _keepSync.enabled;

  // ==================== 播放列表操作 ====================

  /// 添加曲目到播放列表
  void addToPlaylist(TrackMeta track) {
    // 检查是否已存在相同 fileHash 的曲目（同一文件）
    final existingIndex = _playlist.indexWhere(
      (t) => t.fileHash == track.fileHash,
    );
    if (existingIndex >= 0) {
      SyncLog.i(
        '[Playlist] 曲目已存在，跳过: ${track.fileName}, hash=${track.fileHash.substring(0, 8)}..., 索引=$existingIndex',
      );
      return;
    }

    _playlist.add(track);
    // 如果是第一首曲目，自动设置为当前曲目
    if (_currentIndex < 0 && _playlist.length == 1) {
      _currentIndex = 0;
      // 同步更新 _trackState 以保持 UI 一致
      _trackState = TrackState(status: TrackStatus.ready, meta: track);
      _trackStateController.add(_trackState);
    }
    SyncLog.i(
      '[Playlist] 添加曲目: ${track.trackId}, 总数=${_playlist.length}, 当前索引=$_currentIndex',
    );
    // 持久化保存
    _persistence.savePlaylist(_playlist, currentIndex: _currentIndex);
  }

  /// 清空播放列表
  void clearPlaylist() {
    _playlist.clear();
    _currentIndex = -1;
    SyncLog.i('[Playlist] 已清空');
    // 清除持久化数据
    _persistence.clearPlaylist();
  }

  /// 从持久化存储加载播放列表
  Future<void> loadPersistedPlaylist() async {
    final result = await _persistence.loadPlaylist();
    if (result.tracks.isNotEmpty) {
      _playlist.clear();
      _playlist.addAll(result.tracks);
      _currentIndex = result.currentIndex;
      if (_currentIndex >= 0 && _currentIndex < _playlist.length) {
        _trackState = TrackState(
          status: TrackStatus.ready,
          meta: _playlist[_currentIndex],
        );
        _trackStateController.add(_trackState);
      }
      SyncLog.i(
        '[Playlist] 从持久化加载: ${_playlist.length} 首, 当前索引=$_currentIndex',
      );
    }
  }

  /// 上一首（Host 端）
  /// 返回是否成功切换
  Future<bool> previousTrack() async {
    if (_role != SyncRole.host) {
      SyncLog.w('[Playlist] previousTrack: not host role');
      return false;
    }

    if (!hasPreviousTrack) {
      SyncLog.i('[Playlist] previousTrack: 没有上一首');
      return false;
    }

    // 先暂停当前播放
    await _hostPlayer?.pause();
    _stopHostStateBroadcast();

    _currentIndex--;
    final track = _playlist[_currentIndex];
    SyncLog.i(
      '[Playlist] 切换到上一首: index=$_currentIndex, trackId=${track.trackId}',
      role: 'host',
    );

    // 设置新曲目并开始分发
    return await _loadAndServeTrack(track);
  }

  /// 下一首（Host 端）
  /// 返回是否成功切换
  /// 根据播放模式决定下一首
  Future<bool> nextTrack() async {
    if (_role != SyncRole.host) {
      SyncLog.w('[Playlist] nextTrack: not host role');
      return false;
    }

    if (_playlist.isEmpty || _currentIndex < 0) {
      SyncLog.i('[Playlist] nextTrack: 播放列表为空');
      return false;
    }

    // 先暂停当前播放
    await _hostPlayer?.pause();
    _stopHostStateBroadcast();

    // 根据播放模式决定下一首
    int nextIndex;
    switch (_playMode) {
      case PlayMode.loop:
        // 列表循环：最后一首回到第一首
        if (_currentIndex >= _playlist.length - 1) {
          nextIndex = 0;
          SyncLog.i('[Playlist] 列表循环：回到第一首', role: 'host');
        } else {
          nextIndex = _currentIndex + 1;
        }
        break;
      case PlayMode.single:
        // 单曲循环：保持当前索引
        nextIndex = _currentIndex;
        SyncLog.i('[Playlist] 单曲循环', role: 'host');
        break;
      case PlayMode.shuffle:
        // 随机播放：从随机顺序中选取下一个
        if (_shuffleOrder.isEmpty) {
          _generateShuffleOrder();
        }
        final currentShuffleIndex = _shuffleOrder.indexOf(_currentIndex);
        if (currentShuffleIndex >= _shuffleOrder.length - 1) {
          // 重新生成随机顺序
          _generateShuffleOrder();
          nextIndex = _shuffleOrder.isNotEmpty ? _shuffleOrder[0] : 0;
        } else {
          nextIndex = _shuffleOrder[currentShuffleIndex + 1];
        }
        SyncLog.i('[Playlist] 随机播放: shuffleIndex=$nextIndex', role: 'host');
        break;
    }

    _currentIndex = nextIndex;
    final track = _playlist[_currentIndex];
    SyncLog.i(
      '[Playlist] 切换到下一首: index=$_currentIndex, trackId=${track.trackId}',
      role: 'host',
    );

    // 设置新曲目并开始分发
    return await _loadAndServeTrack(track);
  }

  /// 加载曲目并开始分发（内部方法）
  Future<bool> _loadAndServeTrack(TrackMeta track) async {
    try {
      // 更新曲目状态
      _trackState = TrackState(status: TrackStatus.ready, meta: track);
      _trackStateController.add(_trackState);

      // 重置 FutureStart 状态
      _futureStartState = FutureStartState.idle;
      _epoch++;
      _seq = 0;

      // 开始分发
      final success = await startServingTrack();
      if (!success) {
        SyncLog.e('[Playlist] 分发曲目失败: ${track.trackId}');
        return false;
      }

      // Host 需要加载并播放新曲目
      if (_role == SyncRole.host) {
        try {
          // 初始化播放器（如果尚未初始化）
          if (_hostPlayer == null) {
            _hostPlayer = AudioPlayer();
            final session = await AudioSession.instance;
            await session.configure(const AudioSessionConfiguration.music());
          }

          // 加载新曲目
          await _hostPlayer!.setFilePath(track.localPath);
          SyncLog.i(
            '[Host] 已加载新曲目: ${track.fileName}, duration=${_hostPlayer!.duration}',
            role: 'host',
          );

          // 等待 Client 准备好（最多等待 3 秒）
          final clientCount = peerCount;
          if (clientCount > 0) {
            SyncLog.i('[Host] 等待 $clientCount 个 Client 准备好...', role: 'host');
            // 使用 Future.wait 等待一段时间，让 Client 有时间下载
            await Future.delayed(const Duration(milliseconds: 500));
          }

          // 计算同步开播时间（给 Client 准备时间）
          final prepareMs = 1000; // 预留 1000ms 准备时间
          final startAtRoomTimeMs = _clock.roomNowMs + prepareMs;

          // 广播 start_at 消息让 Client 同步开始
          final startAtMsg = StartAtMessage(
            epoch: _epoch,
            seq: _seq++,
            trackId: track.trackId,
            startAtRoomTimeMs: startAtRoomTimeMs,
            startPosMs: 0, // 从头开始播放
          );

          _transport.broadcast(
            TransportMessage.create(startAtMsg.type, startAtMsg.toJson()),
          );

          SyncLog.i(
            '[Host] 已广播 start_at: epoch=$_epoch startAt=$startAtRoomTimeMs',
            role: 'host',
          );

          // Host 也使用 FutureStart 同步开播
          await _futureStart.schedule(
            params: FutureStartParams(
              epoch: _epoch,
              seq: _seq - 1,
              trackId: track.trackId,
              startAtRoomTimeMs: startAtRoomTimeMs,
              startPosMs: 0,
            ),
            onPrepare: (params) async {
              _futureStartState = FutureStartState.preparing;
              // 播放器已加载，无需重新加载
              return FutureStartResult(success: true);
            },
            onStart: (params) {
              _hostPlayer?.play();
              _startHostStateBroadcast();
              SyncLog.i('[Host] 切换曲目同步开播完成', role: 'host');
            },
          );

          SyncLog.i('[Host] 已开始播放新曲目', role: 'host');

          // 检查是否有下一首曲目，设置预缓存
          _announceNextTrack();
        } catch (e) {
          SyncLog.e('[Host] 加载播放曲目失败: ${track.trackId}', error: e);
          return false;
        }
      }

      return true;
    } catch (e) {
      SyncLog.e('[Playlist] 加载曲目失败: ${track.trackId}', error: e);
      return false;
    }
  }

  /// 广播下一首曲目预缓存公告
  void _announceNextTrack() {
    if (_role != SyncRole.host) return;

    if (_playlist.isEmpty || _currentIndex < 0) return;

    // 循环播放：下一首是第一首
    int nextIndex;
    if (_currentIndex >= _playlist.length - 1) {
      nextIndex = 0; // 循环回到第一首
    } else {
      nextIndex = _currentIndex + 1;
    }

    final nextTrack = _playlist[nextIndex];
    _httpFileServer.setNextTrack(nextTrack);

    final nextTrackUrl = _httpFileServer.nextTrackUrl;
    if (nextTrackUrl.isEmpty) {
      SyncLog.w('[Host] 下一首曲目 URL 为空', role: 'host');
      return;
    }

    final announce = NextTrackAnnounceMessage(
      roomId: _roomId!,
      hostPeerId: _peerId!,
      trackId: nextTrack.trackId,
      url: nextTrackUrl,
      fileHash: nextTrack.fileHash,
      sizeBytes: nextTrack.sizeBytes,
      durationMs: nextTrack.durationMs,
      fileName: nextTrack.fileName,
    );

    _transport.broadcast(
      TransportMessage.create(announce.type, announce.toJson()),
    );

    SyncLog.i('[Host] 已广播下一首预缓存: trackId=${nextTrack.trackId}', role: 'host');
  }

  /// 播放指定索引的曲目
  /// Host 端：同步播放并分发
  /// 无角色：本地播放（不需要房间）
  /// 返回是否成功切换
  Future<bool> playTrackAtIndex(int index) async {
    if (index < 0 || index >= _playlist.length) {
      SyncLog.w('[Playlist] playTrackAtIndex: invalid index=$index');
      return false;
    }

    final track = _playlist[index];

    // Host 角色：同步播放
    if (_role == SyncRole.host) {
      // 先暂停当前播放
      await _hostPlayer?.pause();
      _stopHostStateBroadcast();

      _currentIndex = index;
      SyncLog.i(
        '[Playlist] Host 切换曲目: index=$_currentIndex, trackId=${track.trackId}',
        role: 'host',
      );

      return await _loadAndServeTrack(track);
    }

    // 无角色：本地播放模式
    if (_role == SyncRole.none) {
      _currentIndex = index;
      SyncLog.i(
        '[Playlist] 本地播放: index=$_currentIndex, trackId=${track.trackId}',
      );

      return await _playLocal(track);
    }

    // Client 角色：不支持主动切换曲目
    SyncLog.w(
      '[Playlist] playTrackAtIndex: client role cannot control playback',
    );
    return false;
  }

  /// 本地播放（不需要房间）
  Future<bool> _playLocal(TrackMeta track) async {
    try {
      // 初始化本地播放器
      if (_hostPlayer == null) {
        _hostPlayer = AudioPlayer();
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());

        // 监听播放完成事件
        _hostPlayerStateSub?.cancel();
        _hostPlayerStateSub = _hostPlayer!.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            SyncLog.i('[Playlist] 播放完成，自动播放下一首, role=$_role');
            if (_role == SyncRole.host && _roomId != null) {
              // 房间内使用 nextTrack 广播给客户端
              nextTrack();
            } else {
              // 本地播放使用 _playNextTrackLocal
              _playNextTrackLocal();
            }
          }
        });
      }

      // 加载曲目
      await _hostPlayer!.setFilePath(track.localPath);

      SyncLog.i(
        '[Playlist] 本地播放加载完成: ${track.fileName}, duration=${_hostPlayer!.duration}',
      );

      // 开始播放
      _hostPlayer!.play();

      // 更新曲目状态
      _trackState = TrackState(status: TrackStatus.ready, meta: track);
      _trackStateController.add(_trackState);

      // 通知 UI 更新
      _updateState();

      SyncLog.i('[Playlist] 本地播放开始: ${track.fileName}');
      return true;
    } catch (e) {
      SyncLog.e('[Playlist] 本地播放失败: ${track.trackId}', error: e);
      return false;
    }
  }

  /// 本地播放下一首（根据播放模式）
  Future<void> _playNextTrackLocal() async {
    if (_playlist.isEmpty || _currentIndex < 0) {
      SyncLog.i('[Playlist] 播放列表为空，无法播放下一首');
      return;
    }

    // 根据播放模式决定下一首
    int nextIndex;
    switch (_playMode) {
      case PlayMode.loop:
        // 列表循环
        if (_currentIndex >= _playlist.length - 1) {
          nextIndex = 0;
          SyncLog.i('[Playlist] 列表循环：回到第一首');
        } else {
          nextIndex = _currentIndex + 1;
        }
        break;
      case PlayMode.single:
        // 单曲循环
        nextIndex = _currentIndex;
        SyncLog.i('[Playlist] 单曲循环');
        break;
      case PlayMode.shuffle:
        // 随机播放
        if (_shuffleOrder.isEmpty) {
          _generateShuffleOrder();
        }
        final currentShuffleIndex = _shuffleOrder.indexOf(_currentIndex);
        if (currentShuffleIndex >= _shuffleOrder.length - 1) {
          _generateShuffleOrder();
          nextIndex = _shuffleOrder.isNotEmpty ? _shuffleOrder[0] : 0;
        } else {
          nextIndex = _shuffleOrder[currentShuffleIndex + 1];
        }
        SyncLog.i('[Playlist] 随机播放: index=$nextIndex');
        break;
    }

    _currentIndex = nextIndex;
    final track = _playlist[_currentIndex];
    SyncLog.i(
      '[Playlist] 自动播放下一首: index=$_currentIndex, trackId=${track.trackId}',
    );

    await _playLocal(track);
    _updateState();
  }

  /// 根据客户端 IP 选择匹配的本地 IP
  /// 选择与客户端在同一子网的本地 IP
  Future<String?> _selectMatchingLocalIp(String clientIp) async {
    try {
      final interfaces = await NetworkInterface.list();

      // 解析客户端 IP 的子网前缀
      final clientParts = clientIp.split('.');
      if (clientParts.length != 4) {
        SyncLog.w('[Host] Invalid client IP format: $clientIp');
        return null;
      }

      // 尝试找到同一子网的本地 IP
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final localParts = addr.address.split('.');
            if (localParts.length == 4) {
              // 检查前三段是否相同（/24 子网）
              if (clientParts[0] == localParts[0] &&
                  clientParts[1] == localParts[1] &&
                  clientParts[2] == localParts[2]) {
                SyncLog.i(
                  '[Host] Found matching subnet: client=$clientIp, local=${addr.address}',
                  role: 'host',
                );
                return addr.address;
              }
            }
          }
        }
      }

      // 如果没有找到同一子网的，返回第一个非回环 IPv4 地址
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            SyncLog.w(
              '[Host] No matching subnet found, using first available: ${addr.address}',
              role: 'host',
            );
            return addr.address;
          }
        }
      }

      return null;
    } catch (e) {
      SyncLog.e('[Host] Error selecting local IP', error: e);
      return null;
    }
  }
}
