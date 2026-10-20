import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/core/box_service/model/box_alert.dart';
import 'package:clashmiao/domain/connection/application/connection_error_classifier.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = AppLocale.en.buildSync();
  final zhCn = AppLocale.zhCn.buildSync();

  group('classifyBoxAlert', () {
    test('emptyConfiguration 归类为 invalidConfig', () {
      expect(
        classifyBoxAlert(const BoxAlert(type: BoxAlertType.emptyConfiguration)),
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
        classifyBoxAlert(const BoxAlert(type: BoxAlertType.startCommandServer)),
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

  group(
    'localizedMessage / classifyBoxAlertMessage / classifyExceptionMessage',
    () {
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
    },
  );

  group('connectionFailureMessage：类型化失败 → 文案', () {
    test('每种失败在英文与中文下都有非空文案', () {
      final failures = <ConnectionFailure>[
        const NoActiveProfile(),
        const ConfigMissing(),
        const ProfileStoreReadOnly(2),
        const CoreUnavailable(),
        const PermissionDenied(),
        const StartTimeout(),
        for (final code in KernelFailureCode.values)
          KernelStartFailed(code, 'm'),
        const KernelUnresponsive(),
        const NativeUnresponsive(),
        const PlatformFailure('c', 'm'),
        const UnexpectedFailure('x'),
      ];
      for (final f in failures) {
        expect(connectionFailureMessage(f, en), isNotEmpty, reason: '$f');
        expect(connectionFailureMessage(f, zhCn), isNotEmpty, reason: '$f');
      }
    });

    test('订阅存储只读 → 「请升级 App 后再修改订阅」，与订阅页 / 备份恢复同一条文案', () {
      expect(
        connectionFailureMessage(const ProfileStoreReadOnly(2), en),
        en.failure.profiles.readOnlyUpgrade,
      );
      expect(
        connectionFailureMessage(const ProfileStoreReadOnly(2), zhCn),
        '请升级 App 后再修改订阅',
      );
    });

    test('沿用既有文案：缺订阅 / 缺配置 / 核心库缺失 / VPN 授权 / 启动超时', () {
      expect(
        connectionFailureMessage(const NoActiveProfile(), en),
        en.failure.profiles.noActive,
      );
      expect(
        connectionFailureMessage(const ConfigMissing(), en),
        en.failure.profiles.notFound,
      );
      expect(
        connectionFailureMessage(const CoreUnavailable(), en),
        en.failure.singbox.coreLibraryMissing,
      );
      expect(
        connectionFailureMessage(const PermissionDenied(), en),
        en.failure.connectivity.missingVpnPermission,
      );
      expect(
        connectionFailureMessage(const StartTimeout(), en),
        en.failure.singbox.startTimeout,
      );
    });

    test('内核启动失败码：配置为空 → 无效配置；建服务 / 起服务 / 起命令服务 → 服务启动错误', () {
      expect(
        connectionFailureMessage(
          const KernelStartFailed(KernelFailureCode.emptyConfiguration, ''),
          en,
        ),
        en.failure.singbox.invalidConfig,
      );
      for (final code in [
        KernelFailureCode.createService,
        KernelFailureCode.startService,
        KernelFailureCode.startCommandServer,
      ]) {
        expect(
          connectionFailureMessage(KernelStartFailed(code, ''), en),
          en.failure.singbox.start,
          reason: code.name,
        );
      }
    });

    test('失联类失败有各自可操作的文案，且互不相同', () {
      final a = connectionFailureMessage(const KernelUnresponsive(), en);
      final b = connectionFailureMessage(const NativeUnresponsive(), en);
      final c = connectionFailureMessage(
        const KernelStartFailed(KernelFailureCode.kernelExited, ''),
        en,
      );
      expect({a, b, c}.length, 3);
      expect(a, en.failure.singbox.kernelUnresponsive);
      expect(b, en.failure.connectivity.nativeUnresponsive);
      expect(c, en.failure.singbox.kernelExited);
    });

    test('平台/未知失败兜底为「意外错误」，不暴露原始异常文本', () {
      expect(
        connectionFailureMessage(const PlatformFailure('boom', 'secret'), en),
        en.failure.unexpected,
      );
      expect(
        connectionFailureMessage(const UnexpectedFailure('secret'), en),
        en.failure.unexpected,
      );
    });
  });

  group('failureFromError：异常 → 类型化失败', () {
    test('端口 2 s 超时 → nativeUnresponsive；其它端口错误保留错误码', () {
      expect(
        failureFromError(const KernelPortException('timeout')),
        const NativeUnresponsive(),
      );
      expect(
        failureFromError(const KernelPortException('unsupported', 'ios')),
        const PlatformFailure('unsupported', 'ios'),
      );
    });

    test(
      'PlatformException → PlatformFailure；TimeoutException → startTimeout',
      () {
        expect(
          failureFromError(PlatformException(code: 'c', message: 'm')),
          const PlatformFailure('c', 'm'),
        );
        expect(failureFromError(TimeoutException('t')), const StartTimeout());
      },
    );

    test('其它异常 → unexpected', () {
      expect(failureFromError(StateError('x')), isA<UnexpectedFailure>());
    });
  });
}
