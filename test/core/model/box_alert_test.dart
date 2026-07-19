import 'package:clashmiao/core/model/box_alert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoxAlertType.parse', () {
    test('已知 PascalCase 映射到对应 enum', () {
      expect(
        BoxAlertType.parse('RequestVPNPermission'),
        BoxAlertType.requestVpnPermission,
      );
      expect(
        BoxAlertType.parse('RequestNotificationPermission'),
        BoxAlertType.requestNotificationPermission,
      );
      expect(
        BoxAlertType.parse('EmptyConfiguration'),
        BoxAlertType.emptyConfiguration,
      );
      expect(
        BoxAlertType.parse('StartCommandServer'),
        BoxAlertType.startCommandServer,
      );
      expect(BoxAlertType.parse('CreateService'), BoxAlertType.createService);
      expect(BoxAlertType.parse('StartService'), BoxAlertType.startService);
    });

    test('未知值 fallback 到 unknown', () {
      expect(BoxAlertType.parse('SomethingNew'), BoxAlertType.unknown);
      expect(
        BoxAlertType.parse('request_vpn_permission'),
        BoxAlertType.unknown,
      );
    });

    test('null 输入 fallback 到 unknown', () {
      expect(BoxAlertType.parse(null), BoxAlertType.unknown);
    });

    test('空字符串 fallback 到 unknown', () {
      expect(BoxAlertType.parse(''), BoxAlertType.unknown);
    });
  });

  group('BoxAlertType.isFatal', () {
    test('内核压根没起来的三种（建服务/起服务/空配置）判定为致命', () {
      expect(BoxAlertType.startService.isFatal, isTrue);
      expect(BoxAlertType.createService.isFatal, isTrue);
      expect(BoxAlertType.emptyConfiguration.isFatal, isTrue);
    });

    test('权限请求/command server/未知类型不算致命', () {
      expect(BoxAlertType.requestVpnPermission.isFatal, isFalse);
      expect(BoxAlertType.requestNotificationPermission.isFatal, isFalse);
      expect(BoxAlertType.startCommandServer.isFatal, isFalse);
      expect(BoxAlertType.unknown.isFatal, isFalse);
    });
  });
}
