import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('<application> 声明 enableOnBackInvokedCallback=true（预测性返回手势）', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    final application = RegExp(
      r'<application\b[^>]*>',
      dotAll: true,
    ).firstMatch(manifest);
    expect(application, isNotNull, reason: '找不到 <application> 元素');
    expect(
      application!.group(0),
      contains('android:enableOnBackInvokedCallback="true"'),
    );
  });
}
