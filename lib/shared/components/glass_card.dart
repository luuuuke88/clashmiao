import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';

/// 全 App 的卡片材质：半透明磨砂玻璃。
///
/// 首页的订阅卡 / 数据块、设置页和关于页的分组卡都用它，页面上就只有一种
/// "矩形框"。之前每个页面各写一份实色白 + 24 圆角的 decoration，白得发死、
/// 圆角也大到显得笨重；玻璃能透出底下的品牌晕染，卡片才像浮在页面上而不是
/// 糊在页面上。
///
/// 圆角默认收到 16：24 的圆角配这种尺寸的卡片显得钝，16 更利落。
///
/// 玻璃感靠半透明染色 + 高光描边做，**不用 `BackdropFilter`**：一屏上有五六
/// 张卡，每个背景模糊都要开一次 saveLayer 并重采样背景，页面上只要有任何动画
/// 在跑就会拖成幻灯片。卡片底下是一整片平滑的品牌晕染，真模糊和半透明在观感
/// 上分不出来——唯一保留真模糊的是底部胶囊导航，那里确实有内容从下面滚过去。
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 16.0,
    this.padding = const EdgeInsets.all(16.0),
    this.borderColor,
    this.borderWidth = 1.0,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  /// 描边颜色。默认是那道发丝高光；需要表达"选中"之类的状态时才覆盖它，
  /// 免得每处又各写一份卡片。
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;
    final radius = BorderRadius.circular(borderRadius);

    return RepaintBoundary(
      child: DecoratedBox(
        // 投影画在裁剪外面——裁剪会把投影一起裁掉。
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: aiUi.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              // 够实才压得住底下的晕染（卡片里的文字要读得清），又留了
              // 快三成透明让颜色透上来。
              color: isLight
                  ? Colors.white.withValues(alpha: 0.72)
                  : const Color(0xFF1C1C22).withValues(alpha: 0.62),
              borderRadius: radius,
              border: Border.all(
                color:
                    borderColor ??
                    (isLight
                        ? Colors.white.withValues(alpha: 0.75)
                        : Colors.white.withValues(alpha: 0.10)),
                width: borderWidth,
              ),
            ),
            // 用一层透明 Material 兜住水波纹：InkWell 的墨水画在最近的
            // Material 祖先上，那个祖先在卡片外面，所以点一下会冒出一个
            // **直角**高亮，从圆角卡片的角上支出来。放进裁剪里面就规矩了。
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}
