import 'package:clashmiao/core/licenses/bundled_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registerBundledLicenses 登记 sing-box 内核与规则集的许可', () async {
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);

    registerBundledLicenses();

    final entries = await LicenseRegistry.licenses.toList();
    final byPackage = {
      for (final e in entries)
        for (final p in e.packages)
          p: e.paragraphs.map((p) => p.text).join('\n'),
    };

    expect(
      byPackage.keys,
      containsAll([singBoxLicensePackage, ruleSetLicensePackage]),
    );

    final singBox = byPackage[singBoxLicensePackage]!;
    expect(singBox, contains('GPL-3.0'));
    expect(singBox, contains('github.com/SagerNet/sing-box'));

    final ruleSets = byPackage[ruleSetLicensePackage]!;
    expect(ruleSets, contains('github.com/SagerNet/sing-geoip'));
    expect(ruleSets, contains('github.com/SagerNet/sing-geosite'));
  });

  test('登记的文案不出现被禁止点名的项目', () async {
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    registerBundledLicenses();

    final all = (await LicenseRegistry.licenses.toList())
        .expand((e) => e.paragraphs.map((p) => p.text))
        .join('\n')
        .toLowerCase();

    for (final banned in ['hiddify', 'baseproxy', 'nekobox', 'nekohasekai']) {
      expect(all, isNot(contains(banned)));
    }
  });
}
