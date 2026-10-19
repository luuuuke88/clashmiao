// 真实控制器 + 真实 launcher + 假内核端口的联动测试：只有联动才能暴露
// 「控制器先终结意图并 discard、回执后到才 accepted」这类跨组件的顺序问题。

import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/haptic/haptic_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/store_review/store_review_service.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/connection_launcher.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/request_outcome.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_fakes/fake_kernel_port.dart';
import '../../../support/temp_dirs.dart';

class _NoHaptic extends HapticService {
  _NoHaptic(super.ref);
  @override
  Future<void> heavyImpact() async {}
  @override
  Future<void> mediumImpact() async {}
}

class _NoReview extends StoreReviewService {
  _NoReview(super.ref);
  @override
  Future<void> maybeRequestReview() async {}
}

const _config = {
  'outbounds': [
    {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory workDir;
  late FakeKernelPort port;
  late ProviderContainer container;
  var version = 0;

  setUp(() async {
    version = 0;
    tmp = await Directory.systemTemp.createTemp('launcher_ctl_test_');
    workDir = Directory('${tmp.path}/work')..createSync();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(
      dio: Dio(),
      configDir: Directory('${tmp.path}/profiles'),
      prefs: prefs,
      boxService: const StubBoxService(),
    );
    await repo.upsert({
      'id': 'p1',
      'name': 'P1',
      'url': 'https://example.invalid/p1',
    });
    final cfg = File(repo.configFilePath('p1'));
    await cfg.parent.create(recursive: true);
    await cfg.writeAsString(jsonEncode(_config));
    await repo.setActive('p1');

    port = FakeKernelPort(
      initial: FakeKernelPort.snap(
        version: ++version,
        status: KernelStatus.stopped,
      ),
    );
    var tokens = 0;
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        boxServiceProvider.overrideWithValue(
          const StubBoxService(reason: StubReason.unsupported),
        ),
        profileRepositoryProvider.overrideWith((_) async => repo),
        kernelPortProvider.overrideWithValue(port),
        isDesktopPlatformProvider.overrideWithValue(false),
        hapticServiceProvider.overrideWith(_NoHaptic.new),
        storeReviewServiceProvider.overrideWith(_NoReview.new),
        connectionLauncherProvider.overrideWith(
          (ref) => ConnectionLauncher(
            ref,
            workingDirectory: () async => workDir,
            tokenGenerator: () => 't${tokens++}',
          ),
        ),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    await container.read(activeProfileProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await port.dispose();
    await deleteTempDirBestEffort(tmp);
  });

  List<String> runtimeFiles() =>
      workDir
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith('runtime'))
          .toList()
        ..sort();

  test('相同 revision 的请求、快照先于回执到达：运行中的文件原封不动，且始终只有这一份', () async {
    final ctl = container.read(connectionControllerProvider.notifier);
    await pumpEventQueue();

    // 内核「先改快照、后回执」：request() 里先推快照并让控制器消化，再返回回执。
    port.onRequest = (r) async {
      port.push(
        FakeKernelPort.snap(
          version: ++version,
          status: KernelStatus.started,
          attempt: 1,
          desired: Desired.on,
          source: DesiredSource.app,
          appliedSeq: r.seq,
          activeConfigRevision: r.launch!.configRevision,
        ),
      );
      await pumpEventQueue();
    };

    expect(await ctl.connect(), const RequestSucceeded());
    await pumpEventQueue();
    expect(
      container.read(connectionControllerProvider).phase,
      ConnectionPhase.connected,
    );
    final first = port.requests.single.launch!;
    expect(
      first.runtimeConfigPath,
      '${workDir.path}/runtime-${first.configRevision}.json',
    );
    final file = File(first.runtimeConfigPath);
    final past = DateTime(2020, 1, 1);
    file.setLastModifiedSync(past);
    final content = file.readAsStringSync();

    // 同一配置再应用两次：revision 相同，协调器无操作（attempt 不变）；快照先
    // 到、控制器已终结意图并 discard，回执才到。
    expect(await ctl.applyConfig(), const RequestSucceeded());
    await pumpEventQueue();
    expect(await ctl.applyConfig(), const RequestSucceeded());
    await pumpEventQueue();
    await pumpEventQueue();

    expect(port.requests, hasLength(3));
    expect(
      {for (final r in port.requests) r.launch!.runtimeConfigPath},
      {first.runtimeConfigPath},
      reason: '相同 revision 的请求共用同一份文件',
    );
    expect(file.existsSync(), isTrue, reason: '运行中的文件没有被误删');
    expect(file.lastModifiedSync(), past, reason: '也没有被重写');
    expect(file.readAsStringSync(), content);
    expect(runtimeFiles(), ['runtime-${first.configRevision}.json']);
  });
}
