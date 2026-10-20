import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/adaptive_icon.dart';
import 'package:clashmiao/shared/components/page_header.dart';
import 'package:clashmiao/shared/components/press_feedback.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

/// 二级页面（从设置 / 配置里压进来的整页）共用的外框：
///
/// - 页头与首页 / 线路页同一个 [PageHeader]（24 sp 粗体标题、48 dp 最小高度、标题可折行）；
/// - 返回 / 关闭：页头右端的玻璃胶囊，最后一格永远是「关闭」（×，等同系统返回）；
///   页面自己的操作放在它前面（[actions]）；
/// - 页头**固定**在顶部，内容在它下面滚动，没有折叠、没有滚动时的投影变化——
///   以前日志页与分应用线路页用默认 `AppBar`（返回箭头在左、20 sp 标题、滚动时
///   出投影），和配置页一进一出就像换了个 App。
///
/// [body] 自己负责横向内边距与滚动末尾的底部 inset（`MediaQuery.paddingOf(context)
/// .bottom`，手势条高度）；页头左右固定 24 dp。
class SubPageScaffold extends StatelessWidget {
  const SubPageScaffold({
    super.key,
    this.title,
    this.titleWidget,
    this.actions = const [],
    required this.closeLabel,
    this.onClose,
    required this.body,
  });

  final String? title;
  final Widget? titleWidget;

  /// 关闭格之前的操作格（[HeaderPillButton] / [HeaderPillMenu]）。
  final List<Widget> actions;

  /// 「关闭」格的无障碍标签 / 提示（i18n）。
  final String closeLabel;

  /// 默认 `Navigator.maybePop`；搜索态这类「先收起再返回」的页面自己接管。
  final VoidCallback? onClose;

  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // 底部不让安全区把内容截断：edge-to-edge 下手势条那一圈要能看到滚动内容从
        // 下面划过；滚动的 body 自己在末尾补 MediaQuery 的底部 inset。
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: PageHeader(
                title: title,
                titleWidget: titleWidget,
                actions: [
                  HeaderControlPill(
                    children: [
                      ...actions,
                      HeaderPillButton(
                        icon: FluentIcons.dismiss_24_regular,
                        label: closeLabel,
                        onTap:
                            onClose ?? () => Navigator.of(context).maybePop(),
                        isDestructive: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// 页头右侧的玻璃胶囊：几格图标按钮，格与格之间一条细分隔线。
class HeaderControlPill extends StatelessWidget {
  const HeaderControlPill({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final aiUi = Theme.of(context).aiUi;
    return Container(
      // 48 dp 高：各格都有 ≥48 dp 的交互区（Android 最小触控目标）。外框含上下各
      // 1 dp 描边，所以外框 50、内部按钮 48。
      height: kMinInteractiveDimension + 2,
      decoration: BoxDecoration(
        color: aiUi.glassColor,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: aiUi.borderColor),
        boxShadow: aiUi.cardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 20,
                color: aiUi.borderColor.withValues(alpha: 0.5),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 胶囊里的一格：图标按钮。带提示文字（长按出现）与无障碍标签；键盘可聚焦。
class HeaderPillButton extends StatelessWidget {
  const HeaderPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: PressFeedback(
        semanticLabel: label,
        pressedScale: PressFeedback.iconPressedScale,
        focusBorderRadius: BorderRadius.circular(24),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _PillCell(
          child: Icon(
            icon,
            size: 20,
            color: isDestructive
                ? Colors.red.withValues(alpha: 0.8)
                : Theme.of(context).aiUi.secondaryTextColor,
          ),
        ),
      ),
    );
  }
}

/// 胶囊里的一格：点开弹出菜单（日志页的分享、分应用线路的更多操作）。
class HeaderPillMenu<T> extends StatelessWidget {
  const HeaderPillMenu({
    super.key,
    required this.label,
    required this.itemBuilder,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;

  /// 默认是各平台惯用的「更多」图标。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: label,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      child: _PillCell(
        child: Icon(
          icon ??
              resolveAdaptiveIcon(
                apple: FluentIcons.more_horizontal_24_regular,
                other: FluentIcons.more_vertical_24_regular,
              ),
          size: 20,
          color: Theme.of(context).aiUi.secondaryTextColor,
        ),
      ),
    );
  }
}

class _PillCell extends StatelessWidget {
  const _PillCell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    height: kMinInteractiveDimension,
    child: Center(child: child),
  );
}
