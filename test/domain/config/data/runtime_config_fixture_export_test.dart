import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/domain/config/data/runtime_config_builder.dart';
import 'package:clashmiao/domain/config/model/advanced_config.dart';
import 'package:clashmiao/domain/config/model/subscription_info_node.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/golden_file.dart';
import '../../../support/temp_dirs.dart';

/// 跨语言契约：Dart 的 `RuntimeConfigBuilder` 对 Go 侧 profile 夹具（P1–P8，含端点
/// 三形态 P4a / P4b / P4c 与旧 1.8 形态 P7）构建出的 runtime-config.json，入库成
/// `kernel/testdata/dart/runtime-config-*.json`。Go 的 `dart_profiles_test.go` 把它们
/// 全部喂给 `BuildConfig`：禁用键扫描为零，适配副本通过 `CheckConfig` 与真 `Start`。
///
/// 输入夹具归 Go 侧所有（`kernel/internal/build/testdata/profiles/`），这里只读。
const _profileDir = 'kernel/internal/build/testdata/profiles';
const _outDir = 'kernel/testdata/dart';

/// 订阅级 mux（高级配置）：multiplex 由 Dart 注入各出站，内核不再写第二份。
const _muxAdvanced = AdvancedConfig(
  muxEnabled: true,
  muxProtocol: 'h2mux',
  muxConcurrency: 8,
);

class _Variant {
  const _Variant(this.name, this.profile, {this.advanced});

  final String name;
  final String profile;
  final AdvancedConfig? advanced;
}

List<String> _profiles() => [
  for (final f in Directory(_profileDir).listSync().whereType<File>())
    if (f.path.endsWith('.json'))
      f.uri.pathSegments.last.replaceAll('.json', ''),
]..sort();

List<_Variant> _variants() => [
  for (final p in _profiles()) _Variant(p, p),
  // 带信息节点的订阅 + 订阅级 mux：隐藏标记与 multiplex 注入一起过 Go。
  const _Variant('P2-mux', 'P2', advanced: _muxAdvanced),
];

String _pretty(String compactJson) =>
    '${const JsonEncoder.withIndent('  ').convert(jsonDecode(compactJson))}\n';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rcfx_');
  });

  tearDown(() async {
    await deleteTempDirBestEffort(tmp);
  });

  test('输入夹具齐全：P1–P8（含端点三形态）都在', () {
    expect(
      _profiles(),
      containsAll(['P1', 'P2', 'P3', 'P4a', 'P4b', 'P4c', 'P5', 'P6', 'P7']),
    );
  });

  for (final v in _variants()) {
    test(
      'runtime-config-${v.name}.json 与 RuntimeConfigBuilder 的输出逐字节一致',
      () async {
        final out = await RuntimeConfigBuilder().build(
          baseProfile: File('$_profileDir/${v.profile}.json'),
          workingDir: tmp,
          // 连接启动器仍然传它；构建器不再写 dns，输出与它无关。
          remoteDnsAddress: 'https://1.1.1.1/dns-query',
          advancedConfig: v.advanced,
        );
        expectGoldenFile(
          '$_outDir/runtime-config-${v.name}.json',
          _pretty(await out.readAsString()),
        );
      },
    );
  }

  test('夹具目录里没有变体之外的文件', () {
    final want = {for (final v in _variants()) 'runtime-config-${v.name}.json'};
    if (updateGolden) {
      for (final f in Directory(_outDir).listSync().whereType<File>()) {
        if (!want.contains(f.uri.pathSegments.last)) f.deleteSync();
      }
    }
    final names = {
      for (final f in Directory(_outDir).listSync().whereType<File>())
        f.uri.pathSegments.last,
    };
    expect(names, want);
  });

  test('导出的是构建器真正做的事：mux 注入、信息节点打标记、mixed / tun 被剥', () async {
    final out = await RuntimeConfigBuilder().build(
      baseProfile: File('$_profileDir/P2.json'),
      workingDir: tmp,
      advancedConfig: _muxAdvanced,
    );
    final cfg = jsonDecode(await out.readAsString()) as Map<String, dynamic>;
    final outbounds = (cfg['outbounds'] as List).cast<Map<String, dynamic>>();
    expect(
      outbounds.any((o) => (o['tag'] as String).contains(kHideNodeMarker)),
      isTrue,
      reason: 'P2 里的「剩余流量」应被打上隐藏标记',
    );
    expect(
      outbounds.any((o) => o['multiplex'] is Map),
      isTrue,
      reason: '至少一个出站被注入了 multiplex',
    );
    expect(
      (cfg['inbounds'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((i) => i['type'] == 'mixed' || i['type'] == 'tun'),
      isEmpty,
    );
  });
}
