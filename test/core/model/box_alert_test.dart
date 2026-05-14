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
}
