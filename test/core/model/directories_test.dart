import 'dart:io';

import 'package:clashmiao/core/model/directories.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归测试：iOS 上 sing-box 运行时文件（provisioned 的 .srs rule-set、
/// 每次 connect 现场拼的 runtime-config.json）曾经跟其它平台一样统一用
/// path_provider 的 getApplicationDocumentsDirectory()——那是 Runner 主 App
/// 的私有沙盒，packet-tunnel extension（独立进程）看不到，导致
/// RuntimeConfigBuilder 嵌进 config JSON 的 rule_set 绝对路径在 extension
/// 侧解析失败，"智能模式"分流规则静默失效。
///
/// [resolveSingBoxWorkingDirectoryImpl] 把"是不是 iOS"和"两种目录来源怎么
/// 拿"都做成注入参数，这里直接断言 iOS 分支调用了 App Group 路径查询、
/// 且完全没碰 path_provider；非 iOS 分支反过来。不需要真的跑在 iOS 上，
/// 也不需要 mock method channel。
void main() {
  group('resolveSingBoxWorkingDirectoryImpl', () {
    test('iOS：走 App Group 路径查询，绝不调用 getApplicationDocumentsDirectory', () async {
      var appGroupCalls = 0;
      var documentsDirCalls = 0;

      final result = await resolveSingBoxWorkingDirectoryImpl(
        isIOS: true,
        getAppGroupPath: () async {
          appGroupCalls++;
          return '/private/var/mobile/Containers/Shared/AppGroup/FAKE-UUID/Library/Caches/Runtime';
        },
        getDocumentsDirectory: () async {
          documentsDirCalls++;
          return Directory('/should/not/be/used');
        },
      );

      expect(appGroupCalls, 1, reason: 'iOS 分支必须查询 App Group 共享容器路径');
      expect(
        documentsDirCalls,
        0,
        reason:
            'iOS 分支绝不能 fallback 回 path_provider 的私有沙盒目录——'
            '那正是本次要修的 bug',
      );
      expect(
        result.path,
        '/private/var/mobile/Containers/Shared/AppGroup/FAKE-UUID/Library/Caches/Runtime',
      );
    });

    test(
      '非 iOS（Android / 桌面）：维持原状，走 getApplicationDocumentsDirectory',
      () async {
        var appGroupCalls = 0;
        var documentsDirCalls = 0;

        final result = await resolveSingBoxWorkingDirectoryImpl(
          isIOS: false,
          getAppGroupPath: () async {
            appGroupCalls++;
            return '/should/not/be/used';
          },
          getDocumentsDirectory: () async {
            documentsDirCalls++;
            return Directory(
              '/data/user/0/com.clashmiao.clashmiao/app_flutter',
            );
          },
        );

        expect(
          documentsDirCalls,
          1,
          reason: 'Android / 桌面现有行为不能受影响，必须继续走 path_provider',
        );
        expect(appGroupCalls, 0, reason: '非 iOS 平台没有 App Group 概念，不应该调用这个查询');
        expect(result.path, '/data/user/0/com.clashmiao.clashmiao/app_flutter');
      },
    );
  });
}
