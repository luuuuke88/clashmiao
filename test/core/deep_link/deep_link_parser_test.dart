import 'package:clashmiao/core/deep_link/deep_link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseDeepLink — 已注册 host 组合（AndroidManifest.xml intent-filter）', () {
    test('sing-box://import-remote-profile?url= → DeepLinkFetchUrl', () {
      final result = parseDeepLink(
        Uri.parse(
          'sing-box://import-remote-profile'
          '?url=${Uri.encodeComponent('https://example.com/sub')}',
        ),
      );
      expect(result, isA<DeepLinkFetchUrl>());
      expect((result as DeepLinkFetchUrl).url, 'https://example.com/sub');
      expect(result.customName, isNull);
    });

    test('clash://install-config?url= → DeepLinkFetchUrl', () {
      final result = parseDeepLink(
        Uri.parse(
          'clash://install-config'
          '?url=${Uri.encodeComponent('https://example.com/config.yaml')}',
        ),
      );
      expect(result, isA<DeepLinkFetchUrl>());
      expect(
        (result as DeepLinkFetchUrl).url,
        'https://example.com/config.yaml',
      );
    });

    test('clashmiao://install-sub?url= → DeepLinkFetchUrl', () {
      final result = parseDeepLink(
        Uri.parse(
          'clashmiao://install-sub'
          '?url=${Uri.encodeComponent('https://example.com/s/abc')}',
        ),
      );
      expect(result, isA<DeepLinkFetchUrl>());
      expect((result as DeepLinkFetchUrl).url, 'https://example.com/s/abc');
    });

    test('scheme 对行为没有影响：clashmeta://install-sub 与 '
        'clash://install-sub 效果与 clashmiao://install-sub 一致'
        '（Android intent-filter 里多个 <data> 是并集不是配对，'
        '真正决定行为的是 host）', () {
      const url = 'https://example.com/s/xyz';
      final encoded = Uri.encodeComponent(url);
      for (final scheme in ['clashmeta', 'clash', 'sing-box', 'clashmiao']) {
        final result = parseDeepLink(
          Uri.parse('$scheme://install-sub?url=$encoded'),
        );
        expect(
          result,
          isA<DeepLinkFetchUrl>(),
          reason: 'scheme=$scheme 应该和 host 无关地被识别',
        );
        expect((result as DeepLinkFetchUrl).url, url);
      }
    });
  });

  group('parseDeepLink — import host 的智能判定', () {
    test('import?url=<http(s) URL> → 当订阅 URL 处理（DeepLinkFetchUrl）', () {
      final result = parseDeepLink(
        Uri.parse(
          'clashmiao://import'
          '?url=${Uri.encodeComponent('https://example.com/sub')}',
        ),
      );
      expect(result, isA<DeepLinkFetchUrl>());
      expect((result as DeepLinkFetchUrl).url, 'https://example.com/sub');
    });

    for (final scheme in kDeepLinkProxyUriSchemes) {
      test('import?url=<$scheme:// 单节点 URI> → 当字面内容处理'
          '（DeepLinkImportContent）', () {
        final proxyUri = '$scheme://payload@host:443#name';
        final result = parseDeepLink(
          Uri.parse('clashmiao://import?url=${Uri.encodeComponent(proxyUri)}'),
        );
        expect(result, isA<DeepLinkImportContent>());
        expect((result as DeepLinkImportContent).content, proxyUri);
      });
    }

    test('import?url=<既不是 http(s) 也不是代理 URI 的内容> → 兜底当字面内容', () {
      final result = parseDeepLink(
        Uri.parse(
          'clashmiao://import?url=${Uri.encodeComponent('not-a-real-url')}',
        ),
      );
      expect(result, isA<DeepLinkImportContent>());
      expect((result as DeepLinkImportContent).content, 'not-a-real-url');
    });
  });

  group('parseDeepLink — 容错', () {
    test('已注册 host 但完全没带 url 参数 → DeepLinkMissingPayload', () {
      final result = parseDeepLink(Uri.parse('clashmiao://install-sub'));
      expect(result, isA<DeepLinkMissingPayload>());
    });

    test('url 参数为空字符串 → DeepLinkMissingPayload', () {
      final result = parseDeepLink(Uri.parse('clashmiao://install-sub?url='));
      expect(result, isA<DeepLinkMissingPayload>());
    });

    test('url 参数为纯空白 → DeepLinkMissingPayload（trim 后判空）', () {
      final result = parseDeepLink(
        Uri.parse('clashmiao://install-sub?url=${Uri.encodeComponent('   ')}'),
      );
      expect(result, isA<DeepLinkMissingPayload>());
    });

    test('import host 缺 url 参数 → 同样是 DeepLinkMissingPayload', () {
      final result = parseDeepLink(Uri.parse('clashmiao://import'));
      expect(result, isA<DeepLinkMissingPayload>());
    });

    test('不认识的 host → DeepLinkUnrecognized（防御性兜底，正常不会被路由到）', () {
      final result = parseDeepLink(
        Uri.parse(
          'clashmiao://totally-unknown-host'
          '?url=${Uri.encodeComponent('https://example.com/sub')}',
        ),
      );
      expect(result, isA<DeepLinkUnrecognized>());
    });

    test('没有 host 的裸 URI（例如 clashmiao:opaque）→ DeepLinkUnrecognized', () {
      final result = parseDeepLink(Uri.parse('clashmiao:opaque-payload'));
      expect(result, isA<DeepLinkUnrecognized>());
    });
  });

  group('parseDeepLink — URL-decode 与 name 参数', () {
    test('url 参数里的特殊字符（&=?/中文）解码后与原始值完全一致', () {
      const original = 'https://example.com/sub?token=a&b=1&名字=测试';
      final uri = Uri.parse(
        'clashmiao://install-sub?url=${Uri.encodeComponent(original)}',
      );
      final result = parseDeepLink(uri);
      expect(result, isA<DeepLinkFetchUrl>());
      expect((result as DeepLinkFetchUrl).url, original);
    });

    test('携带 name 参数 → customName 被提取并 URL-decode', () {
      final result = parseDeepLink(
        Uri.parse(
          'clashmiao://install-sub'
          '?url=${Uri.encodeComponent('https://example.com/sub')}'
          '&name=${Uri.encodeComponent('我的订阅')}',
        ),
      );
      expect(result, isA<DeepLinkFetchUrl>());
      expect((result as DeepLinkFetchUrl).customName, '我的订阅');
    });

    test('name 参数缺失 → customName 为 null', () {
      final result = parseDeepLink(
        Uri.parse(
          'clashmiao://install-sub'
          '?url=${Uri.encodeComponent('https://example.com/sub')}',
        ),
      );
      expect((result as DeepLinkFetchUrl).customName, isNull);
    });

    test('name 参数为空白 → customName 为 null（不把空白当有效名称）', () {
      final result = parseDeepLink(
        Uri.parse(
          'clashmiao://install-sub'
          '?url=${Uri.encodeComponent('https://example.com/sub')}'
          '&name=${Uri.encodeComponent('   ')}',
        ),
      );
      expect((result as DeepLinkFetchUrl).customName, isNull);
    });

    test('host 大小写不敏感', () {
      final result = parseDeepLink(
        Uri.parse(
          'clashmiao://INSTALL-SUB'
          '?url=${Uri.encodeComponent('https://example.com/sub')}',
        ),
      );
      expect(result, isA<DeepLinkFetchUrl>());
    });
  });
}
