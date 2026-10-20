import 'package:flutter/material.dart';

/// 各页面共用的页头：左侧标题、右侧一排圆按钮，整行垂直居中。
///
/// 首页与线路页以前各写一份，标题字号（28 / 24）、上边距、按钮对齐都不一样，
/// 切 tab 时页头会跳。统一到这里：
/// - 最小高度 [kMinInteractiveDimension]（48 dp）——正好是圆按钮的交互区高度，
///   标题与按钮天然垂直居中；
/// - 标题放进 [Expanded] 并允许折成两行再省略，文字放大或窄屏下不会把按钮
///   挤出屏幕（不靠 FittedBox 缩小字号）；
/// - 标题带 `header` 语义，读屏可以按标题跳转。
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.actions = const [],
  }) : assert(
         (title == null) != (titleWidget == null),
         'title 与 titleWidget 二选一',
       );

  final String? title;

  /// 替代 [title] 的自定义标题区（例如搜索态里的输入框）；位置、占宽、垂直居中
  /// 与文字标题一致。
  final Widget? titleWidget;

  /// 右侧按钮，自标题一侧的末端起依次排列，间距 12 dp。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
      child: Row(
        children: [
          Expanded(
            child:
                titleWidget ??
                Semantics(
                  header: true,
                  child: Text(
                    title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
          ),
          for (final action in actions) ...[const SizedBox(width: 12), action],
        ],
      ),
    );
  }
}
