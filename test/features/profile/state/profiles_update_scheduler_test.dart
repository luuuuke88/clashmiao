import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/features/profile/state/profiles_update_scheduler.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/temp_dirs.dart';

Future<HttpServer> _countingServer(void Function() onRequest) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  // ignore: unawaited_futures
  server.listen((req) async {
    onRequest();
    req.response.write(
      jsonEncode({
        'outbounds': [
          {'type': 'vless', 'tag': 'node'},
        ],
      }),
    );
    await req.response.close();
  });
  return server;
}

void main() {
  group('isProfileDue（纯函数）', () {
    final now = DateTime(2026, 7, 19, 12);

    ProfileEntity remote({
      required Duration updateInterval,
      DateTime? lastUpdate,
    }) {
      return ProfileEntity(
        id: 'r',
        name: 'r',
        url: 'https://example.com/sub',
        updateInterval: updateInterval,
        lastUpdate: lastUpdate,
      );
    }

    test('超过 updateInterval 的远程订阅到期', () {
      final p = remote(
        updateInterval: const Duration(hours: 6),
        lastUpdate: now.subtract(const Duration(hours: 7)),
      );
      expect(isProfileDue(p, now), isTrue);
    });

    test('未到 updateInterval 的远程订阅不到期', () {
      final p = remote(
        updateInterval: const Duration(hours: 6),
        lastUpdate: now.subtract(const Duration(hours: 1)),
      );
      expect(isProfileDue(p, now), isFalse);
    });

    test('恰好等于 updateInterval 视为到期（>=）', () {
      final p = remote(
        updateInterval: const Duration(hours: 6),
        lastUpdate: now.subtract(const Duration(hours: 6)),
      );
      expect(isProfileDue(p, now), isTrue);
    });

    test('updateInterval 为 0（用户禁用自动更新）永不到期', () {
      final p = remote(
        updateInterval: Duration.zero,
        lastUpdate: now.subtract(const Duration(days: 30)),
      );
      expect(isProfileDue(p, now), isFalse);
    });

    test('本地导入（content:// URL）不参与自动更新', () {
      final p = ProfileEntity(
        id: 'l',
        name: 'local',
        url: 'content://abc',
        updateInterval: const Duration(hours: 1),
        lastUpdate: now.subtract(const Duration(days: 30)),
      );
      expect(isProfileDue(p, now), isFalse);
    });

    test('从未更新过（lastUpdate 为 null）视为已到期', () {
      final p = remote(updateInterval: const Duration(hours: 6));
      expect(isProfileDue(p, now), isTrue);
    });
  });

  group('ProfileUpdateScheduler.checkAndRefreshDue', () {
    late Directory tmpDir;
    late ProfileRepository repo;

    setUp(() async {
      HttpOverrides.global = null;
      tmpDir = await Directory.systemTemp.createTemp('scheduler_test_');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: prefs,
        boxService: const StubBoxService(),
      );
    });

    tearDown(() async {
      await deleteTempDirBestEffort(tmpDir);
    });

    test('到期的订阅被静默刷新，未到期的不会被打扰', () async {
      var dueCallCount = 0;
      var freshCallCount = 0;
      final dueServer = await _countingServer(() => dueCallCount++);
      final freshServer = await _countingServer(() => freshCallCount++);
      addTearDown(() => dueServer.close(force: true));
      addTearDown(() => freshServer.close(force: true));

      final now = DateTime.now();

      final dueProfile = await repo.addByUrl(
        'http://localhost:${dueServer.port}/due',
        customName: 'due',
      );
      final freshProfile = await repo.addByUrl(
        'http://localhost:${freshServer.port}/fresh',
        customName: 'fresh',
      );

      // 手动把 due 的 lastUpdate 拨回很久以前（超过 updateInterval），
      // fresh 的 lastUpdate 保持刚刚（未到期）。
      await repo.updateProfile(
        dueProfile.copyWith(
          updateInterval: const Duration(hours: 1),
          lastUpdate: now.subtract(const Duration(hours: 2)),
        ),
      );
      await repo.updateProfile(
        freshProfile.copyWith(
          updateInterval: const Duration(hours: 6),
          lastUpdate: now,
        ),
      );
      // addByUrl 已经各打了一次 server，重新清零方便下面精确断言。
      dueCallCount = 0;
      freshCallCount = 0;

      final scheduler = ProfileUpdateScheduler(
        repositoryProvider: () async => repo,
      );

      final refreshed = await scheduler.checkAndRefreshDue();

      expect(dueCallCount, 1);
      expect(freshCallCount, 0);
      expect(refreshed.map((p) => p.id), [dueProfile.id]);
    });

    test('并发调用会被去重，不会叠加触发', () async {
      var callCount = 0;
      final server = await _countingServer(() => callCount++);
      addTearDown(() => server.close(force: true));

      final profile = await repo.addByUrl(
        'http://localhost:${server.port}/due',
      );
      await repo.updateProfile(
        profile.copyWith(
          updateInterval: const Duration(hours: 1),
          lastUpdate: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );
      callCount = 0;

      final scheduler = ProfileUpdateScheduler(
        repositoryProvider: () async => repo,
      );

      final results = await Future.wait([
        scheduler.checkAndRefreshDue(),
        scheduler.checkAndRefreshDue(),
      ]);

      // 两次并发调用总共只应该真正刷新一次（另一次被 `_checking` 闸门挡掉，
      // 返回空列表）。
      expect(callCount, 1);
      expect(results.expand((r) => r).length, 1);
    });

    test('单条刷新失败不影响其它到期订阅', () async {
      final okServer = await _countingServer(() {});
      addTearDown(() => okServer.close(force: true));
      // 一个必定会验证失败的订阅：StubBoxService 直接写原文，所以用一个不会
      // 抛错的仓库路径反而测不出"刷新失败"——这里改用一个会在 update() 内部
      // 抛错的场景：目标 host 没有监听（一个从未绑定的本地端口），dio 请求
      // 会抛异常。
      final unreachableProfile = ProfileEntity(
        id: 'unreachable',
        name: 'unreachable',
        url: 'http://127.0.0.1:1/unreachable',
        updateInterval: const Duration(hours: 1),
        lastUpdate: DateTime.now().subtract(const Duration(hours: 2)),
      );
      await repo.upsert(unreachableProfile.toJson());

      final okProfile = await repo.addByUrl(
        'http://localhost:${okServer.port}/ok',
        customName: 'ok',
      );
      await repo.updateProfile(
        okProfile.copyWith(
          updateInterval: const Duration(hours: 1),
          lastUpdate: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );

      final scheduler = ProfileUpdateScheduler(
        repositoryProvider: () async => repo,
      );

      final refreshed = await scheduler.checkAndRefreshDue();

      // 不可达的那条刷新失败，但 ok 那条依然被成功刷新。
      expect(refreshed.map((p) => p.id), contains(okProfile.id));
      expect(refreshed.map((p) => p.id), isNot(contains('unreachable')));
    });
  });

  group('ProfileUpdateScheduler 生命周期触发（不需要 WidgetsBinding）', () {
    // 这两个测试用普通 test()（不是 testWidgets()）：`didChangeAppLifecycleState`
    // 只是 WidgetsBindingObserver mixin 提供的一个普通方法覆写，直接调用它
    // 不需要真的注册到 WidgetsBinding——用普通 test() 也能验证，还避开了
    // testWidgets() 的 fake-time zone 对真实 Socket / Timer 的干扰。
    late Directory tmpDir;
    late ProfileRepository repo;

    setUp(() async {
      HttpOverrides.global = null;
      tmpDir = await Directory.systemTemp.createTemp('scheduler_lifecycle_');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: prefs,
        boxService: const StubBoxService(),
      );
    });

    tearDown(() async {
      await deleteTempDirBestEffort(tmpDir);
    });

    test('App 恢复前台（resumed）触发一次检查', () async {
      var callCount = 0;
      final server = await _countingServer(() => callCount++);
      addTearDown(() => server.close(force: true));

      final profile = await repo.addByUrl(
        'http://localhost:${server.port}/due',
      );
      await repo.updateProfile(
        profile.copyWith(
          updateInterval: const Duration(hours: 1),
          lastUpdate: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );
      callCount = 0;

      final scheduler = ProfileUpdateScheduler(
        repositoryProvider: () async => repo,
      );

      // didChangeAppLifecycleState 内部是 fire-and-forget（不 await），
      // 轮询等它真的跑完。
      scheduler.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (callCount == 0 && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(callCount, 1);
    });

    test('非 resumed 状态不会触发检查', () async {
      var callCount = 0;
      final server = await _countingServer(() => callCount++);
      addTearDown(() => server.close(force: true));

      final profile = await repo.addByUrl(
        'http://localhost:${server.port}/due',
      );
      await repo.updateProfile(
        profile.copyWith(
          updateInterval: const Duration(hours: 1),
          lastUpdate: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );
      callCount = 0;

      final scheduler = ProfileUpdateScheduler(
        repositoryProvider: () async => repo,
      );

      scheduler.didChangeAppLifecycleState(AppLifecycleState.paused);
      scheduler.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await Future.delayed(const Duration(milliseconds: 500));

      expect(callCount, 0);
    });
  });

  group('ProfileUpdateScheduler.start（需要 WidgetsBinding）', () {
    late Directory tmpDir;
    late ProfileRepository repo;

    setUp(() async {
      HttpOverrides.global = null;
      tmpDir = await Directory.systemTemp.createTemp('scheduler_start_');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: prefs,
        boxService: const StubBoxService(),
      );
    });

    tearDown(() async {
      await deleteTempDirBestEffort(tmpDir);
    });

    testWidgets('start() 之后 Timer.periodic 会定期触发检查', (tester) async {
      // TestWidgetsFlutterBinding 会全局装一个"HttpClient 一律返回 400"的
      // mock；这条测试需要真实网络，关掉它（每个测试文件独立进程，清一次
      // 对本文件后续用例都有效）。
      HttpOverrides.global = null;

      await tester.runAsync(() async {
        var callCount = 0;
        final server = await _countingServer(() => callCount++);
        addTearDown(() => server.close(force: true));

        final profile = await repo.addByUrl(
          'http://localhost:${server.port}/due',
        );
        await repo.updateProfile(
          profile.copyWith(
            updateInterval: const Duration(hours: 1),
            lastUpdate: DateTime.now().subtract(const Duration(hours: 2)),
          ),
        );
        callCount = 0;

        final scheduler = ProfileUpdateScheduler(
          repositoryProvider: () async => repo,
          checkInterval: const Duration(milliseconds: 50),
        );
        addTearDown(scheduler.dispose);

        scheduler.start();
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (callCount == 0 && DateTime.now().isBefore(deadline)) {
          await Future.delayed(const Duration(milliseconds: 50));
        }

        expect(callCount, greaterThan(0));
      });
    });
  });
}
