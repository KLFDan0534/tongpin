import 'package:flutter/material.dart';
import '../bricolage/bricolage.dart';

/// UI 效果演示页面（使用本地 Bricolage UI 组件）
/// 可安全删除: 删除 lib/ui/bricolage/ 目录 + 此文件 + settings_page.dart 中的入口
class BricolageDemoPage extends StatefulWidget {
  const BricolageDemoPage({super.key});

  @override
  State<BricolageDemoPage> createState() => _BricolageDemoPageState();
}

class _BricolageDemoPageState extends State<BricolageDemoPage> {
  bool _switchValue = true;
  bool _checkboxValue = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('Bricolage UI 演示'),
        backgroundColor: const Color(0xFF16213e),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ========== 玻璃态效果 ==========
            _buildSectionTitle('玻璃态效果 (Glassmorphism)'),
            const SizedBox(height: 12),
            EffectContainer(
              enableGlassmorphism: true,
              glassBlur: 10.0,
              glassOpacity: 0.15,
              padding: const EdgeInsets.all(20),
              borderRadius: BorderRadius.circular(16),
              child: const Column(
                children: [
                  Icon(Icons.music_note, size: 48, color: Colors.white70),
                  SizedBox(height: 12),
                  Text(
                    '磨砂玻璃卡片',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'EffectContainer + enableGlassmorphism',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ========== 渐变 + 发光效果 ==========
            _buildSectionTitle('渐变 + 发光效果'),
            const SizedBox(height: 12),
            EffectContainer(
              enableGradients: true,
              gradientStart: const Color(0xFF6366F1),
              gradientEnd: const Color(0xFF8B5CF6),
              enableBorderGlow: true,
              glowColor: const Color(0xFF6366F1),
              glowIntensity: 0.5,
              glowSpread: 8.0,
              padding: const EdgeInsets.all(20),
              borderRadius: BorderRadius.circular(16),
              child: const Column(
                children: [
                  Icon(Icons.auto_awesome, size: 48, color: Colors.white),
                  SizedBox(height: 12),
                  Text(
                    '发光渐变卡片',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'enableGradients + enableBorderGlow',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ========== 新粗野主义效果 ==========
            _buildSectionTitle('新粗野主义 (Neobrutalism)'),
            const SizedBox(height: 12),
            EffectContainer(
              enableHardShadow: true,
              hardShadowOffsetX: 6,
              hardShadowOffsetY: 6,
              backgroundColor: const Color(0xFFFFE66D),
              padding: const EdgeInsets.all(20),
              borderRadius: BorderRadius.circular(8),
              child: const Column(
                children: [
                  Icon(Icons.star, size: 48, color: Color(0xFF1a1a2e)),
                  SizedBox(height: 12),
                  Text(
                    '硬朗阴影卡片',
                    style: TextStyle(
                      color: Color(0xFF1a1a2e),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'enableHardShadow + 偏移阴影',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ========== 拟物化效果 ==========
            _buildSectionTitle('拟物化效果 (Neumorphism)'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF2d2d44),
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: EffectContainer(
                enableNeumorphism: true,
                neumorphismIntensity: 0.6,
                backgroundColor: const Color(0xFF2d2d44),
                padding: const EdgeInsets.all(20),
                borderRadius: BorderRadius.circular(16),
                child: const Column(
                  children: [
                    Icon(Icons.touch_app, size: 48, color: Colors.white70),
                    SizedBox(height: 12),
                    Text(
                      '柔和 3D 卡片',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'enableNeumorphism + 双向阴影',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ========== 浮动动画 ==========
            _buildSectionTitle('浮动动画效果'),
            const SizedBox(height: 12),
            EffectContainer(
              enableFloating: true,
              floatingDistance: 8.0,
              enableGradients: true,
              gradientStart: const Color(0xFF10B981),
              gradientEnd: const Color(0xFF059669),
              padding: const EdgeInsets.all(20),
              borderRadius: BorderRadius.circular(16),
              child: const Column(
                children: [
                  Icon(Icons.flight_takeoff, size: 48, color: Colors.white),
                  SizedBox(height: 12),
                  Text(
                    '浮动卡片',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'enableFloating 上下浮动',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ========== 按钮组件 ==========
            _buildSectionTitle('按钮组件'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                CustomButton(
                  text: '填充按钮',
                  variant: CustomButtonVariant.filled,
                  onPressed: () {},
                ),
                CustomButton(
                  text: '描边按钮',
                  variant: CustomButtonVariant.outlined,
                  onPressed: () {},
                ),
                CustomButton(
                  text: '文本按钮',
                  variant: CustomButtonVariant.text,
                  onPressed: () {},
                ),
                CustomButton(
                  text: '大按钮',
                  variant: CustomButtonVariant.filled,
                  size: CustomButtonSize.large,
                  backgroundColor: const Color(0xFF6366F1),
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ========== 开关和复选框 ==========
            _buildSectionTitle('开关和复选框'),
            const SizedBox(height: 12),
            Row(
              children: [
                CustomSwitch(
                  value: _switchValue,
                  onChanged: (v) => setState(() => _switchValue = v),
                  activeColor: const Color(0xFF6366F1),
                ),
                const SizedBox(width: 12),
                Text(
                  '开关: ${_switchValue ? "开" : "关"}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _checkboxValue,
                  onChanged: (v) => setState(() => _checkboxValue = v ?? false),
                  activeColor: const Color(0xFF8B5CF6),
                ),
                const SizedBox(width: 12),
                Text(
                  '复选框: ${_checkboxValue ? "选中" : "未选中"}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ========== 卡片组件 ==========
            _buildSectionTitle('卡片组件'),
            const SizedBox(height: 12),
            CustomCard(
              variant: CustomCardVariant.elevated,
              padding: const EdgeInsets.all(16),
              child: const Text(
                '悬浮卡片 (Elevated)',
                style: TextStyle(color: Color(0xFF18181B)),
              ),
            ),
            const SizedBox(height: 12),
            CustomCard(
              variant: CustomCardVariant.outlined,
              padding: const EdgeInsets.all(16),
              child: const Text(
                '描边卡片 (Outlined)',
                style: TextStyle(color: Color(0xFF18181B)),
              ),
            ),
            const SizedBox(height: 24),

            // ========== 徽章和芯片 ==========
            _buildSectionTitle('徽章和芯片'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                CustomBadge(text: '默认', variant: CustomBadgeVariant.default_),
                CustomBadge(text: '成功', variant: CustomBadgeVariant.success),
                CustomBadge(text: '警告', variant: CustomBadgeVariant.secondary),
                CustomBadge(
                  text: '危险',
                  variant: CustomBadgeVariant.destructive,
                ),
                CustomBadge(text: '描边', variant: CustomBadgeVariant.outline),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                CustomChip(label: '音乐', icon: Icons.music_note),
                CustomChip(label: '同步', icon: Icons.sync),
                CustomChip(label: '可删除', icon: Icons.close, onDeleted: () {}),
              ],
            ),
            const SizedBox(height: 24),

            // ========== 加载动画 ==========
            _buildSectionTitle('加载动画'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    CustomSpinner(
                      type: SpinnerType.circular,
                      color: const Color(0xFF6366F1),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Circular',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                Column(
                  children: [
                    CustomSpinner(
                      type: SpinnerType.dots,
                      color: const Color(0xFF8B5CF6),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Dots',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                Column(
                  children: [
                    CustomSpinner(
                      type: SpinnerType.pulse,
                      color: const Color(0xFF10B981),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Pulse',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ========== 对话框 ==========
            _buildSectionTitle('对话框'),
            const SizedBox(height: 12),
            CustomButton(
              text: '显示对话框',
              variant: CustomButtonVariant.filled,
              backgroundColor: const Color(0xFF6366F1),
              onPressed: () {
                CustomDialog.show(
                  context,
                  title: '提示',
                  description: '这是一个 Bricolage UI 对话框示例，带有淡入滑动动画。',
                  confirmText: '确定',
                  cancelText: '取消',
                  onConfirm: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('点击了确定'),
                        backgroundColor: Color(0xFF2d2d44),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 24),

            // ========== 提示 ==========
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '💡 本页面使用本地 Bricolage UI 组件（lib/ui/bricolage/）\n'
                '删除方式: 删除 lib/ui/bricolage/ 目录 + 此文件 + settings_page.dart 入口\n'
                '在线预览: https://bricolage-ui-preview.vercel.app/',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
