import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 跨语言夹具的黄金文件比对：`UPDATE_GOLDEN=1 flutter test <文件>` 重写，否则
/// 逐字节比较并在不一致时失败。
///
/// 夹具入库在 `kernel/testdata/**`，由 Dart 测试产出、Go 测试消费。Dart 一侧
/// 产出变了而夹具没跟着更新，这里就失败——这是「Dart 键漂移」第一道防线。
bool get updateGolden => Platform.environment['UPDATE_GOLDEN'] == '1';

/// [path]（相对包根）的内容必须逐字节等于 [content]；[updateGolden] 时改为重写。
void expectGoldenFile(String path, String content) {
  final file = File(path);
  if (updateGolden) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return;
  }
  expect(
    file.existsSync(),
    isTrue,
    reason: '$path 不存在：用 UPDATE_GOLDEN=1 重跑本测试生成，并把它放进评审',
  );
  expect(
    file.readAsStringSync(),
    content,
    reason: '$path 与 Dart 的产出不一致：确认改动符合预期后用 UPDATE_GOLDEN=1 重跑本测试更新',
  );
}
