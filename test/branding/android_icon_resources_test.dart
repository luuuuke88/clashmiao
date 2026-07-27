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
    expect(foreground, contains('android:strokeColor="#FFC6CDFF"'));
    expect(foreground, contains('android:strokeLineCap="round"'));
    expect(
      foreground,
      contains(
        'M11.5,62 C13,60.2 15,60.2 16.5,62 '
        'C17.5,63.2 18.5,63.2 19.2,62.4',
      ),
    );
    expect(foreground, contains('android:strokeWidth="2.2"'));
    expect(foreground, isNot(contains('M24,51 C17,51')));
    expect(foreground, isNot(contains('M25,64 C17,67')));

    final notification = File(
      'android/app/src/main/res/drawable/ic_stat_logo.xml',
    ).readAsStringSync();
    expect(notification, contains('android:viewportWidth="24"'));
    expect(notification, contains('android:fillType="evenOdd"'));
    expect(notification, contains('android:strokeLineCap="round"'));
    expect(
      notification,
      contains(
        'M2.2,14 C2.7,13.3 3.3,13.3 3.8,14 '
        'C4.1,14.4 4.4,14.4 4.6,14.1',
      ),
    );
    expect(notification, contains('android:strokeWidth="0.7"'));
    expect(notification, isNot(contains('M12,1L3,5v6')));
  });
}
