import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';

/// 全 App 共用的背景晕染：页面顶部左右各一团品牌色，向下化开到页面底色。
///
/// 两团颜色就是 logo 上那两个色——左上靛蓝、右上闪电黄，一冷一暖。晕染只发生
/// 在顶部约 45% 的高度，越往下越干净，内容区（卡片、列表）始终落在纯净底色上，
/// 不会跟卡片的白抢注意力。
///
/// 画在 [ShellPage] 的最底层而不是各个页面里：四个 tab 用的是同一块背景，切页
/// 的时候晕染不该跟着重画一遍；各页面的 Scaffold 因此都要设成透明。
class BrandBackdrop extends StatelessWidget {
  const BrandBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    // 深色主题下同样的透明度会糊成一片脏色，靛蓝要更亮、黄要更收。
    final indigoAlpha = isLight ? 0.16 : 0.22;
    final goldAlpha = isLight ? 0.14 : 0.07;

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final blob = width * 1.25;

          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: theme.scaffoldBackgroundColor),
              ),
              _Blob(
                key: const ValueKey('brand-wash-top-left'),
                size: blob,
                left: -blob * 0.35,
                top: -blob * 0.45,
                color: BrandColors.indigo.withValues(alpha: indigoAlpha),
              ),
              _Blob(
                key: const ValueKey('brand-wash-top-right'),
                size: blob,
                left: width - blob * 0.62,
                top: -blob * 0.5,
                color: BrandColors.gold.withValues(alpha: goldAlpha),
              ),
              // 底部同样来一层，左右跟顶部对调，页面读起来是一条对角的色带。
              //
              // 这不只是好看：底部胶囊导航是一块浅色实心底，压在原本几乎纯白
              // 的页尾上根本分不出边界。底下有了颜色，那块浅色才浮得起来。
              _Blob(
                key: const ValueKey('brand-wash-bottom-left'),
                size: blob,
                left: -blob * 0.42,
                top: constraints.maxHeight - blob * 0.55,
                color: BrandColors.gold.withValues(alpha: goldAlpha * 0.8),
              ),
              _Blob(
                key: const ValueKey('brand-wash-bottom-right'),
                size: blob,
                left: width - blob * 0.58,
                top: constraints.maxHeight - blob * 0.5,
                color: BrandColors.indigo.withValues(alpha: indigoAlpha * 0.9),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required super.key,
    required this.size,
    required this.left,
    required this.top,
    required this.color,
  });

  final double size;
  final double left;
  final double top;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      // 径向渐变直接化到全透明，比"实心圆 + 100px 高斯模糊"便宜得多，
      // 边缘也不会在窗口缩放时抖。
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }
}
