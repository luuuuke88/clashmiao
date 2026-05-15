import 'dart:io';

import 'package:clashmiao/core/auto_start/auto_start_notifier.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.clashmiao/auto_start');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AutoStartNotifier', () {
    if (!Platform.isMacOS) {
      test('非 macOS 平台保持 false 不动', () async {
        final n = AutoStartNotifier();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(n.state, isFalse);
        await n.toggle();
        expect(n.state, isFalse);
      });
      return;
    }

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    test('init 读 getAutoStart 返回 true', () async {
      var getCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'getAutoStart') {
              getCalls++;
              return true;
            }
            return null;
          });
      final n = AutoStartNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(getCalls, 1);
      expect(n.state, isTrue);
    });

    test('toggle false → true 调 setAutoStart(true) + state 翻转', () async {
      bool? receivedEnabled;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'getAutoStart') return false;
            if (call.method == 'setAutoStart') {
              receivedEnabled = (call.arguments as Map)['enabled'] as bool?;
              return null;
            }
            return null;
          });
      final n = AutoStartNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state, isFalse);
      await n.toggle();
      expect(receivedEnabled, isTrue);
      expect(n.state, isTrue);
    });

    test('native 抛错时保持当前 state', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'getAutoStart') return true;
            if (call.method == 'setAutoStart') {
              throw PlatformException(code: 'ERR');
            }
            return null;
          });
      final n = AutoStartNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state, isTrue);
      await n.toggle();
      // 异常被吞，状态保持
      expect(n.state, isTrue);
    });
  });
}
