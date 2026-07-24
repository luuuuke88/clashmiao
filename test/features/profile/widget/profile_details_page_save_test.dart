import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/features/profile/widget/profile_details_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 记录被打了几次的假 [HttpClientAdapter]——验证"保存时是否真的发起了重新
/// 拉取"，不关心响应内容，只关心**请求次数**。
///
/// ## 为什么是 adapter 层假实现，而不是起一个真的 HttpServer
///
/// 这个文件之前用真实 `HttpServer` + 真实 socket + 自己写的 `DateTime.now()`
/// 墙钟 deadline（`_pumpUntil`，10 秒）来数请求次数，结果是**间歇性 flaky**：
/// 单独跑必过，全量跑（`flutter test` 会并发跑多个测试文件，机器负载高）时
/// 会偶发超时失败，导致 CI 随机变红。把超时数字调大只是降低概率，不解决
/// "断言依赖不可控的墙钟与系统负载"这个根子。
///
/// 换成 adapter 层假实现后，去掉的是真正的 flake 来源：
/// - 真实 socket / 端口绑定 / DNS
/// - `ProfileRepository` 那个 `connectTimeout: 3s`（负载高时可能先超时）
/// - `HttpOverrides.global = null` 这个绕开测试框架全局 HTTP mock 的 hack
/// - 自己手写的墙钟轮询 deadline
///
/// 断言强度不变：`ProfileRepository` 的两处拉取都走注入的这个 `dio`
/// （`profile_repository.dart` 的 `dio.get<String>()`），Dio 的完整请求管线
/// （options / 拦截器 / 响应解析）仍被真实执行，只是不落到 socket。
///
/// ## 为什么保留 `runAsync` + 手写轮询（而不是改用 `pumpAndSettle`）
///
/// 两条硬约束让"真实时间等待"在这里无法消除，实测都撞过：
/// 1. `ProfileRepository` 写的是**真实文件**（`configDir` 下的 config json），
///    真实文件 I/O 在 widget test 默认的 fake-time zone 里根本完不成 → 必须
///    `runAsync`。
/// 2. `_save()` 期间 `_busy = true` 会渲染 `CircularProgressIndicator`，那是
///    一个**无限动画** → `pumpAndSettle()` 在这个窗口内永远收敛不了（实测报
///    `pumpAndSettle timed out`）。所以不能用它来等保存完成。
///
/// 因此保留 [_pumpUntil]。但它现在等的只是**本地文件 I/O + 微任务**（毫秒
/// 级），不再等一个可能被系统负载拖慢的真实网络往返，deadline 给得很宽，
/// 不会再被负载判死。这是这次修复与"把超时数字调大"的本质区别：去掉的是
/// 争用源本身，而不是给症状加余量。
///
/// 写法沿用仓库既有范式（`egress_ip_service_test.dart` /
/// `app_http_client_test.dart` / `region_detection_service_test.dart` 里的
/// 同款 `_FakeAdapter`）。
class _CountingAdapter implements HttpClientAdapter {
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    return ResponseBody.fromString(
      jsonEncode({
        'outbounds': [
          {'type': 'vless', 'tag': 'node'},
        ],
      }),
      HttpStatus.ok,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 反复小步 pump，直到 [condition] 成立或到达 [timeout]。
///
/// deadline 取 60 秒：这里等的是本地文件写入（正常毫秒级），给两个数量级的
/// 余量纯粹是为了让"系统负载"永远不可能成为判定因素——不是在给一个真实很慢
/// 的操作留时间。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 60),
  Duration step = const Duration(milliseconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('_pumpUntil 超时（$timeout）仍未满足条件');
    }
    await Future.delayed(step);
    await tester.pump(step);
  }
}

Future<Widget> _host({
  required ProfileRepository repo,
  required ProfileEntity profile,
}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
      profileListProvider.overrideWith((_) => Future.value(repo.getAll())),
      activeProfileProvider.overrideWith((_) => Future.value(profile)),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  await container.read(profileListProvider.future);
  await container.read(activeProfileProvider.future);

  return UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
          splashFactory: NoSplash.splashFactory,
        ),
        home: ProfileDetailsPage(profile.id),
      ),
    ),
  );
}

void main() {
  group('ProfileDetailsPage._save 保存时的重新拉取行为', () {
    late Directory tmpDir;
    late ProfileRepository repo;
    late _CountingAdapter adapter;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('details_save_');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      adapter = _CountingAdapter();
      final dio = Dio();
      dio.httpClientAdapter = adapter;
      repo = ProfileRepository(
        dio: dio,
        configDir: tmpDir,
        prefs: prefs,
        boxService: const StubBoxService(),
      );
    });

    tearDown(() async {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });

    testWidgets('URL 变化时保存会触发一次真实的重新拉取', (tester) async {
      await tester.runAsync(() async {
        final profile = ProfileEntity(
          id: 'p1',
          name: '旧订阅',
          url: 'https://old.example.invalid/sub',
          active: true,
          lastUpdate: DateTime.now(),
        );
        await repo.upsert(profile.toJson());
        // upsert 本身也走 dio（把订阅内容拉下来落盘），先归零，让后面的断言
        // 只统计"保存动作"引发的请求。
        adapter.requestCount = 0;

        await tester.pumpWidget(await _host(repo: repo, profile: profile));
        await tester.pump(const Duration(milliseconds: 250));

        final urlField = find.byWidgetPredicate(
          (w) => w is TextField && w.keyboardType == TextInputType.url,
        );
        expect(urlField, findsOneWidget);
        await tester.enterText(urlField, 'https://new.example.invalid/new');
        await tester.tap(find.text('保存'));
        await tester.pump();
        await _pumpUntil(tester, () => adapter.requestCount > 0);
        await _pumpUntil(
          tester,
          () =>
              repo.getAll().firstWhere((p) => p.id == 'p1').url ==
              'https://new.example.invalid/new',
        );

        expect(adapter.requestCount, 1);
        expect(
          repo.getAll().firstWhere((p) => p.id == 'p1').url,
          'https://new.example.invalid/new',
        );
      });
    });

    testWidgets('URL 未变化时保存不应该发起多余的网络请求', (tester) async {
      await tester.runAsync(() async {
        final profile = ProfileEntity(
          id: 'p2',
          name: '旧订阅',
          url: 'https://unchanged.example.invalid/sub',
          active: true,
          lastUpdate: DateTime.now(),
        );
        await repo.upsert(profile.toJson());
        adapter.requestCount = 0;

        await tester.pumpWidget(await _host(repo: repo, profile: profile));
        await tester.pump(const Duration(milliseconds: 250));

        // 只改名称，不改网址
        await tester.enterText(find.byType(TextField).first, '新名称');
        await tester.tap(find.text('保存'));
        await tester.pump();
        await _pumpUntil(
          tester,
          () => repo.getAll().firstWhere((p) => p.id == 'p2').name == '新名称',
        );

        expect(adapter.requestCount, 0);
        expect(repo.getAll().firstWhere((p) => p.id == 'p2').name, '新名称');
      });
    });
  });
}
