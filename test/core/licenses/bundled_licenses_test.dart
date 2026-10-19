import 'package:clashmiao/core/licenses/bundled_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, String>> _registered() async {
  LicenseRegistry.reset();
  addTearDown(LicenseRegistry.reset);
  registerBundledLicenses();
  final entries = await LicenseRegistry.licenses.toList();
  return {
    for (final e in entries)
      for (final pkg in e.packages)
        pkg: e.paragraphs.map((p) => p.text).join('\n'),
  };
}

void main() {
  test('登记 sing-box、geosite、geoip 三条许可，各自独立', () async {
    final byPackage = await _registered();
    expect(
      byPackage.keys,
      containsAll([
        singBoxLicensePackage,
        geositeLicensePackage,
        geoipLicensePackage,
      ]),
    );
  });

  test('sing-box：随包版本 v1.8.9 的 GPL-3.0-or-later 与名称附加条件，链接固定到该 tag', () async {
    final text = (await _registered())[singBoxLicensePackage]!;
    expect(text, contains('GPL-3.0-or-later'));
    expect(text, contains('v1.8.9'));
    expect(
      text,
      contains('https://github.com/SagerNet/sing-box/blob/v1.8.9/LICENSE'),
    );
    expect(text, contains('may use the name of the application'));
    // 不再指向会变的分支。
    expect(text, isNot(contains('dev-next')));
  });

  test('geosite-cn：数据来自 domain-list-community，许可证为 MIT，附完整许可原文', () async {
    final text = (await _registered())[geositeLicensePackage]!;
    expect(text, contains('v2fly/domain-list-community'));
    expect(text, contains('MIT License'));
    expect(text, contains('Copyright (c) 2018-2019 V2Ray'));
    expect(text, contains('Permission is hereby granted, free of charge'));
    expect(text, contains('THE SOFTWARE IS PROVIDED "AS IS"'));
    // 转换工具是 GPL，但数据的许可不能说成 GPL。
    expect(text, contains('GPL-3.0'));
  });

  test(
    'geoip-cn：MaxMind GeoLite2，GeoLite EULA + CC BY-SA 4.0，带原样署名句',
    () async {
      final text = (await _registered())[geoipLicensePackage]!;
      expect(text, contains('GeoLite2-Country'));
      expect(text, contains('Dreamacro/maxmind-geoip'));
      expect(text, contains('GeoLite End User License Agreement'));
      expect(text, contains('https://www.maxmind.com/en/geolite2/eula'));
      expect(text, contains('CC BY-SA 4.0'));
      expect(
        text,
        contains('Creative Commons Attribution-ShareAlike 4.0 International'),
      );
      expect(
        text,
        contains(
          'This product includes GeoLite Data created by MaxMind, '
          'available from https://www.maxmind.com',
        ),
      );
    },
  );

  test('无法核实的部分如实写在登记文本里（中英文）', () async {
    final byPackage = await _registered();
    for (final pkg in [geositeLicensePackage, geoipLicensePackage]) {
      final text = byPackage[pkg]!;
      expect(text, contains('未核实'), reason: pkg);
      expect(text, contains('Unverified'), reason: pkg);
      expect(text, contains('assets/rule-sets/VERSION'), reason: pkg);
    }
  });

  test('登记的文案不出现被禁止点名的项目', () async {
    final all = (await _registered()).values.join('\n').toLowerCase();
    for (final banned in ['hiddify', 'baseproxy', 'nekobox', 'nekohasekai']) {
      expect(all, isNot(contains(banned)));
    }
  });
}
