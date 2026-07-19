import 'dart:convert';

import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NetworkSettings WARP 凭证字段', () {
    test('默认值均为空字符串', () {
      const settings = NetworkSettings();

      expect(settings.warpAccountId, '');
      expect(settings.warpAccessToken, '');
      expect(settings.warpWireguardConfig, '');
    });

    test('copyWith 只更新指定字段，其余保持不变', () {
      const settings = NetworkSettings(
        warpAccountId: 'acc-1',
        warpAccessToken: 'token-1',
        warpWireguardConfig: '{"k":"v"}',
      );

      final updated = settings.copyWith(warpAccountId: 'acc-2');

      expect(updated.warpAccountId, 'acc-2');
      expect(updated.warpAccessToken, 'token-1');
      expect(updated.warpWireguardConfig, '{"k":"v"}');
    });
  });

  group('NetworkSettings WARP 噪音混淆默认值（对齐参照项目推荐值）', () {
    test('默认构造函数：clean-ip/port/noise 系列不再是全空/旧固定端口', () {
      const settings = NetworkSettings();

      expect(settings.warpCleanIp, 'auto');
      expect(settings.warpPort, 0);
      expect(settings.warpNoise, '1-3');
      expect(settings.warpNoiseSize, '10-30');
      expect(settings.warpNoiseMode, 'm6');
      expect(settings.warpNoiseDelay, '10-30');
    });

    test('从未持久化过时（prefs 为空），notifier 落到新默认值', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      expect(notifier.state.warpCleanIp, 'auto');
      expect(notifier.state.warpPort, 0);
      expect(notifier.state.warpNoise, '1-3');
      expect(notifier.state.warpNoiseSize, '10-30');
      expect(notifier.state.warpNoiseMode, 'm6');
      expect(notifier.state.warpNoiseDelay, '10-30');
    });

    test('已持久化的用户偏好不会被新默认值覆盖', () async {
      // 模拟"用户以前保存过跟旧默认值、新默认值都不同的自定义值"这一场景：
      // 只要 key 存在于 prefs 里，读取时就必须原样返回，不能被这次改默认值顶掉。
      SharedPreferences.setMockInitialValues({
        'clashmiao_warp_clean_ip': '162.159.192.1',
        'clashmiao_warp_port': 2408,
        'clashmiao_warp_noise': '5-5',
        'clashmiao_warp_noise_size': '20-20',
        'clashmiao_warp_noise_mode': 'm4',
        'clashmiao_warp_noise_delay': '2-2',
      });
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      expect(notifier.state.warpCleanIp, '162.159.192.1');
      expect(notifier.state.warpPort, 2408);
      expect(notifier.state.warpNoise, '5-5');
      expect(notifier.state.warpNoiseSize, '20-20');
      expect(notifier.state.warpNoiseMode, 'm4');
      expect(notifier.state.warpNoiseDelay, '2-2');
    });

    test('用户此前保存过“旧默认值”本身也当作已设置值保留（不会被悄悄替换成新默认值）', () async {
      // 边界场景：用户从未改过设置，但由于旧版本的默认值曾被写入过 prefs
      // （例如早期版本在首次运行时把默认值落盘），这次改默认值常量不能让
      // 这些历史落盘值“被动升级”成新默认值——已保存的就是已保存的。
      SharedPreferences.setMockInitialValues({
        'clashmiao_warp_clean_ip': '',
        'clashmiao_warp_port': 40000,
        'clashmiao_warp_noise': '',
        'clashmiao_warp_noise_size': '',
        'clashmiao_warp_noise_mode': '',
        'clashmiao_warp_noise_delay': '',
      });
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      expect(notifier.state.warpCleanIp, '');
      expect(notifier.state.warpPort, 40000);
      expect(notifier.state.warpNoise, '');
      expect(notifier.state.warpNoiseSize, '');
      expect(notifier.state.warpNoiseMode, '');
      expect(notifier.state.warpNoiseDelay, '');
    });

    test('setWarpCleanIp/setWarpPort/setWarpNoise 系列写入后可持久化读回', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      await notifier.setWarpCleanIp('1.2.3.4');
      await notifier.setWarpPort(1234);
      await notifier.setWarpNoise('7-9');
      await notifier.setWarpNoiseSize('11-13');
      await notifier.setWarpNoiseMode('m2');
      await notifier.setWarpNoiseDelay('3-4');

      final reloaded = NetworkSettingsNotifier(prefs);
      expect(reloaded.state.warpCleanIp, '1.2.3.4');
      expect(reloaded.state.warpPort, 1234);
      expect(reloaded.state.warpNoise, '7-9');
      expect(reloaded.state.warpNoiseSize, '11-13');
      expect(reloaded.state.warpNoiseMode, 'm2');
      expect(reloaded.state.warpNoiseDelay, '3-4');
    });

    test('reset 后 WARP 噪音混淆字段回落到新默认值', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);
      await notifier.setWarpCleanIp('1.2.3.4');
      await notifier.setWarpPort(1234);

      await notifier.reset();

      expect(notifier.state.warpCleanIp, 'auto');
      expect(notifier.state.warpPort, 0);
      expect(notifier.state.warpNoise, '1-3');
      expect(notifier.state.warpNoiseSize, '10-30');
      expect(notifier.state.warpNoiseMode, 'm6');
      expect(notifier.state.warpNoiseDelay, '10-30');
      expect(prefs.getString('clashmiao_warp_clean_ip'), isNull);
      expect(prefs.getInt('clashmiao_warp_port'), isNull);
    });
  });

  group('NetworkSettingsNotifier WARP 凭证持久化', () {
    test('setWarpAccountId 更新 state 并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      await notifier.setWarpAccountId('acc-42');

      expect(notifier.state.warpAccountId, 'acc-42');
      expect(prefs.getString('clashmiao_warp_account_id'), 'acc-42');
    });

    test('setWarpAccessToken 更新 state 并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      await notifier.setWarpAccessToken('token-42');

      expect(notifier.state.warpAccessToken, 'token-42');
      expect(prefs.getString('clashmiao_warp_access_token'), 'token-42');
    });

    test('setWarpWireguardConfig 更新 state 并持久化（原样保存，不 trim）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);
      const wireguardConfigJson = '{"private_key":"a","peer":"b"}';

      await notifier.setWarpWireguardConfig(wireguardConfigJson);

      expect(notifier.state.warpWireguardConfig, wireguardConfigJson);
      expect(
        prefs.getString('clashmiao_warp_wireguard_config'),
        wireguardConfigJson,
      );
    });

    test('重新从 prefs 构造 notifier 时读回已持久化的凭证', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = NetworkSettingsNotifier(prefs);
      await first.setWarpAccountId('acc-persisted');
      await first.setWarpAccessToken('token-persisted');
      await first.setWarpWireguardConfig('{"a":1}');

      final second = NetworkSettingsNotifier(prefs);

      expect(second.state.warpAccountId, 'acc-persisted');
      expect(second.state.warpAccessToken, 'token-persisted');
      expect(second.state.warpWireguardConfig, '{"a":1}');
    });

    test('reset 清除 WARP 凭证字段', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);
      await notifier.setWarpAccountId('acc-1');
      await notifier.setWarpAccessToken('token-1');
      await notifier.setWarpWireguardConfig('{"a":1}');

      await notifier.reset();

      expect(notifier.state.warpAccountId, '');
      expect(notifier.state.warpAccessToken, '');
      expect(notifier.state.warpWireguardConfig, '');
      expect(prefs.getString('clashmiao_warp_account_id'), isNull);
      expect(prefs.getString('clashmiao_warp_access_token'), isNull);
      expect(prefs.getString('clashmiao_warp_wireguard_config'), isNull);
    });
  });

  // ===========================================================
  // wave3: 高级配置字段（此前在 default_config_options.dart 里被硬编码成
  // 常量，现在是 NetworkSettings 的一等字段）。具体默认值沿用此前
  // default_config_options.dart 里的硬编码常量，避免这次重构改变现有
  // 运行时行为（见 network_settings.dart 构造函数上的注释）。
  // ===========================================================
  group('NetworkSettings 高级配置字段默认值', () {
    test('默认值对齐此前 default_config_options.dart 的硬编码常量', () {
      const settings = NetworkSettings();

      expect(settings.mtu, 9000);
      expect(settings.clashApiPort, 6756);
      expect(settings.tproxyPort, 2081);
      expect(settings.localDnsPort, 6450);
      expect(settings.enableFakeDns, isFalse);
      expect(settings.independentDnsCache, isTrue);
      expect(settings.tlsFragmentSleep, '50-200');
      expect(settings.enableTlsMixedSniCase, isFalse);
      expect(settings.tlsPaddingSize, '100-200');
      expect(settings.muxPadding, isFalse);
    });

    test('copyWith 只更新指定的高级字段，其余保持不变', () {
      const settings = NetworkSettings();

      final updated = settings.copyWith(
        mtu: 1400,
        clashApiPort: 19999,
        tproxyPort: 19998,
        localDnsPort: 19997,
        enableFakeDns: true,
        independentDnsCache: false,
        tlsFragmentSleep: '2-8',
        enableTlsMixedSniCase: true,
        tlsPaddingSize: '1-1500',
        muxPadding: true,
      );

      expect(updated.mtu, 1400);
      expect(updated.clashApiPort, 19999);
      expect(updated.tproxyPort, 19998);
      expect(updated.localDnsPort, 19997);
      expect(updated.enableFakeDns, isTrue);
      expect(updated.independentDnsCache, isFalse);
      expect(updated.tlsFragmentSleep, '2-8');
      expect(updated.enableTlsMixedSniCase, isTrue);
      expect(updated.tlsPaddingSize, '1-1500');
      expect(updated.muxPadding, isTrue);
      // 没碰过的字段应该保持默认值不变。
      expect(updated.mixedPort, 2080);
      expect(updated.strictRoute, isTrue);
    });
  });

  group('NetworkSettingsNotifier 高级配置字段持久化', () {
    test('setMtu 更新 state 并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      await notifier.setMtu(1420);

      expect(notifier.state.mtu, 1420);
      expect(prefs.getInt('clashmiao_mtu'), 1420);
    });

    test('setMtu 拒绝非正数', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      await expectLater(notifier.setMtu(0), throwsArgumentError);
      await expectLater(notifier.setMtu(-1), throwsArgumentError);
      expect(notifier.state.mtu, 9000);
    });

    test('setClashApiPort/setTproxyPort/setLocalDnsPort 更新 state 并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      await notifier.setClashApiPort(17000);
      await notifier.setTproxyPort(17001);
      await notifier.setLocalDnsPort(17002);

      expect(notifier.state.clashApiPort, 17000);
      expect(notifier.state.tproxyPort, 17001);
      expect(notifier.state.localDnsPort, 17002);
      expect(prefs.getInt('clashmiao_clash_api_port'), 17000);
      expect(prefs.getInt('clashmiao_tproxy_port'), 17001);
      expect(prefs.getInt('clashmiao_local_dns_port'), 17002);
    });

    test('端口类字段拒绝越界端口，state 保持原值', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      await expectLater(notifier.setClashApiPort(80), throwsArgumentError);
      await expectLater(notifier.setTproxyPort(70000), throwsArgumentError);
      await expectLater(notifier.setLocalDnsPort(-1), throwsArgumentError);

      expect(notifier.state.clashApiPort, 6756);
      expect(notifier.state.tproxyPort, 2081);
      expect(notifier.state.localDnsPort, 6450);
    });

    test('setEnableFakeDns/setIndependentDnsCache 更新 state 并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      await notifier.setEnableFakeDns(true);
      await notifier.setIndependentDnsCache(false);

      expect(notifier.state.enableFakeDns, isTrue);
      expect(notifier.state.independentDnsCache, isFalse);
      expect(prefs.getBool('clashmiao_enable_fake_dns'), isTrue);
      expect(prefs.getBool('clashmiao_independent_dns_cache'), isFalse);
    });

    test(
      'setTlsFragmentSleep/setTlsPaddingSize 更新 state 并持久化，拒绝空字符串',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final notifier = NetworkSettingsNotifier(prefs);

        await notifier.setTlsFragmentSleep('2-8');
        await notifier.setTlsPaddingSize('1-1500');

        expect(notifier.state.tlsFragmentSleep, '2-8');
        expect(notifier.state.tlsPaddingSize, '1-1500');
        expect(prefs.getString('clashmiao_tls_fragment_sleep'), '2-8');
        expect(prefs.getString('clashmiao_tls_padding_size'), '1-1500');

        await expectLater(
          notifier.setTlsFragmentSleep('   '),
          throwsArgumentError,
        );
        await expectLater(
          notifier.setTlsPaddingSize(''),
          throwsArgumentError,
        );
      },
    );

    test('setEnableTlsMixedSniCase/setMuxPadding 更新 state 并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      await notifier.setEnableTlsMixedSniCase(true);
      await notifier.setMuxPadding(true);

      expect(notifier.state.enableTlsMixedSniCase, isTrue);
      expect(notifier.state.muxPadding, isTrue);
      expect(prefs.getBool('clashmiao_enable_tls_mixed_sni_case'), isTrue);
      expect(prefs.getBool('clashmiao_mux_padding'), isTrue);
    });

    test('重新从 prefs 构造 notifier 时读回已持久化的高级字段', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = NetworkSettingsNotifier(prefs);
      await first.setMtu(1300);
      await first.setClashApiPort(17000);
      await first.setEnableFakeDns(true);
      await first.setTlsFragmentSleep('3-9');
      await first.setMuxPadding(true);

      final second = NetworkSettingsNotifier(prefs);

      expect(second.state.mtu, 1300);
      expect(second.state.clashApiPort, 17000);
      expect(second.state.enableFakeDns, isTrue);
      expect(second.state.tlsFragmentSleep, '3-9');
      expect(second.state.muxPadding, isTrue);
    });

    test('reset 清除高级配置字段，落回默认值', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);
      await notifier.setMtu(1300);
      await notifier.setClashApiPort(17000);
      await notifier.setTproxyPort(17001);
      await notifier.setLocalDnsPort(17002);
      await notifier.setEnableFakeDns(true);
      await notifier.setIndependentDnsCache(false);
      await notifier.setTlsFragmentSleep('3-9');
      await notifier.setEnableTlsMixedSniCase(true);
      await notifier.setTlsPaddingSize('5-50');
      await notifier.setMuxPadding(true);

      await notifier.reset();

      expect(notifier.state.mtu, 9000);
      expect(notifier.state.clashApiPort, 6756);
      expect(notifier.state.tproxyPort, 2081);
      expect(notifier.state.localDnsPort, 6450);
      expect(notifier.state.enableFakeDns, isFalse);
      expect(notifier.state.independentDnsCache, isTrue);
      expect(notifier.state.tlsFragmentSleep, '50-200');
      expect(notifier.state.enableTlsMixedSniCase, isFalse);
      expect(notifier.state.tlsPaddingSize, '100-200');
      expect(notifier.state.muxPadding, isFalse);
      expect(prefs.getInt('clashmiao_mtu'), isNull);
      expect(prefs.getInt('clashmiao_clash_api_port'), isNull);
      expect(prefs.getBool('clashmiao_mux_padding'), isNull);
    });
  });

  group('NetworkSettingsNotifier.importJson', () {
    test('包含全部高级字段的 JSON 导入后正确写入 NetworkSettings', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      final json = jsonEncode({
        'mixedPort': 2222,
        'mtu': 1350,
        'clashApiPort': 17756,
        'tproxyPort': 17081,
        'localDnsPort': 17450,
        'enableFakeDns': true,
        'independentDnsCache': false,
        'tlsFragmentSleep': '4-10',
        'enableTlsMixedSniCase': true,
        'tlsPaddingSize': '2-1000',
        'muxPadding': true,
      });

      final result = await notifier.importJson(json);

      expect(result.hasParseError, isFalse);
      expect(result.skippedKeys, isEmpty);
      expect(result.appliedKeys, contains('mtu'));
      expect(result.appliedKeys, contains('muxPadding'));
      expect(notifier.state.mixedPort, 2222);
      expect(notifier.state.mtu, 1350);
      expect(notifier.state.clashApiPort, 17756);
      expect(notifier.state.tproxyPort, 17081);
      expect(notifier.state.localDnsPort, 17450);
      expect(notifier.state.enableFakeDns, isTrue);
      expect(notifier.state.independentDnsCache, isFalse);
      expect(notifier.state.tlsFragmentSleep, '4-10');
      expect(notifier.state.enableTlsMixedSniCase, isTrue);
      expect(notifier.state.tlsPaddingSize, '2-1000');
      expect(notifier.state.muxPadding, isTrue);
      // 持久化也要跟着写，不能只改内存 state。
      expect(prefs.getInt('clashmiao_mtu'), 1350);
      expect(prefs.getBool('clashmiao_mux_padding'), isTrue);
    });

    test('缺失字段的 JSON 只更新出现过的字段，其余保留原值', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);
      await notifier.setMuxPadding(true);

      final json = jsonEncode({'mtu': 1300});
      final result = await notifier.importJson(json);

      expect(result.appliedKeys, ['mtu']);
      expect(notifier.state.mtu, 1300);
      // 没出现在 JSON 里的字段维持导入前的值，不会被悄悄重置成默认值。
      expect(notifier.state.muxPadding, isTrue);
      expect(notifier.state.clashApiPort, 6756);
    });

    test('顶层不是合法 JSON 时优雅失败，不崩溃、不改动任何状态', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      final result = await notifier.importJson('not even json {{{');

      expect(result.hasParseError, isTrue);
      expect(result.parseError, isNotNull);
      expect(result.appliedKeys, isEmpty);
      expect(notifier.state.mtu, 9000);
    });

    test('顶层是 JSON 数组（不是对象）时优雅失败', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      final result = await notifier.importJson(jsonEncode([1, 2, 3]));

      expect(result.hasParseError, isTrue);
      expect(notifier.state.mtu, 9000);
    });

    test('单个字段类型错误只跳过该字段，其余字段仍正常导入', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      final json = jsonEncode({
        'mtu': 'not-a-number',
        'clashApiPort': 17756,
      });
      final result = await notifier.importJson(json);

      expect(result.skippedKeys, contains('mtu'));
      expect(result.appliedKeys, contains('clashApiPort'));
      // 类型错误的字段保留原值。
      expect(notifier.state.mtu, 9000);
      expect(notifier.state.clashApiPort, 17756);
    });

    test('字段值未通过 setter 校验（端口越界）时跳过并保留原值', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      final json = jsonEncode({'tproxyPort': 80, 'mtu': 1400});
      final result = await notifier.importJson(json);

      expect(result.skippedKeys, contains('tproxyPort'));
      expect(result.appliedKeys, contains('mtu'));
      expect(notifier.state.tproxyPort, 2081);
      expect(notifier.state.mtu, 1400);
    });

    test('导出的 JSON 可以原样导回（往返一致）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final source = NetworkSettingsNotifier(prefs);
      await source.setMtu(1280);
      await source.setMuxPadding(true);
      await source.setTlsFragmentSleep('9-19');

      // 模拟"导出配置选项 JSON"里已有的字段集合 + 新增高级字段，
      // 直接从 state 序列化（跟 config_options_page._networkSettingsJson 的
      // 字段集合保持一致）。
      final exported = jsonEncode({
        'mixedPort': source.state.mixedPort,
        'mtu': source.state.mtu,
        'clashApiPort': source.state.clashApiPort,
        'tproxyPort': source.state.tproxyPort,
        'localDnsPort': source.state.localDnsPort,
        'enableFakeDns': source.state.enableFakeDns,
        'independentDnsCache': source.state.independentDnsCache,
        'tlsFragmentSleep': source.state.tlsFragmentSleep,
        'enableTlsMixedSniCase': source.state.enableTlsMixedSniCase,
        'tlsPaddingSize': source.state.tlsPaddingSize,
        'muxPadding': source.state.muxPadding,
      });

      final fresh = NetworkSettingsNotifier(prefs);
      // fresh 复用同一份 prefs，此刻已经带着 source 写入的持久化值，
      // 所以先手动 reset 到默认值，确认 importJson 真的是它把值改回来的。
      await fresh.reset();
      final result = await fresh.importJson(exported);

      expect(result.hasParseError, isFalse);
      expect(fresh.state.mtu, 1280);
      expect(fresh.state.muxPadding, isTrue);
      expect(fresh.state.tlsFragmentSleep, '9-19');
    });
  });
}
