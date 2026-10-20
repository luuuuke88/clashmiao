import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../tools/srsdump/gen_cn_direct_rules.dart';
import '../../../support/temp_dirs.dart';

// 生成管线端到端：固定的 srsdump 原始产物 + 测试专用排除表，走生成器的读文件 →
// 排除 → 渲染整条路径，断言完整输出。cn_direct_rules_test.dart 只对已经生成好
// 的清单再跑一遍排除，覆盖不到「生成器读了排除表、排除结果确实写进了输出」。

const _fixtures = 'test/domain/config/data/fixtures/cn_direct_pipeline';
const _golden = '$_fixtures/expected_cn_direct_rules.golden';

CnDirectGeneration _generate({
  String exclusionsPath = '$_fixtures/exclusions.txt',
}) => generateCnDirectRules(
  sitePath: '$_fixtures/site.json',
  ipPath: '$_fixtures/ip.json',
  exclusionsPath: exclusionsPath,
);

void main() {
  test('完整输出与金样一致（含 cn 宽后缀改写出的正则常量）', () {
    final rendered = _generate().rendered;
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      File(_golden).writeAsStringSync(rendered);
    }
    expect(
      rendered,
      File(_golden).readAsStringSync(),
      reason: '生成器输出变了：确认改动符合预期后用 UPDATE_GOLDENS=1 重跑本测试更新金样',
    );
  });

  test('输出里的清单：谷歌系条目与谷歌北京地址段被剔除，正常国内条目保留', () {
    final lists = _generate().lists;
    expect(lists.domains, ['www.baidu.com', 'www.gov.cn', 'map.qq.com']);
    expect(lists.suffixes, ['.baidu', 'baidu.com', 'qq.com', 'taobao.com']);
    expect(lists.cidrs, isNot(contains('203.208.0.0/16')));
    expect(lists.cidrs, isNot(contains('2401:3800::/32')));
    expect(
      lists.cidrs,
      containsAll(['1.0.1.0/24', '223.5.5.0/24', '240e::/20']),
    );
    // 203.208.0.0/16 被拆开，只挖掉 203.208.32.0/19。
    expect(
      lists.cidrs.where((c) => c.startsWith('203.208.')),
      unorderedEquals([
        '203.208.0.0/19',
        '203.208.64.0/18',
        '203.208.128.0/17',
      ]),
    );
    // 宽后缀 cn 改写成正则：仍匹配普通 .cn 域名，跳过被排除的谷歌系 .cn。
    expect(lists.rewrittenSuffixes, ['cn']);
    final re = RegExp(lists.regexes.single);
    for (final d in ['cn', 'example.cn', 'www.gov.cn', 'gg.cn', 'googlex.cn']) {
      expect(re.hasMatch(d), isTrue, reason: d);
    }
    for (final d in ['g.cn', 'www.google.cn', 'fonts.googleapis.cn']) {
      expect(re.hasMatch(d), isFalse, reason: d);
    }
  });

  test('排除表文件确实被读取：测试专用表里临时多一条，输出随之改变', () async {
    final tmp = await Directory.systemTemp.createTemp('cn_direct_pipeline_');
    addTearDown(() => deleteTempDirBestEffort(tmp));
    final table = File('${tmp.path}/exclusions.txt')
      ..writeAsStringSync(
        '${File('$_fixtures/exclusions.txt').readAsStringSync()}\n'
        'taobao.com\n',
      );

    final base = _generate();
    final extra = _generate(exclusionsPath: table.path);

    expect(extra.rendered, isNot(base.rendered));
    expect(base.lists.suffixes, contains('taobao.com'));
    expect(extra.lists.suffixes, isNot(contains('taobao.com')));
    expect(
      extra.rendered,
      base.rendered
          .replaceFirst("  'taobao.com',\n", '')
          .replaceFirst('国内域名后缀（4 条）', '国内域名后缀（3 条）'),
      reason: '除了这一条，其余输出不变',
    );
  });

  test('不传排除表路径时读仓库里真正的排除表', () {
    final lists = generateCnDirectRules(
      sitePath: '$_fixtures/site.json',
      ipPath: '$_fixtures/ip.json',
    ).lists;
    expect(kCnDirectExclusionsPath, 'tools/srsdump/cn_direct_exclusions.txt');
    expect(lists.domains, isNot(contains('www.google.cn')));
    expect(lists.suffixes, isNot(contains('gstatic.com')));
    expect(lists.cidrs.where((c) => c.startsWith('2401:3800:')), isEmpty);
  });
}
