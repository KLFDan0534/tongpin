import 'package:flutter/material.dart';
import '../../core/sync_v2/playback_sync/sync_controller.dart';
import '../theme/app_colors.dart';
import 'bricolage_demo_page.dart';

/// 设置页面
/// 包含音频校准、同步设置、关于等功能
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SyncV2Controller _controller = SyncV2Controller();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor: AppColors.lightSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('设置'),
      ),
      body: ListView(
        padding: EdgeInsets.all(screenWidth * 0.05),
        children: [
          // 同步设置
          _buildSectionHeader('同步设置'),
          _buildSettingItem(
            icon: Icons.devices,
            title: '当前角色',
            subtitle: _controller.role.name == 'host'
                ? '房主'
                : _controller.role.name == 'client'
                ? '成员'
                : '未连接',
            onTap: () => _showRoleInfo(),
          ),
          _buildSettingItem(
            icon: Icons.wifi,
            title: '连接状态',
            subtitle: _controller.connectionState.name,
            onTap: () => _showConnectionInfo(),
          ),
          _buildSettingItem(
            icon: Icons.people,
            title: '已连接设备',
            subtitle: '${_controller.peerCount} 台设备',
            onTap: () => _showDeviceInfo(),
          ),

          SizedBox(height: screenWidth * 0.05),

          // 音频设置
          _buildSectionHeader('音频设置'),
          _buildSettingItem(
            icon: Icons.tune,
            title: '音频校准',
            subtitle: '人耳校准播放延迟',
            onTap: () => _showCalibrationDialog(),
          ),

          SizedBox(height: screenWidth * 0.05),

          // 关于
          _buildSectionHeader('关于'),
          _buildSettingItem(
            icon: Icons.info_outline,
            title: '版本信息',
            subtitle: 'SyncTune v1.0.0',
            onTap: () => _showAboutDialog(),
          ),
          _buildSettingItem(
            icon: Icons.code,
            title: '开源许可',
            subtitle: '查看第三方库许可',
            onTap: () => _showLicenses(),
          ),
          _buildSettingItem(
            icon: Icons.palette,
            title: 'Bricolage UI 演示',
            subtitle: '查看 UI 组件库效果',
            onTap: () => _openBricolageDemo(),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Container(
      margin: EdgeInsets.only(bottom: screenWidth * 0.025),
      decoration: BoxDecoration(
        color: AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lightBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          title,
          style: TextStyle(
            color: AppColors.lightTextPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: AppColors.lightTextSecondary),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: AppColors.lightTextSecondary,
        ),
        onTap: onTap,
      ),
    );
  }

  void _showRoleInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.lightCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.lightBorder, width: 1),
        ),
        title: Text(
          '当前角色',
          style: TextStyle(color: AppColors.lightTextPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '角色: ${_controller.role.name}',
              style: TextStyle(color: AppColors.lightTextPrimary),
            ),
            Text(
              '房间 ID: ${_controller.roomId ?? "未创建"}',
              style: TextStyle(color: AppColors.lightTextPrimary),
            ),
            Text(
              'Peer ID: ${_controller.peerId ?? "未分配"}',
              style: TextStyle(color: AppColors.lightTextPrimary),
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

  void _showConnectionInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.lightCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.lightBorder, width: 1),
        ),
        title: Text(
          '连接状态',
          style: TextStyle(color: AppColors.lightTextPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '状态: ${_controller.connectionState.name}',
              style: TextStyle(color: AppColors.lightTextPrimary),
            ),
            Text(
              '时钟同步: ${_controller.isClockLocked ? "已锁定" : "未锁定"}',
              style: TextStyle(color: AppColors.lightTextPrimary),
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

  void _showDeviceInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.lightCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.lightBorder, width: 1),
        ),
        title: Text(
          '已连接设备',
          style: TextStyle(color: AppColors.lightTextPrimary),
        ),
        content: Text(
          '当前有 ${_controller.peerCount} 台设备连接',
          style: TextStyle(color: AppColors.lightTextPrimary),
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
                            -300,
                            300,
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
                            -300,
                            300,
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
                          latencyComp = (latencyComp - 10).clamp(0, 500);
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
                          latencyComp = (latencyComp + 10).clamp(0, 500);
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

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'SyncTune',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2024 SyncTune Team',
      children: [
        const Text('跨设备音乐同步播放应用'),
        const SizedBox(height: 16),
        const Text('支持多台设备同步播放音乐，实现完美的音频同步体验。'),
      ],
    );
  }

  void _showLicenses() {
    showLicensePage(
      context: context,
      applicationName: 'SyncTune',
      applicationVersion: '1.0.0',
    );
  }

  void _openBricolageDemo() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BricolageDemoPage()),
    );
  }
}
