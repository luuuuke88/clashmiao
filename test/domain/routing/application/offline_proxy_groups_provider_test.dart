import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// 订阅配置：自带一个叫 `proxy` 的 selector（运行时会被内核丢掉重建）。
final _profile = jsonEncode({
  'outbounds': [
    {
      'type': 'selector',
      'tag': 'proxy',
      'outbounds': ['hk', 'sg'],
    },
    {'type': 'vless', 'tag': 'hk'},
    {'type': 'vless', 'tag': 'sg'},
  ],
});

/// 内核编译出的运行时配置：主选择组 `select` + 自动选择组 `auto`。
final _runtime = jsonEncode({
  'outbounds': [
    {
      'type': 'selector',
      'tag': 'select',
      'outbounds': ['auto', 'hk', 'sg'],
      'default': 'auto',
    },
    {
      'type': 'urltest',
      'tag': 'auto',
      'outbounds': ['hk', 'sg'],
    },
    {'type': 'vless', 'tag': 'hk'},
    {'type': 'vless', 'tag': 'sg'},
  ],
});

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('offline_groups');
    path = '${dir.path}/profile.json';
    await File(path).writeAsString(_profile);
  });

  tearDown(() => dir.delete(recursive: true));

  // 真机验收 BUG-1：离线分组取自订阅配置，tag（proxy）在运行时不存在。
  test('能编译时取运行时形态：分组 tag 与连接后内核报出的一致', () async {
    final groups = await loadOfflineGroups(
      path,
      compile: (_) async => _runtime,
    );
    expect(groups.map((g) => g.tag), ['select', 'auto']);
    expect(groups.first.selected, 'auto');
  });

  test('编译不可用 / 失败 / 为空：退回直接解析订阅配置', () async {
    expect((await loadOfflineGroups(path)).map((g) => g.tag), ['proxy']);
    expect(
      (await loadOfflineGroups(
        path,
        compile: (_) async => throw StateError('x'),
      )).map((g) => g.tag),
      ['proxy'],
    );
    expect(
      (await loadOfflineGroups(
        path,
        compile: (_) async => null,
      )).map((g) => g.tag),
      ['proxy'],
    );
  });
}
