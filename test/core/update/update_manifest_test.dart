import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/update/update_checker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 起一个假的官网端点，可以按路径给不同响应，并记录收到过哪些请求。
class _FakeSite {
  _FakeSite(this._server);

  final HttpServer _server;
  final List<String> requestedPaths = [];

  static Future<_FakeSite> start({
    required Map<String, Object?> manifest,
    int manifestStatus = 200,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final site = _FakeSite(server);
    // ignore: unawaited_futures
    server.listen((req) async {
      site.requestedPaths.add(req.uri.path);
      if (manifestStatus != 200) {
        req.response.statusCode = manifestStatus;
      } else {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(manifest));
      }
      await req.response.close();
    });
    return site;
  }

  String get manifestUrl => 'http://localhost:${_server.port}/api/latest.json';
  Future<void> close() => _server.close(force: true);
}

Map<String, Object?> _manifest(String version) => {
  'version': version,
  'tag': 'v$version',
  'publishedAt': '2026-07-26T20:23:00Z',
  'notesUrl': 'https://example.test/releases/tag/v$version',
  'platforms': {
    'android': {
      'name': 'ClashMiao-Android-arm64-v8a-$version.apk',
      'url': 'https://example.test/download/app.apk',
      'size': 1024,
      'sha256': 'a' * 64,
    },
  },
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'ClashMiao',
      packageName: 'com.clashmiao.clashmiao',
      version: '0.1.1',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('官网端点报告了更高版本时，返回该 tag', () async {
    final site = await _FakeSite.start(manifest: _manifest('0.2.0'));
    addTearDown(site.close);
    final prefs = await SharedPreferences.getInstance();

    final result = await UpdateChecker.checkOnce(
      prefs,
      dio: Dio(),
      manifestUrl: site.manifestUrl,
    );

    expect(result, 'v0.2.0');
    expect(site.requestedPaths, ['/api/latest.json']);
  });

  test('官网端点报告的版本不比当前新时，返回 null', () async {
    final site = await _FakeSite.start(manifest: _manifest('0.1.1'));
    addTearDown(site.close);
    final prefs = await SharedPreferences.getInstance();

    final result = await UpdateChecker.checkOnce(
      prefs,
      dio: Dio(),
      manifestUrl: site.manifestUrl,
    );

    expect(result, isNull);
  });

  test('官网端点不可用时，回退到 GitHub API', () async {
    // 官网挂了不该让"检查更新"整个失效——GitHub 那条路仍然要走通。
    final site = await _FakeSite.start(manifest: {}, manifestStatus: 503);
    addTearDown(site.close);

    final github = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => github.close(force: true));
    var githubHit = false;
    // ignore: unawaited_futures
    github.listen((req) async {
      githubHit = true;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'tag_name': 'v0.3.0'}));
      await req.response.close();
    });

    final prefs = await SharedPreferences.getInstance();
    final result = await UpdateChecker.checkOnce(
      prefs,
      dio: Dio(),
      manifestUrl: site.manifestUrl,
      githubApiUrl: 'http://localhost:${github.port}/releases/latest',
    );

    expect(githubHit, isTrue, reason: '官网端点失败后应当回退到 GitHub');
    expect(result, 'v0.3.0');
  });

  test('24 小时内不重复发起网络请求', () async {
    final site = await _FakeSite.start(manifest: _manifest('0.2.0'));
    addTearDown(site.close);
    final prefs = await SharedPreferences.getInstance();

    await UpdateChecker.checkOnce(
      prefs,
      dio: Dio(),
      manifestUrl: site.manifestUrl,
    );
    final firstCount = site.requestedPaths.length;

    // 第二次调用应当直接用缓存下来的 tag，不再打网络
    final again = await UpdateChecker.checkOnce(
      prefs,
      dio: Dio(),
      manifestUrl: site.manifestUrl,
    );

    expect(site.requestedPaths.length, firstCount, reason: '不该重复请求');
    expect(again, 'v0.2.0', reason: '缓存命中时仍应正确报告有新版本');
  });
}
