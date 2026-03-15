import 'package:flutter/material.dart';
import '../../core/sync_v2/playback_sync/sync_controller.dart';
import '../../core/sync_v2/room_discovery/mdns_service.dart';
import '../../core/sync_v2/room_discovery/discovered_room.dart';
import '../theme/app_colors.dart';

/// 房间发现页面
/// 自动扫描局域网内的 SyncTune 房间
class RoomDiscoveryPage extends StatefulWidget {
  const RoomDiscoveryPage({super.key});

  @override
  State<RoomDiscoveryPage> createState() => _RoomDiscoveryPageState();
}

class _RoomDiscoveryPageState extends State<RoomDiscoveryPage> {
  final MdnsService _mdnsService = MdnsService();
  final SyncV2Controller _controller = SyncV2Controller();
  List<DiscoveredRoom> _rooms = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _startScanning();
    _mdnsService.roomsStream.listen((rooms) {
      if (mounted) {
        setState(() => _rooms = rooms);
      }
    });
  }

  @override
  void dispose() {
    _mdnsService.stopScanning();
    super.dispose();
  }

  Future<void> _startScanning() async {
    setState(() => _isScanning = true);
    await _mdnsService.startScanning();
    if (mounted) {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _joinRoom(DiscoveredRoom room) async {
    // 显示加载提示
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await _controller.joinRoom(room);

      if (mounted) {
        Navigator.pop(context); // 关闭加载提示

        if (result == true) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已加入房间: ${room.roomName}')));
          Navigator.pop(context); // 返回上一页
        } else if (result == null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已在房间中')));
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('加入房间失败')));
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加入房间失败: $e')));
      }
    }
  }

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
        title: const Text('发现房间'),
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _startScanning,
          ),
        ],
      ),
      body: Column(
        children: [
          // 扫描状态提示
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(screenWidth * 0.04),
            color: AppColors.lightSurface,
            child: Row(
              children: [
                Icon(
                  _isScanning ? Icons.wifi_find : Icons.wifi,
                  color: AppColors.primary,
                  size: screenWidth * 0.05,
                ),
                SizedBox(width: screenWidth * 0.02),
                Text(
                  _isScanning ? '正在扫描局域网内的房间...' : '发现 ${_rooms.length} 个房间',
                  style: TextStyle(
                    fontSize: screenWidth * 0.035,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),

          // 房间列表
          Expanded(
            child: _rooms.isEmpty
                ? _buildEmptyState(screenWidth)
                : ListView.builder(
                    padding: EdgeInsets.all(screenWidth * 0.04),
                    itemCount: _rooms.length,
                    itemBuilder: (context, index) {
                      return _buildRoomCard(_rooms[index], screenWidth);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(double screenWidth) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: screenWidth * 0.2,
            color: AppColors.lightTextSecondary,
          ),
          SizedBox(height: screenWidth * 0.05),
          Text(
            '未发现房间',
            style: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.w500,
              color: AppColors.lightTextSecondary,
            ),
          ),
          SizedBox(height: screenWidth * 0.02),
          Text(
            '请确保其他设备已创建房间\n且在同一局域网内',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: AppColors.lightTextSecondary,
            ),
          ),
          SizedBox(height: screenWidth * 0.05),
          ElevatedButton.icon(
            onPressed: _isScanning ? null : _startScanning,
            icon: const Icon(Icons.refresh),
            label: const Text('重新扫描'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(DiscoveredRoom room, double screenWidth) {
    return Card(
      margin: EdgeInsets.only(bottom: screenWidth * 0.03),
      child: InkWell(
        onTap: () => _joinRoom(room),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(screenWidth * 0.04),
          child: Row(
            children: [
              // 房间图标
              Container(
                width: screenWidth * 0.12,
                height: screenWidth * 0.12,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(screenWidth * 0.03),
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  color: AppColors.primary,
                  size: screenWidth * 0.06,
                ),
              ),
              SizedBox(width: screenWidth * 0.04),

              // 房间信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.roomName,
                      style: TextStyle(
                        fontSize: screenWidth * 0.04,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: screenWidth * 0.01),
                    Text(
                      '${room.hostIp}:${room.hostWsPort}',
                      style: TextStyle(
                        fontSize: screenWidth * 0.03,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                    Text(
                      '版本: ${room.appVersion}',
                      style: TextStyle(
                        fontSize: screenWidth * 0.03,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // 加入按钮
              Icon(Icons.chevron_right, color: AppColors.lightTextSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
