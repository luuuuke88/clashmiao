import 'dart:convert';

import 'package:clashmiao/core/latency/latency_rules.dart';
import 'package:clashmiao/domain/routing/model/cached_delay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime.fromMillisecondsSinceEpoch(1760000000000);

  group('decodeDelayCache 读旧格式', () {
    test('纯 int 视为历史值：measuredAt 为 null', () {
      final map = decodeDelayCache(jsonEncode({'香港01': 111, 'US': 88}));
      expect(map['香港01'], const CachedDelay(111, null));
      expect(map['US'], const CachedDelay(88, null));
      expect(map['香港01']!.measuredAt, isNull);
    });

    test('数字字符串（更老的写法）同样兼容', () {
      final map = decodeDelayCache(jsonEncode({'a': '120'}));
      expect(map['a'], const CachedDelay(120, null));
    });

    test('非正数、非数字、坏条目被丢掉，其余保留', () {
      final map = decodeDelayCache(
        jsonEncode({'ok': 50, 'zero': 0, 'neg': -3, 'bad': 'x', 'n': null}),
      );
      expect(map.keys, ['ok']);
    });

    test('空串、null、非 JSON、非对象都得到空表', () {
      expect(decodeDelayCache(null), isEmpty);
      expect(decodeDelayCache(''), isEmpty);
      expect(decodeDelayCache('not json'), isEmpty);
      expect(decodeDelayCache('[1,2]'), isEmpty);
    });
  });

  group('新格式往返', () {
    test('{ms, measuredAt} 编码后再解码得到同一份数据', () {
      final src = {
        'a': CachedDelay(120, at),
        'legacy': const CachedDelay(77, null),
      };
      final back = decodeDelayCache(encodeDelayCache(src));
      expect(back, src);
      expect(back['a']!.measuredAt, at);
    });

    test('写出的是 {ms, measuredAt(毫秒时间戳)} 对象，不再是裸 int', () {
      final raw = jsonDecode(
        encodeDelayCache({'a': CachedDelay(120, at)}),
      ) as Map<String, dynamic>;
      expect(raw['a'], {'ms': 120, 'measuredAt': at.millisecondsSinceEpoch});
    });

    test('历史值（无时间）重新写出后仍是历史值，不会被冒充成刚测的', () {
      final raw = jsonDecode(
        encodeDelayCache({'a': const CachedDelay(9, null)}),
      ) as Map<String, dynamic>;
      expect((raw['a'] as Map).containsKey('measuredAt'), isFalse);
      expect(decodeDelayCache(jsonEncode(raw))['a']!.measuredAt, isNull);
    });

    test('新格式里 measuredAt 缺失或不是数字时按历史值处理', () {
      final map = decodeDelayCache(
        jsonEncode({
          'a': {'ms': 10},
          'b': {'ms': 20, 'measuredAt': 'yesterday'},
        }),
      );
      expect(map['a'], const CachedDelay(10, null));
      expect(map['b'], const CachedDelay(20, null));
    });

    test('新旧格式混在同一份缓存里（升级过渡期）', () {
      final map = decodeDelayCache(
        jsonEncode({
          'old': 100,
          'new': {'ms': 200, 'measuredAt': at.millisecondsSinceEpoch},
        }),
      );
      expect(map['old'], const CachedDelay(100, null));
      expect(map['new'], CachedDelay(200, at));
    });
  });

  group('失败记录（测过但没通）', () {
    test('失败条目编码后再解码仍是失败，不是成功，也不会被丢掉', () {
      final src = {'dead': CachedDelay.failed(at), 'ok': CachedDelay(90, at)};
      final back = decodeDelayCache(encodeDelayCache(src));
      expect(back['dead'], CachedDelay.failed(at));
      expect(back['dead']!.isFailed, isTrue);
      expect(back['dead']!.measuredAt, at);
      expect(back['ok']!.isFailed, isFalse);
    });

    test('失败条目的毫秒数落在超时哨兵之外，不是可展示的延迟', () {
      final failed = CachedDelay.failed(at);
      expect(failed.ms, greaterThan(kDelayTimeoutSentinelMs));
      expect(isMeasurableDelay(failed.ms), isFalse);
      expect(const CachedDelay(98, null).isFailed, isFalse);
    });

    test('旧版本留下的哨兵值仍被丢掉（不会被误读成失败记录）', () {
      final map = decodeDelayCache(
        jsonEncode({
          'a': 65535,
          'b': {'ms': 65535, 'measuredAt': 1},
        }),
      );
      expect(map, isEmpty);
    });
  });

  group('isMeasurableDelay', () {
    test('1..65000 是有效延迟，0 与哨兵值（>65000）不是', () {
      expect(isMeasurableDelay(1), isTrue);
      expect(isMeasurableDelay(65000), isTrue);
      expect(isMeasurableDelay(0), isFalse);
      expect(isMeasurableDelay(-1), isFalse);
      expect(isMeasurableDelay(65535), isFalse);
    });
  });
}
