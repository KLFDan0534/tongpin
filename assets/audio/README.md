# 自带音乐文件目录

将 MP3 文件放置在此目录下，App 安装后会自动包含这些音乐文件。

## 使用方法

1. 将 MP3 文件复制到此目录
2. 编辑 `lib/core/services/bundled_music_service.dart` 中的 `bundledTracks` 列表
3. 运行 `flutter pub get` 更新资源

## 示例配置

```dart
static const List<BundledMusic> bundledTracks = [
  BundledMusic(
    id: 'demo_1',
    assetPath: 'assets/audio/demo_track_1.mp3',
    displayName: '示例曲目 1',
    artist: 'SyncTune Demo',
  ),
  BundledMusic(
    id: 'demo_2',
    assetPath: 'assets/audio/demo_track_2.mp3',
    displayName: '示例曲目 2',
    artist: 'SyncTune Demo',
  ),
];
```

## 注意事项

- 文件大小：建议每个文件 < 5MB，避免 APK/IPA 过大
- 格式：仅支持 MP3 格式
- 版权：请确保音乐文件拥有合法使用权
