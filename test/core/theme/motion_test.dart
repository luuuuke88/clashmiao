import 'package:clashmiao/core/theme/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> _context(
  WidgetTester tester, {
  required bool disableAnimations,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  test('时长 token：short 150 / medium 250 / long 400 ms', () {
    expect(Motion.short, const Duration(milliseconds: 150));
    expect(Motion.medium, const Duration(milliseconds: 250));
    expect(Motion.long, const Duration(milliseconds: 400));
  });

  test('曲线 token 都是 [0,1] 上单调落在端点的有效曲线', () {
    for (final curve in [Motion.standard, Motion.emphasized, Motion.exit]) {
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
    }
    // 强调曲线是减速进入：前半程已走过大半；退出曲线是加速离开：前半程走得少。
    expect(Motion.emphasized.transform(0.5), greaterThan(0.5));
    expect(Motion.exit.transform(0.5), lessThan(0.5));
  });

  testWidgets('正常模式：时长原样，延迟保留，循环动画启动', (tester) async {
    final context = await _context(tester, disableAnimations: false);
    expect(Motion.reduced(context), isFalse);
    expect(Motion.duration(context, Motion.medium), Motion.medium);
    expect(
      Motion.delay(context, const Duration(milliseconds: 80)),
      const Duration(milliseconds: 80),
    );
    expect(Motion.loops(context), isTrue);
    expect(Motion.layoutDuration(context, Motion.medium), Motion.medium);
  });

  testWidgets('减少动画：时长取 0、延迟清除、循环不启动', (tester) async {
    final context = await _context(tester, disableAnimations: true);
    expect(Motion.reduced(context), isTrue);
    for (final token in [Motion.short, Motion.medium, Motion.long]) {
      expect(Motion.duration(context, token), Duration.zero);
    }
    expect(
      Motion.delay(context, const Duration(milliseconds: 80)),
      Duration.zero,
    );
    expect(Motion.loops(context), isFalse);
    // 布局期驱动的动画（AnimatedSize）不能取 0，否则会在 performLayout 里同步通知。
    expect(
      Motion.layoutDuration(context, Motion.medium),
      const Duration(microseconds: 1),
    );
  });
}
