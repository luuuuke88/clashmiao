import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/blocking_alert_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [showBlockingAlert] 的测试：这是一个"阻断式"错误/重要提示弹窗——用户
/// 必须点确认按钮才能关闭，跟会自动消失、可能被划走而错过的
/// `AppToast.error` 相对（`AppToast.error` 场景见 `app_toast.dart`）。
void main() {
  Future<bool?> pumpAndOpen(
    WidgetTester tester, {
    String confirmLabel = '知道了',
  }) async {
    bool? completed;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: TextButton(
                  onPressed: () async {
                    completed = false;
                    await showBlockingAlert(
                      context,
                      title: '连接失败',
                      message: '核心服务未能启动，请重试。',
                      confirmLabel: confirmLabel,
                    );
                    completed = true;
                  },
                  child: const Text('open-blocking-alert'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-blocking-alert'));
    await tester.pumpAndSettle();

    return completed;
  }

  testWidgets('渲染标题和正文', (tester) async {
    await pumpAndOpen(tester);

    expect(find.text('连接失败'), findsOneWidget);
    expect(find.text('核心服务未能启动，请重试。'), findsOneWidget);
    expect(find.text('知道了'), findsOneWidget);
  });

  testWidgets('barrierDismissible 为 false', (tester) async {
    await pumpAndOpen(tester);

    final barrier = tester.widget<ModalBarrier>(
      find
          .byWidgetPredicate((w) => w is ModalBarrier)
          .last,
    );

    expect(barrier.dismissible, isFalse);
  });

  testWidgets('点击遮罩（对话框外的区域）不会关闭弹窗', (tester) async {
    final completed = await pumpAndOpen(tester);
    expect(completed, isFalse, reason: '弹窗打开后还没点确认，Future 不应该完成');

    // 点屏幕左上角——AlertDialog 默认居中显示，这个位置在对话框内容区域
    // 之外，只会点到 barrier。
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('连接失败'), findsOneWidget, reason: '点遮罩不应该关闭阻断式弹窗');
    expect(find.text('核心服务未能启动，请重试。'), findsOneWidget);
  });

  testWidgets('点击确认按钮才关闭弹窗，并让 Future 完成', (tester) async {
    bool? completed = await pumpAndOpen(tester);
    expect(completed, isFalse);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    expect(find.text('连接失败'), findsNothing, reason: '点确认按钮应该关闭弹窗');
    expect(find.text('核心服务未能启动，请重试。'), findsNothing);
  });

  testWidgets('确认按钮文案默认使用 Material 的 OK 本地化文案', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showBlockingAlert(
                  context,
                  title: '连接失败',
                  message: '核心服务未能启动，请重试。',
                ),
                child: const Text('open-blocking-alert'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-blocking-alert'));
    await tester.pumpAndSettle();

    expect(find.text('OK'), findsOneWidget);
  });
}
