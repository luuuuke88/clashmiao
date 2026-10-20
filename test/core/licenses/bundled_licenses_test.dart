import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/licenses/bundled_licenses.dart';
import 'package:crypto/crypto.dart';
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

  group('随包快照与许可记录一一对应', () {
    final version = File('assets/rule-sets/VERSION').readAsStringSync();

    String shortShaIn(String repo) {
      final m = RegExp('$repo:.*\\(([0-9a-f]{7})\\)').firstMatch(version);
      expect(m, isNotNull, reason: 'VERSION 里找不到 $repo 的快照提交');
      return m!.group(1)!;
    }

    String sha256Of(String path) =>
        sha256.convert(File(path).readAsBytesSync()).toString();

    test('geoip：VERSION 里的快照提交就是登记引用的提交，随包文件与之逐字节一致', () async {
      final text = (await _registered())[geoipLicensePackage]!;

      expect(geoipSnapshotCommit, startsWith(shortShaIn('sing-geoip')));
      expect(
        text,
        contains(
          'https://github.com/SagerNet/sing-geoip/commit/$geoipSnapshotCommit',
        ),
      );
      // 生成程序固定到提交，数据来源固定到具体发布。
      expect(
        text,
        contains(
          'https://github.com/SagerNet/sing-geoip/blob/'
          '$geoipGeneratorCommit/main.go',
        ),
      );
      expect(
        text,
        contains(
          'https://github.com/Dreamacro/maxmind-geoip/releases/tag/'
          '$geoipDataRelease',
        ),
      );
      // 随包二进制确实就是这个快照里的那一份。
      expect(sha256Of('assets/rule-sets/geoip-cn.srs'), geoipCnSha256);
      expect(text, contains(geoipCnSha256));
    });

    test('geosite：VERSION 里的快照提交就是登记引用的提交，随包文件与之逐字节一致', () async {
      final text = (await _registered())[geositeLicensePackage]!;

      expect(geositeSnapshotCommit, startsWith(shortShaIn('sing-geosite')));
      expect(
        text,
        contains(
          'https://github.com/SagerNet/sing-geosite/commit/'
          '$geositeSnapshotCommit',
        ),
      );
      expect(
        text,
        contains(
          'https://github.com/SagerNet/sing-geosite/blob/'
          '$geositeGeneratorCommit/main.go',
        ),
      );
      // 许可原文固定在数据来源提交上。
      expect(
        text,
        contains(
          'https://github.com/v2fly/domain-list-community/blob/'
          '$dlcCommit/LICENSE',
        ),
      );
      expect(sha256Of('assets/rule-sets/geosite-cn.srs'), geositeCnSha256);
      expect(text, contains(geositeCnSha256));
    });

    test('登记文本不再用笼统的「未核实」搪塞：已核实的写成固定引用', () async {
      final byPackage = await _registered();
      for (final pkg in [geositeLicensePackage, geoipLicensePackage]) {
        final text = byPackage[pkg]!;
        expect(text, isNot(contains('未核实')), reason: pkg);
        expect(text, isNot(contains('Unverified')), reason: pkg);
        expect(text, isNot(contains('当前主分支')), reason: pkg);
        // 仍未确认的内容单列并写明具体事项，而不是一句话带过。
        expect(text, contains('未能确认的事项'), reason: pkg);
        expect(text, contains('Not confirmed'), reason: pkg);
      }
    });
  });

  test('登记的文案不出现被禁止点名的项目', () async {
    final all = (await _registered()).values.join('\n').toLowerCase();
    // 名单以 base64 保存：公开仓库里不出现这些名字的明文。
    const encoded = [
      'aGlkZGlmeQ==',
      'YmFzZXByb3h5',
      'bmVrb2JveA==',
      'bmVrb2hhc2VrYWk=',
    ];
    for (final banned in encoded.map((e) => utf8.decode(base64.decode(e)))) {
      expect(all, isNot(contains(banned)));
    }
  });
}
