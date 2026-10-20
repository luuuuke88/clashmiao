import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/model/box_stats.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/box_service/platform_box_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 线格式通道测试（spec §4.2）：Kotlin 经**真实的** EventChannel 编解码器编出的信封
/// 黄金文件（`kernel/testdata/wire/`，U15 产出），原样字节经真实的 `EventChannel`
/// 投递给 `PlatformBoxService` 的流，断言 Dart 侧解出的统计与分组。
///
/// 为什么不直接把 Dart 里手造的 `Map<String, dynamic>` 喂给流：那样测的只是 Dart
/// 自己的解析，抓不到「统计被透传成字符串」「JSON 信封外多包一层」这类跨语言的
/// 线格式错误——这正是旧内核迁移最容易悄悄坏掉的地方。
///
/// - 统计通道 `com.clashmiao.app/stats`：`JSONMethodCodec`，事件是 JSON 对象；
/// - 分组通道 `com.clashmiao.app/groups`：默认 `StandardMethodCodec`，事件是 JSON 字符串。
const _statsName = 'com.clashmiao.app/stats';
const _groupsName = 'com.clashmiao.app/groups';
const _wireDir = 'kernel/testdata/wire';

Uint8List _bytes(String name) => File('$_wireDir/$name').readAsBytesSync();

ByteData _data(List<int> bytes) =>
    ByteData.sublistView(Uint8List.fromList(bytes));

/// 黄金文件里的分组信封：base64 文本（文件里是一行 base64）。
Uint8List _groupsEnvelope() =>
    base64Decode(utf8.decode(_bytes('groups-envelope.b64')).trim());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// 让真实的 EventChannel 能 `listen` / `cancel`：对 Dart → 原生的方法调用回成功信封。
  void mockPlatformSide(String name, MethodCodec codec) {
    messenger.setMockMethodCallHandler(
      MethodChannel(name, codec),
      (call) async => null,
    );
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(MethodChannel(name, codec), null),
    );
  }

  /// 订阅 [stream]、等监听建立、把 [envelope] 的原始字节作为平台事件投递，返回收到的事件。
  Future<List<T>> deliver<T>(
    Stream<T> stream,
    String channel,
    List<int> envelope,
  ) async {
    final received = <T>[];
    final sub = stream.listen(received.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await messenger.handlePlatformMessage(channel, _data(envelope), (_) {});
    await pumpEventQueue();
    return received;
  }

  group('统计通道（JSONMethodCodec）', () {
    setUp(() => mockPlatformSide(_statsName, const JSONMethodCodec()));

    test('黄金信封 → 非零的 BoxStats，逐字段等于 stats-frame.json', () async {
      final expected = jsonDecode(
        utf8.decode(_bytes('stats-frame.json')),
      ) as Map<String, dynamic>;
      final got = await deliver<BoxStats>(
        PlatformBoxService().watchStats(),
        _statsName,
        _bytes('stats-envelope.json'),
      );

      expect(got, hasLength(1));
      final s = got.single;
      expect(s.uplink, expected['uplink']);
      expect(s.downlink, expected['downlink']);
      expect(s.uplinkTotal, expected['uplink-total']);
      expect(s.downlinkTotal, expected['downlink-total']);
      expect(s.connectionsIn, expected['connections-in']);
      expect(s.connectionsOut, expected['connections-out']);
      // 非零：防止「全 0 的默认值」也满足逐字段相等。
      expect([
        s.uplink,
        s.downlink,
        s.uplinkTotal,
        s.downlinkTotal,
        s.connectionsIn,
        s.connectionsOut,
      ], everyElement(greaterThan(0)));
    });

    test('反例：把统计编成字符串的信封 → BoxStats.empty（证明测试抓得住「统计被透传成字符串」）', () async {
      // 与黄金文件相同的内容，但事件是 JSON 字符串而不是对象：`["{...}"]`。
      final frame = utf8.decode(_bytes('stats-frame.json'));
      final asString = utf8.encode(jsonEncode([frame]));
      final got = await deliver<BoxStats>(
        PlatformBoxService().watchStats(),
        _statsName,
        asString,
      );

      expect(got, hasLength(1));
      final s = got.single;
      expect(s.uplink, BoxStats.empty.uplink);
      expect(s.downlinkTotal, BoxStats.empty.downlinkTotal);
      expect(s.connectionsOut, BoxStats.empty.connectionsOut);
    });

    test('信封黄金文件本身是一个 JSON 数组，里面是对象（线格式没有被改动）', () {
      final decoded = jsonDecode(utf8.decode(_bytes('stats-envelope.json')));
      expect(decoded, isList);
      expect((decoded as List).single, isA<Map<String, dynamic>>());
    });
  });

  group('分组通道（StandardMethodCodec）', () {
    setUp(() => mockPlatformSide(_groupsName, const StandardMethodCodec()));

    test('黄金信封 → 非空的 OutboundGroup 列表', () async {
      final got = await deliver<List<OutboundGroup>>(
        PlatformBoxService().watchGroups(),
        _groupsName,
        _groupsEnvelope(),
      );

      expect(got, hasLength(1));
      final groups = got.single;
      expect(groups, isNotEmpty);
      final select = groups.firstWhere((g) => g.tag == 'select');
      expect(select.type, 'selector');
      expect(select.selected, 'auto');
      expect(select.items.map((i) => i.tag), ['auto', 'a', 'b']);
      expect(select.items.map((i) => i.type), ['urltest', 'direct', 'direct']);
      final auto = groups.firstWhere((g) => g.tag == 'auto');
      expect(auto.type, 'urltest');
      expect(auto.selected, 'a');
      expect(auto.items.map((i) => i.tag), ['a', 'b']);
    });

    test('反例：信封不是字符串（被多包了一层对象）→ 空列表，不抛', () async {
      // 标准编解码器的成功信封：0 + 值。这里值是一个 Map，不是 JSON 字符串。
      final envelope = const StandardMethodCodec().encodeSuccessEnvelope({
        'groups': <Object>[],
      });
      final got = await deliver<List<OutboundGroup>>(
        PlatformBoxService().watchGroups(),
        _groupsName,
        envelope.buffer.asUint8List(0, envelope.lengthInBytes),
      );

      expect(got, hasLength(1));
      expect(got.single, isEmpty);
    });

    test('信封黄金文件：首字节是标准编解码器的成功标记 0，后面是字符串', () {
      final bytes = _groupsEnvelope();
      expect(bytes.first, 0);
      final value = const StandardMessageCodec().decodeMessage(
        ByteData.sublistView(bytes, 1),
      );
      expect(value, isA<String>());
      expect(jsonDecode(value as String), isList);
    });
  });
}
