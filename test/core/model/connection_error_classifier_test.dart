import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/connection_error_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = Translations.build();
  final zhCn = TranslationsZhCn.build();

  group('classifyBoxAlert', () {
    test('emptyConfiguration 归类为 invalidConfig', () {
      expect(
        classifyBoxAlert(
          const BoxAlert(type: BoxAlertType.emptyConfiguration),
        ),
        ConnectionErrorCategory.invalidConfig,
      );
    });

    test('requestVpnPermission 归类为 vpnPermissionDenied', () {
      expect(
        classifyBoxAlert(
          const BoxAlert(type: BoxAlertType.requestVpnPermission),
        ),
        ConnectionErrorCategory.vpnPermissionDenied,
      );
    });

    test('requestNotificationPermission 归类为 notificationPermissionDenied', () {
      expect(
        classifyBoxAlert(
          const BoxAlert(type: BoxAlertType.requestNotificationPermission),
        ),
        ConnectionErrorCategory.notificationPermissionDenied,
      );
    });

    test('createService / startService / startCommandServer 都归类为 serviceStartFailed', () {
      expect(
        classifyBoxAlert(const BoxAlert(type: BoxAlertType.createService)),
        ConnectionErrorCategory.serviceStartFailed,
      );
      expect(
        classifyBoxAlert(const BoxAlert(type: BoxAlertType.startService)),
        ConnectionErrorCategory.serviceStartFailed,
      );
      expect(
        classifyBoxAlert(
          const BoxAlert(type: BoxAlertType.startCommandServer),
        ),
        ConnectionErrorCategory.serviceStartFailed,
      );
    });

    test('unknown 归类为 unexpected', () {
      expect(
        classifyBoxAlert(const BoxAlert(type: BoxAlertType.unknown)),
        ConnectionErrorCategory.unexpected,
      );
    });
  });

  group('classifyException', () {
    test('SocketException 归类为 networkUnavailable', () {
      expect(
        classifyException(const SocketException('no route to host')),
        ConnectionErrorCategory.networkUnavailable,
      );
    });

    test('TimeoutException 归类为 timeout', () {
      expect(
        classifyException(TimeoutException('startup timed out')),
        ConnectionErrorCategory.timeout,
      );
    });

    test('其它未归类异常兜底为 unexpected', () {
      expect(
        classifyException(Exception('some native plugin error')),
        ConnectionErrorCategory.unexpected,
      );
      expect(
        classifyException(StateError('instance not stopped')),
        ConnectionErrorCategory.unexpected,
      );
    });
  });

  group('localizedMessage / classifyBoxAlertMessage / classifyExceptionMessage', () {
    test('每个类别在英文下都返回非空、已本地化的文案', () {
      for (final category in ConnectionErrorCategory.values) {
        final msg = category.localizedMessage(en);
        expect(msg, isNotEmpty, reason: '$category 缺少英文文案');
      }
    });

    test('每个类别在中文下都返回非空、已本地化的文案', () {
      for (final category in ConnectionErrorCategory.values) {
        final msg = category.localizedMessage(zhCn);
        expect(msg, isNotEmpty, reason: '$category 缺少中文文案');
      }
    });

    test('classifyBoxAlertMessage: 分类结果不是原始 alert.message', () {
      const alert = BoxAlert(
        type: BoxAlertType.emptyConfiguration,
        message: 'raw native stack trace garbage 0xdeadbeef',
      );
      final msg = classifyBoxAlertMessage(alert, en);
      expect(msg, isNot(contains('0xdeadbeef')));
      expect(msg, en.failure.singbox.invalidConfig);
    });

    test('classifyExceptionMessage: 分类结果不是原始 e.toString()', () {
      const error = SocketException('Connection refused (errno 111)');
      final msg = classifyExceptionMessage(error, en);
      expect(msg, isNot(contains('errno 111')));
      expect(msg, en.failure.connectivity.networkUnavailable);
    });

    test('中文本地化文案示例', () {
      expect(
        ConnectionErrorCategory.invalidConfig.localizedMessage(zhCn),
        '无效配置',
      );
      expect(
        ConnectionErrorCategory.vpnPermissionDenied.localizedMessage(zhCn),
        '缺少 VPN 权限',
      );
      expect(
        ConnectionErrorCategory.networkUnavailable.localizedMessage(zhCn),
        '网络不可用',
      );
      expect(
        ConnectionErrorCategory.timeout.localizedMessage(zhCn),
        '服务启动超时',
      );
    });
  });
}
