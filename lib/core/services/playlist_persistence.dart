import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sync_v2/distributor/track_meta.dart';

/// 播放列表持久化服务
/// 负责保存和加载本地音乐列表到本地存储
/// 使用 SharedPreferences 保存元数据，复制音乐文件到应用持久化目录
class PlaylistPersistence {
  static const String _playlistKey = 'playlist_metadata';
  static const String _currentIndexKey = 'playlist_current_index';

  /// 单例实例
  static final PlaylistPersistence _instance = PlaylistPersistence._internal();
  factory PlaylistPersistence() => _instance;
  PlaylistPersistence._internal();

  /// 保存播放列表到本地存储
  /// [tracks] 曲目列表
  /// [currentIndex] 当前播放索引
  Future<bool> savePlaylist(
    List<TrackMeta> tracks, {
    int currentIndex = -1,
  }) async {
    try {
      // 确保持久化目录存在
      final musicDir = await _getMusicDirectory();
      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }

      // 复制新文件到持久化目录并更新路径
      final persistedTracks = <TrackMeta>[];
      for (final track in tracks) {
        final originalFile = File(track.localPath);
        if (!await originalFile.exists()) {
          debugPrint('[持久化] 源文件不存在: ${track.localPath}');
          continue;
        }

        // 目标文件路径（使用 trackId 作为文件名，保留扩展名）
        final extension = track.localPath.split('.').last;
        final targetPath = '${musicDir.path}/${track.trackId}.$extension';
        final targetFile = File(targetPath);

        // 如果目标文件不存在，复制过去
        if (!await targetFile.exists()) {
          await originalFile.copy(targetPath);
          debugPrint('[持久化] 复制文件: ${track.fileName} -> $targetPath');
        }

        // 创建更新后的元数据（使用持久化路径）
        persistedTracks.add(track.copyWith(localPath: targetPath));
      }

      // 序列化并保存元数据
      final jsonList = persistedTracks.map((t) => t.toJson()).toList();
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_playlistKey, jsonEncode(jsonList));
      await prefs.setInt(_currentIndexKey, currentIndex);

      debugPrint(
        '[持久化] 保存播放列表成功: ${persistedTracks.length} 首, 当前索引=$currentIndex',
      );
      return true;
    } catch (e) {
      debugPrint('[持久化] 保存播放列表失败: $e');
      return false;
    }
  }

  /// 从本地存储加载播放列表
  /// 返回曲目列表和当前索引
  Future<PlaylistLoadResult> loadPlaylist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_playlistKey);
      final currentIndex = prefs.getInt(_currentIndexKey) ?? -1;

      if (jsonString == null || jsonString.isEmpty) {
        debugPrint('[持久化] 没有保存的播放列表');
        return PlaylistLoadResult(tracks: [], currentIndex: -1);
      }

      final jsonList = jsonDecode(jsonString) as List;
      final tracks = <TrackMeta>[];

      for (final json in jsonList) {
        final track = TrackMeta.fromJson(json as Map<String, dynamic>);

        // 验证文件是否存在
        final file = File(track.localPath);
        if (await file.exists()) {
          tracks.add(track);
        } else {
          debugPrint('[持久化] 文件不存在，跳过: ${track.fileName}');
        }
      }

      debugPrint('[持久化] 加载播放列表成功: ${tracks.length} 首, 当前索引=$currentIndex');
      return PlaylistLoadResult(
        tracks: tracks,
        currentIndex: currentIndex >= 0 && currentIndex < tracks.length
            ? currentIndex
            : -1,
      );
    } catch (e) {
      debugPrint('[持久化] 加载播放列表失败: $e');
      return PlaylistLoadResult(tracks: [], currentIndex: -1);
    }
  }

  /// 清空保存的播放列表
  Future<bool> clearPlaylist() async {
    try {
      // 删除持久化的音乐文件
      final musicDir = await _getMusicDirectory();
      if (await musicDir.exists()) {
        await musicDir.delete(recursive: true);
        debugPrint('[持久化] 删除音乐目录: ${musicDir.path}');
      }

      // 清除 SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_playlistKey);
      await prefs.remove(_currentIndexKey);

      debugPrint('[持久化] 清空播放列表成功');
      return true;
    } catch (e) {
      debugPrint('[持久化] 清空播放列表失败: $e');
      return false;
    }
  }

  /// 删除单首曲目
  Future<bool> removeTrack(String trackId) async {
    try {
      final result = await loadPlaylist();
      final tracks = result.tracks.where((t) => t.trackId != trackId).toList();

      // 删除对应的文件
      final musicDir = await _getMusicDirectory();
      final files = await musicDir.list().toList();
      for (final file in files) {
        if (file.path.contains(trackId)) {
          await file.delete();
          debugPrint('[持久化] 删除文件: ${file.path}');
        }
      }

      // 保存更新后的列表
      return await savePlaylist(tracks, currentIndex: result.currentIndex);
    } catch (e) {
      debugPrint('[持久化] 删除曲目失败: $e');
      return false;
    }
  }

  /// 获取音乐持久化目录
  Future<Directory> _getMusicDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/persisted_music');
  }

  /// 获取持久化目录大小（字节）
  Future<int> getPersistedSize() async {
    try {
      final musicDir = await _getMusicDirectory();
      if (!await musicDir.exists()) return 0;

      int totalSize = 0;
      await for (final entity in musicDir.list()) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }
}

/// 播放列表加载结果
class PlaylistLoadResult {
  final List<TrackMeta> tracks;
  final int currentIndex;

  const PlaylistLoadResult({required this.tracks, required this.currentIndex});
}
