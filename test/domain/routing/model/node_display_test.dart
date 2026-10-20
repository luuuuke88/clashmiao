import 'package:clashmiao/domain/routing/model/node_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NodeDisplay.parse 开头旗帜', () {
    test('开头旗帜被搬到 flag，label 不再含它', () {
      final d = NodeDisplay.parse('🇭🇰 香港 01 | SS');
      expect(d.flag, '🇭🇰');
      expect(d.flagSource, FlagSource.leading);
      expect(d.label, '香港 01 | SS');
    });

    test('旗帜后紧跟文字（没有空格）也能搬移', () {
      final d = NodeDisplay.parse('🇯🇵东京 02');
      expect(d.flag, '🇯🇵');
      expect(d.flagSource, FlagSource.leading);
      expect(d.label, '东京 02');
    });

    test('开头旗帜与名称关键词矛盾时以订阅给出的旗帜为准', () {
      final d = NodeDisplay.parse('🇹🇼 台湾 03');
      expect(d.flag, '🇹🇼');
      expect(d.flagSource, FlagSource.leading);
      final conflict = NodeDisplay.parse('🇺🇸 香港 04');
      expect(conflict.flag, '🇺🇸');
      expect(conflict.flagSource, FlagSource.leading);
    });

    test('只有旗帜没有名字：旗帜只出现一次（在 flag），label 为空交给展示层占位', () {
      for (final tag in ['🇭🇰', ' 🇭🇰 ', '🇭🇰 §2']) {
        final d = NodeDisplay.parse(tag);
        expect(d.flag, '🇭🇰', reason: tag);
        expect(d.flagSource, FlagSource.leading, reason: tag);
        expect(d.label, isEmpty, reason: tag);
        expect(d.label.contains('🇭🇰'), isFalse, reason: '旗帜不能左右各显示一次');
      }
    });

    test('前导空格 / 制表符：检测与截取用同一个规范化字符串，旗帜不被切断', () {
      for (final tag in [' 🇭🇰 香港 01', '\t🇭🇰 香港 01', '  \t 🇭🇰香港 01 ']) {
        final d = NodeDisplay.parse(tag);
        expect(d.flag, '🇭🇰', reason: tag);
        expect(d.flagSource, FlagSource.leading, reason: tag);
        expect(d.label, '香港 01', reason: tag);
        // 没有落单的代理项（被切断的旗帜会留下孤立的 UTF-16 代理项）。
        for (final unit in d.label.codeUnits) {
          expect(unit >= 0xD800 && unit <= 0xDFFF, isFalse, reason: tag);
        }
      }
    });

    test('前导空白但没有旗帜：label 去掉首尾空白', () {
      final d = NodeDisplay.parse('  Premium Node 12 ');
      expect(d.label, 'Premium Node 12');
      expect(d.flagSource, FlagSource.none);
    });
  });

  group('NodeDisplay.parse 中间旗帜不动', () {
    test('名称中间的旗帜留在 label 里，flag 按关键词推断', () {
      final d = NodeDisplay.parse('香港 🇭🇰 01');
      expect(d.label, '香港 🇭🇰 01');
      expect(d.flag, '🇭🇰');
      expect(d.flagSource, FlagSource.inferred);
    });

    test('中间旗帜与推断不出国家时：不搬移也不采用', () {
      final d = NodeDisplay.parse('Node 🇺🇸 07');
      expect(d.label, 'Node 🇺🇸 07');
      expect(d.flagSource, FlagSource.none);
      expect(d.flag, isNull);
    });
  });

  group('NodeDisplay.parse 关键词推断', () {
    test('台湾 / tw / taiwan 推断为 🇹🇼（不是 🇨🇳）', () {
      for (final tag in ['台湾 01', 'TW-02', 'Taiwan 03', '台北 04']) {
        final d = NodeDisplay.parse(tag);
        expect(d.flag, '🇹🇼', reason: tag);
        expect(d.flagSource, FlagSource.inferred, reason: tag);
        expect(d.label, tag, reason: '推断不改名称');
      }
    });

    test('其余沿用现表：香港 / 日本 / US / 新加坡', () {
      expect(NodeDisplay.parse('香港 01 | SS').flag, '🇭🇰');
      expect(NodeDisplay.parse('日本 Tokyo 02').flag, '🇯🇵');
      expect(NodeDisplay.parse('US Los Angeles 03').flag, '🇺🇸');
      expect(NodeDisplay.parse('Singapore 04').flag, '🇸🇬');
    });

    test('两个字母的关键词必须独立成词，不误伤普通单词', () {
      // "transit" 含 "tr"，"node" 不含任何国家码独立词。
      expect(NodeDisplay.parse('transit node').flagSource, FlagSource.none);
    });

    test('中国大陆关键词仍是 🇨🇳', () {
      expect(NodeDisplay.parse('北京 01').flag, '🇨🇳');
    });
  });

  group('NodeDisplay.parse 推断不出', () {
    test('没有任何线索：flag 为空、来源 none、label 原样', () {
      final d = NodeDisplay.parse('Premium Node 12');
      expect(d.flag, isNull);
      expect(d.flagSource, FlagSource.none);
      expect(d.label, 'Premium Node 12');
    });

    test('空串不崩', () {
      final d = NodeDisplay.parse('');
      expect(d.flag, isNull);
      expect(d.flagSource, FlagSource.none);
      expect(d.label, '');
    });
  });

  group('§ 后缀处理', () {
    test('第一个 § 之后的内容被丢掉，并去掉右侧空白', () {
      final d = NodeDisplay.parse('🇭🇰 香港 01 §2');
      expect(d.label, '香港 01');
      expect(d.flag, '🇭🇰');
    });

    test('只有后缀被剥离时推断照常进行', () {
      final d = NodeDisplay.parse('台湾 01 §hide§');
      expect(d.label, '台湾 01');
      expect(d.flag, '🇹🇼');
    });

    test('stripSuffix 保留开头旗帜（供排序与长按全名使用）', () {
      expect(NodeDisplay.stripSuffix('🇭🇰 香港 01 §2'), '🇭🇰 香港 01');
      expect(NodeDisplay.stripSuffix('plain'), 'plain');
    });

    test('isHidden 识别 §hide§ 标记', () {
      expect(NodeDisplay.isHidden('x §hide§'), isTrue);
      expect(NodeDisplay.isHidden('x §2'), isFalse);
    });
  });
}
