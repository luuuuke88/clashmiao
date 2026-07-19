import 'package:clashmiao/shared/components/profile_form_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/// 通用导入入口（“添加订阅”弹窗）判断“输入内容该走 HTTP 下载还是当作
/// 节点/订阅内容直接解析”的方向测试。
///
/// 正确方向：只有 http/https scheme 的地址才叫“URL”，走 HTTP 下载；
/// 其余任何内容（不管是不是认识的协议前缀）都应该走“当内容解析”，
/// 不应该对着它发起 HTTP 请求。
void main() {
  group('isHttpDownloadUrl', () {
    test('http(s) 地址应该判定为 URL，走下载路径', () {
      expect(isHttpDownloadUrl('https://example.com/sub'), isTrue);
      expect(isHttpDownloadUrl('http://example.com/sub?token=abc'), isTrue);
    });

    test('未在硬编码白名单里的真实节点协议应该走内容解析，不应被当成 URL', () {
      expect(isHttpDownloadUrl('ssconf://user:pass@example.com:1234'), isFalse);
      expect(isHttpDownloadUrl('wg://example.com/config'), isFalse);
      expect(isHttpDownloadUrl('ssh://user@example.com:22'), isFalse);
      expect(isHttpDownloadUrl('warp://example.com/register'), isFalse);
    });

    test('已知的 7 个节点协议应该走内容解析（回归）', () {
      for (final scheme in [
        'ss',
        'vless',
        'vmess',
        'trojan',
        'hysteria',
        'hysteria2',
        'tuic',
      ]) {
        expect(
          isHttpDownloadUrl('$scheme://payload@example.com:443'),
          isFalse,
          reason: '$scheme:// 应该走内容解析',
        );
      }
    });

    test('裸文本（不含 :// ）应该走内容解析', () {
      // 常见场景：base64 编码的订阅内容 / 纯 JSON 配置片段。
      expect(
        isHttpDownloadUrl(
          'c3M6Ly9hZXMtMjU2LWdjbTpwYXNzd29yZEAxLjIuMy40OjgzODg=',
        ),
        isFalse,
      );
      expect(isHttpDownloadUrl('{"outbounds": []}'), isFalse);
    });
  });
}
