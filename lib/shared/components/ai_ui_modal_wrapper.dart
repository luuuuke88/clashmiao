import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 弹层顶部必须留出来的高度（不含状态栏）：页面标题那一行 + 右上角的圆按钮
/// 都在这个范围里。遮住标题的话，用户会不知道自己还在哪一页。
const double _modalTopHeadroom = 96;

class AiUiModalWrapper extends StatelessWidget {
  const AiUiModalWrapper({
    super.key,
    required this.child,
    this.showHandle = true,
    this.scrollableContent = true,
  });

  final Widget child;
  final bool showHandle;

  /// 内容超过弹层最大高度时是否由这里负责滚动。
  ///
  /// 弹层封了顶（要给页面标题让位，见 [showAiUiModal]），所以内容必须能被压缩，
  /// 否则矮屏上会直接 overflow。默认包一层滚动；自己内部已经有可滚列表的弹层
  /// （比如设置里的语言选择）传 false，不然 `Flexible` 落进无界高度里会炸。
  final bool scrollableContent;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final media = MediaQuery.of(context);
    // 封顶写在这里而不是 showAiUiModal 里：项目里有好几处直接调
    // `showModalBottomSheet`（设置页的语言/主题、配置项的单选…），封在弹出
    // 函数里的话那些就漏掉了——语言列表照样会顶到最上面盖住页面标题。
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: media.size.height - media.padding.top - _modalTopHeadroom,
      ),
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 30,
                offset: const Offset(0, -5),
              ),
            ],
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child:
                  Container(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        decoration: BoxDecoration(
                          color: isLight
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.2),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(32),
                            topRight: Radius.circular(32),
                          ),
                          border: Border.all(
                            color: isLight
                                ? Colors.white.withValues(alpha: 0.5)
                                : Theme.of(
                                    context,
                                  ).aiUi.borderColor.withValues(alpha: 0.1),
                            width: 0.5,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showHandle) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .aiUi
                                      .secondaryTextColor
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (scrollableContent)
                              Flexible(
                                child: SingleChildScrollView(child: child),
                              )
                            else
                              Flexible(child: child),
                          ],
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> showAiUiModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useRootNavigator = true,
}) {
  // 高度封顶在 AiUiModalWrapper 里做，这里不重复——那样直接调
  // showModalBottomSheet 的地方也一样受保护。
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    builder: builder,
  );
}
