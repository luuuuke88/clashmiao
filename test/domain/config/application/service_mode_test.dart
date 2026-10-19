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
  test('Android：只有仅线路 / VPN 两档，任何设置都落在其中之一', () {
    debugServiceModePlatformOverride = ServiceModePlatform.android;
    expect(serviceModeChoices(_defaults), [
      ServiceMode.proxyOnly,
      ServiceMode.vpn,
    ]);
    expect(serviceModeIsFixed, isFalse);
    expect(serviceModeOf(_defaults), ServiceMode.vpn, reason: '默认值就是一直在跑的 VPN');
    expect(serviceModeOf(_proxyOnly), ServiceMode.proxyOnly);
    expect(serviceModeOf(_vpn), ServiceMode.vpn);
    expect(
      serviceModeOf(
        const NetworkSettings(setSystemProxy: true, enableTun: true),
      ),
      ServiceMode.vpn,
    );
  });

  // 不给假入口：Packet Tunnel 恒为 TUN，「仅线路」在 iOS 上什么也不改变。
  test('iOS：只有 VPN 一档，任何设置都显示为 VPN', () {
    debugServiceModePlatformOverride = ServiceModePlatform.ios;
    expect(serviceModeChoices(_vpn), [ServiceMode.vpn]);
    expect(serviceModeIsFixed, isTrue);
    for (final s in [_defaults, _proxyOnly, _vpn]) {
      expect(serviceModeOf(s), ServiceMode.vpn);
      expect(tunSettingsTakeEffect(s), isTrue);
    }
  });

  test('桌面端档位：不主动提供 TUN；已持久化的 enableTun 显示为选中、可切走', () {
    debugServiceModePlatformOverride = ServiceModePlatform.desktop;
    expect(serviceModeChoices(_defaults), [
      ServiceMode.proxyOnly,
      ServiceMode.systemProxy,
    ]);
    expect(serviceModeChoices(_vpn), [
      ServiceMode.proxyOnly,
      ServiceMode.systemProxy,
      ServiceMode.vpn,
    ]);
    expect(serviceModeIsFixed, isFalse);
    expect(serviceModeOf(_defaults), ServiceMode.systemProxy);
    expect(serviceModeOf(_proxyOnly), ServiceMode.proxyOnly);
    expect(serviceModeOf(_vpn), ServiceMode.vpn);
    expect(
      serviceModeOf(
        const NetworkSettings(setSystemProxy: true, enableTun: true),
      ),
      ServiceMode.vpn,
    );
    for (final s in [_defaults, _proxyOnly, _vpn]) {
      expect(serviceModeChoices(s), contains(serviceModeOf(s)));
    }
    expect(tunSettingsTakeEffect(_defaults), isFalse);
    expect(tunSettingsTakeEffect(_proxyOnly), isFalse);
    expect(tunSettingsTakeEffect(_vpn), isTrue, reason: '显式 TUN 照旧生效');
  });

  test('Android：TUN 相关设置只在 VPN 档起作用', () {
    debugServiceModePlatformOverride = ServiceModePlatform.android;
    expect(tunSettingsTakeEffect(_vpn), isTrue);
    expect(tunSettingsTakeEffect(_defaults), isTrue);
    expect(tunSettingsTakeEffect(_proxyOnly), isFalse);
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

    test('桌面端尊重显式设置：enableTun=true 才进启动配置', () {
      debugServiceModePlatformOverride = ServiceModePlatform.desktop;
      expect(kernelEnableTun(_vpn), isTrue);
      expect(kernelEnableTun(_defaults), isFalse);
      expect(getDefaultConfigOptions(settings: _vpn)['enable-tun'], isTrue);
    });
  });

  // 启动参数回归矩阵：平台 × 设置组合。界面档位（能力）与启动参数（显式设置）
  // 分开算——这里锁住的是后者，界面怎么隐藏都不能改写它。
  group('启动参数矩阵（平台 × 设置）', () {
    const combos = {
      'tun=0 sys=0': NetworkSettings(setSystemProxy: false, enableTun: false),
      'tun=0 sys=1': NetworkSettings(setSystemProxy: true, enableTun: false),
      'tun=1 sys=0': NetworkSettings(setSystemProxy: false, enableTun: true),
      'tun=1 sys=1': NetworkSettings(setSystemProxy: true, enableTun: true),
    };
    // 期望值：(enable-tun, 保留订阅里的 tun inbound)
    const expected = <ServiceModePlatform, Map<String, (bool, bool)>>{
      ServiceModePlatform.android: {
        'tun=0 sys=0': (false, false),
        'tun=0 sys=1': (true, true),
        'tun=1 sys=0': (true, true),
        'tun=1 sys=1': (true, true),
      },
      ServiceModePlatform.ios: {
        'tun=0 sys=0': (true, true),
        'tun=0 sys=1': (true, true),
        'tun=1 sys=0': (true, true),
        'tun=1 sys=1': (true, true),
      },
      ServiceModePlatform.desktop: {
        'tun=0 sys=0': (false, false),
        'tun=0 sys=1': (false, false),
        'tun=1 sys=0': (true, false),
        'tun=1 sys=1': (true, false),
      },
    };
    for (final platform in ServiceModePlatform.values) {
      for (final entry in combos.entries) {
        test('${platform.name} / ${entry.key}', () {
          debugServiceModePlatformOverride = platform;
          final (tun, keepInbound) = expected[platform]![entry.key]!;
          final options = getDefaultConfigOptions(settings: entry.value);
          expect(options['enable-tun'], tun, reason: 'enable-tun');
          expect(kernelEnableTun(entry.value), tun);
          expect(
            runtimeKeepsTunInbound(entry.value),
            keepInbound,
            reason: 'tun inbound',
          );
          // 不变量：选中态一定在档位里；TUN 专属设置与 enable-tun 同口径。
          expect(
            serviceModeChoices(entry.value),
            contains(serviceModeOf(entry.value)),
          );
          expect(tunSettingsTakeEffect(entry.value), tun);
        });
      }
    }
  });
}
