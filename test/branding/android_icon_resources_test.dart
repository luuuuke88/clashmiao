import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 自适应启动图标与疾速猫通知图标资源完整', () {
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(adaptive, contains('@drawable/ic_launcher_background'));
    expect(adaptive, contains('@drawable/ic_launcher_foreground'));

    final notification = File(
      'android/app/src/main/res/drawable/ic_stat_logo.xml',
    ).readAsStringSync();
    expect(notification, contains('android:viewportWidth="24"'));
    expect(notification, contains('android:fillType="evenOdd"'));
    expect(notification, isNot(contains('M12,1L3,5v6')));
  });
}
