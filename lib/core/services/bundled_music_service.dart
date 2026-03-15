import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../sync_v2/distributor/track_meta.dart';

/// 自带音乐信息
class BundledMusic {
  final String id;
  final String assetPath;
  final String displayName;
  final String artist;
  final int durationMs;

  const BundledMusic({
    required this.id,
    required this.assetPath,
    required this.displayName,
    required this.artist,
    this.durationMs = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'assetPath': assetPath,
    'displayName': displayName,
    'artist': artist,
    'durationMs': durationMs,
  };
}

/// 自带音乐服务
/// 管理 App 内置的示例音乐文件
/// 支持格式: MP3, AAC, M4A, WAV, OGG, FLAC
class BundledMusicService {
  static const BundledMusicService _instance = BundledMusicService._internal();
  factory BundledMusicService() => _instance;
  const BundledMusicService._internal();

  /// 支持的音频格式
  static const List<String> supportedFormats = [
    'mp3',
    'aac',
    'm4a',
    'wav',
    'ogg',
    'flac',
  ];

  /// 自带音乐列表
  /// 注意：需要在 assets/audio/ 目录下放置对应的音频文件
  /// 支持中文文件名和中文歌曲信息
  static const List<BundledMusic> bundledTracks = [
    BundledMusic(
      id: 'yong_chun',
      assetPath: 'assets/audio/咏春-七朵组合.aac',
      displayName: '咏春',
      artist: '七朵组合',
    ),
    BundledMusic(
      id: 'yang_zhou_man',
      assetPath: 'assets/audio/扬州慢-七朵组合.mp3',
      displayName: '扬州慢',
      artist: '七朵组合',
    ),
    BundledMusic(
      id: 'yu_sheng_yan',
      assetPath: 'assets/audio/玉生烟-七朵组合.aac',
      displayName: '玉生烟',
      artist: '七朵组合',
    ),
    BundledMusic(
      id: 'qing_she',
      assetPath: 'assets/audio/青蛇-七朵组合.aac',
      displayName: '青蛇',
      artist: '七朵组合',
    ),
  ];

  /// 获取自带音乐列表
  List<BundledMusic> get tracks => bundledTracks;

  /// 是否有自带音乐
  bool get hasBundledMusic => bundledTracks.isNotEmpty;

  /// 将 asset 文件复制到本地缓存目录
  /// 返回本地文件路径
  Future<String?> copyAssetToCache(String assetPath, String fileName) async {
    try {
      // 获取应用缓存目录
      final cacheDir = await getApplicationCacheDirectory();
      final localPath = '${cacheDir.path}/bundled_music/$fileName';

      // 检查是否已存在
      final localFile = File(localPath);
      if (await localFile.exists()) {
        return localPath;
      }

      // 确保目录存在
      final dir = Directory('${cacheDir.path}/bundled_music');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 从 asset 加载并写入本地文件
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List();
      await localFile.writeAsBytes(bytes);

      debugPrint('[BundledMusicService] 已复制: $assetPath -> $localPath');
      return localPath;
    } catch (e) {
      debugPrint('[BundledMusicService] 复制 asset 失败: $e');
      return null;
    }
  }

  /// 将自带音乐转换为 TrackMeta
  /// 会复制文件到本地缓存并计算 hash
  Future<TrackMeta?> toTrackMeta(BundledMusic track) async {
    try {
      final fileName = track.assetPath.split('/').last;
      final localPath = await copyAssetToCache(track.assetPath, fileName);

      if (localPath == null) {
        debugPrint('[BundledMusicService] 无法复制文件: ${track.assetPath}');
        return null;
      }

      final file = File(localPath);
      final bytes = await file.readAsBytes();
      final sizeBytes = bytes.length;

      // 计算 hash
      final hash = sha256.convert(bytes).toString();

      // 生成 trackId
      final trackId = TrackMeta.generateTrackId(hash);

      return TrackMeta(
        trackId: trackId,
        localPath: localPath,
        fileName: '${track.artist} - ${track.displayName}',
        sizeBytes: sizeBytes,
        durationMs: track.durationMs,
        fileHash: hash,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[BundledMusicService] 转换 TrackMeta 失败: $e');
      return null;
    }
  }

  /// 获取所有自带音乐的 TrackMeta 列表
  Future<List<TrackMeta>> getAllTrackMetas() async {
    final metas = <TrackMeta>[];
    for (final track in bundledTracks) {
      final meta = await toTrackMeta(track);
      if (meta != null) {
        metas.add(meta);
      }
    }
    return metas;
  }

  /// 获取所有自带音乐的本地路径
  /// 将所有 asset 文件复制到本地缓存
  Future<List<String>> getAllLocalPaths() async {
    final paths = <String>[];
    for (final track in bundledTracks) {
      final fileName = track.assetPath.split('/').last;
      final localPath = await copyAssetToCache(track.assetPath, fileName);
      if (localPath != null) {
        paths.add(localPath);
      }
    }
    return paths;
  }

  /// 清理缓存的自带音乐
  Future<void> clearCache() async {
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final dir = Directory('${cacheDir.path}/bundled_music');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('[BundledMusicService] 清理缓存失败: $e');
    }
  }
}
