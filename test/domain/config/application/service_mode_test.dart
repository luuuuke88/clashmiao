import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/config/application/service_mode.dart';
import 'package:clashmiao/domain/config/data/default_config_options.dart';
import 'package:flutter_test/flutter_test.dart';

/// 默认值：两个开关都没动过（升级用户的典型状态）。
const _defaults = NetworkSettings(setSystemProxy: true, enableTun: false);
const _proxyOnly = NetworkSettings(setSystemProxy: false, enableTun: false);
const _vpn = NetworkSettings(setSystemProxy: false, enableTun: true);

void main() {
  tearDown(() => debugServiceModePlatformOverride = null);

  // 真机验收 BUG-4：移动端默认值落在不存在的「系统线路」档，分段控件两段都不亮。
  group('移动端档位', () {
    for (final platform in [
      ServiceModePlatform.android,
      ServiceModePlatform.ios,
    ]) {
      test('${platform.name}：只有仅线路 / VPN 两档，任何设置都落在其中之一', () {
        debugServiceModePlatformOverride = platform;
        expect(serviceModeChoices(), [ServiceMode.proxyOnly, ServiceMode.vpn]);
        expect(
          serviceModeOf(_defaults),
          ServiceMode.vpn,
          reason: '默认值就是一直在跑的 VPN',
        );
        expect(serviceModeOf(_proxyOnly), ServiceMode.proxyOnly);
        expect(serviceModeOf(_vpn), ServiceMode.vpn);
        expect(
          serviceModeOf(
            const NetworkSettings(setSystemProxy: true, enableTun: true),
          ),
          ServiceMode.vpn,
        );
      });
    }
  });

  test('桌面端档位不变：仅线路 / 系统线路', () {
    debugServiceModePlatformOverride = ServiceModePlatform.desktop;
    expect(serviceModeChoices(), [
      ServiceMode.proxyOnly,
      ServiceMode.systemProxy,
    ]);
    expect(serviceModeOf(_defaults), ServiceMode.systemProxy);
    expect(serviceModeOf(_proxyOnly), ServiceMode.proxyOnly);
  });

  // 真机验收 BUG-3：移动端 enable-tun 无条件为 true，选「仅线路」不进请求、
  // revision 不变，协调器原样无操作，Service 类不换。
  group('启动配置的 enable-tun（Android 上即 Service 形态）', () {
    test('Android：仅线路 → false，VPN / 默认 → true，且进 options（改变 revision）', () {
      debugServiceModePlatformOverride = ServiceModePlatform.android;
      expect(kernelEnableTun(_proxyOnly), isFalse);
      expect(kernelEnableTun(_vpn), isTrue);
      expect(kernelEnableTun(_defaults), isTrue);
      expect(
        getDefaultConfigOptions(settings: _proxyOnly)['enable-tun'],
        isFalse,
      );
      expect(getDefaultConfigOptions(settings: _vpn)['enable-tun'], isTrue);
    });

    test('运行时配置的 tun inbound 与之一致：Android 仅线路剥，桌面一律剥', () {
      debugServiceModePlatformOverride = ServiceModePlatform.android;
      expect(runtimeKeepsTunInbound(_proxyOnly), isFalse);
      expect(runtimeKeepsTunInbound(_defaults), isTrue);
      debugServiceModePlatformOverride = ServiceModePlatform.ios;
      expect(runtimeKeepsTunInbound(_proxyOnly), isTrue);
      debugServiceModePlatformOverride = ServiceModePlatform.desktop;
      expect(runtimeKeepsTunInbound(_vpn), isFalse);
    });

    test('iOS 恒为 true（Packet Tunnel 只能以 TUN 运行，行为不变）', () {
      debugServiceModePlatformOverride = ServiceModePlatform.ios;
      expect(kernelEnableTun(_proxyOnly), isTrue);
    });

    test('桌面端按用户开关', () {
      debugServiceModePlatformOverride = ServiceModePlatform.desktop;
      expect(kernelEnableTun(_vpn), isTrue);
      expect(kernelEnableTun(_defaults), isFalse);
    });
  });
}
