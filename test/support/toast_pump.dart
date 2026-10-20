import 'package:flutter_test/flutter_test.dart';

/// 让刚触发的 toast 真正出现在界面上。
///
/// toastification 3 起，`showCustom` 只插入 overlay，把 toast 放进列表这一步挪到
/// 了**下一帧**的 post-frame 回调里；放进列表后 AnimatedList 还要再一帧才把它
/// 构建出来。所以触发 toast 之后至少要再出两帧，然后给入场动画留出时间——之前
/// 一次 `pump(时长)` 就够，是因为 2.x 用的是 `Future.delayed`，推进时钟就会执行。
///
/// 在已经触发 toast 的那次 pump 之后调用。
Future<void> pumpToast(
  WidgetTester tester, [
  Duration entrance = const Duration(milliseconds: 300),
]) async {
  await tester.pump(); // post-frame 回调：toast 入列
  await tester.pump(); // AnimatedList 构建新条目
  await tester.pump(entrance); // 入场动画
}
