import 'package:flutter/material.dart';

/// SyncTune 应用颜色定义
/// 基于 Pencil 设计稿提取的颜色规格
class AppColors {
  AppColors._();

  // ========== 主色调 ==========
  /// 主绿色 - 用于按钮、进度条、强调元素
  static const Color primary = Color(0xFF32D583);
  
  /// 主绿色渐变起点
  static const Color primaryGradientStart = Color(0xFF32D583);
  
  /// 主绿色渐变终点 (深绿)
  static const Color primaryGradientEnd = Color(0xFF059669);

  // ========== 深色模式 ==========
  /// 深色背景
  static const Color darkBackground = Color(0xFF0B0B0E);
  
  /// 深色表面
  static const Color darkSurface = Color(0xFF1A1A1E);
  
  /// 深色卡片
  static const Color darkCard = Color(0xFF1F1F23);
  
  /// 深色文字 (主)
  static const Color darkTextPrimary = Color(0xFFFAFAF9);
  
  /// 深色文字 (次)
  static const Color darkTextSecondary = Color(0xFFA1A1AA);
  
  /// 深色边框
  static const Color darkBorder = Color(0xFF2A2A2E);

  // ========== 浅色模式 ==========
  /// 浅色背景
  static const Color lightBackground = Color(0xFFF8FAF9);
  
  /// 浅色表面
  static const Color lightSurface = Color(0xFFFFFFFF);
  
  /// 浅色卡片
  static const Color lightCard = Color(0xFFFFFFFF);
  
  /// 浅色文字 (主)
  static const Color lightTextPrimary = Color(0xFF1A1A1E);
  
  /// 浅色文字 (次)
  static const Color lightTextSecondary = Color(0xFF64748B);
  
  /// 浅色边框
  static const Color lightBorder = Color(0xFFE2E8F0);

  // ========== 状态颜色 ==========
  /// 成功/同步中
  static const Color success = Color(0xFF32D583);
  
  /// 警告
  static const Color warning = Color(0xFFF59E0B);
  
  /// 错误
  static const Color error = Color(0xFFEF4444);
  
  /// 信息
  static const Color info = Color(0xFF3B82F6);

  // ========== 特殊颜色 ==========
  /// 进度条背景
  static const Color progressBackground = Color(0xFFE2E8F0);
  
  /// 进度条填充 (深色模式)
  static const Color progressFillDark = Color(0xFF32D583);
  
  /// 进度条填充 (浅色模式)
  static const Color progressFillLight = Color(0xFF32D583);
  
  /// 阴影颜色
  static const Color shadow = Color(0x1A000000);
  
  /// 绿色阴影 (用于主按钮)
  static const Color primaryShadow = Color(0x4D32D583);

  // ========== 渐变 ==========
  /// 主按钮渐变
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 1.0],
    colors: [primaryGradientStart, primaryGradientEnd],
  );
  
  /// 创建房间卡片渐变
  static const LinearGradient createRoomGradient = LinearGradient(
    begin: Alignment(-1.0, -1.0),
    end: Alignment(1.0, 1.0),
    stops: [0.0, 1.0],
    colors: [primaryGradientStart, primaryGradientEnd],
  );
}
