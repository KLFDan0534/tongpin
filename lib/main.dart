import 'package:flutter/material.dart';
import 'ui/theme/app_theme.dart';
import 'ui/pages/main_page.dart';
import 'core/sync_v2/playback_sync/sync_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 SyncV2Controller (必须在使用前调用)
  await SyncV2Controller().init();
  // 加载持久化的播放列表
  await SyncV2Controller().loadPersistedPlaylist();
  runApp(const SyncTuneApp());
}

class SyncTuneApp extends StatelessWidget {
  const SyncTuneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tongpin SyncTune',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // 默认使用深色主题
      home: const MainPage(),
    );
  }
}
