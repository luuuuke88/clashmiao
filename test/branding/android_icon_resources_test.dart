import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 自适应启动图标与疾速猫通知图标资源完整', () {
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(adaptive, contains('@drawable/ic_launcher_background'));
    expect(adaptive, contains('@drawable/ic_launcher_foreground'));

    final foreground = File(
      'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
    ).readAsStringSync();
    expect(RegExp(r'<path\b').allMatches(foreground).length, 2);
    expect(foreground, isNot(contains('android:stroke')));
    expect(foreground, isNot(contains('M24,51 C17,51')));
    expect(foreground, isNot(contains('M25,64 C17,67')));

    final notification = File(
      'android/app/src/main/res/drawable/ic_stat_logo.xml',
    ).readAsStringSync();
    expect(notification, contains('android:viewportWidth="24"'));
    expect(notification, contains('android:fillType="evenOdd"'));
    expect(RegExp(r'<path\b').allMatches(notification).length, 1);
    expect(notification, isNot(contains('android:stroke')));
    expect(notification, isNot(contains('M12,1L3,5v6')));
  });
}
