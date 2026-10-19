import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/selection_store_reconciler.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_fakes/fake_kernel_port.dart';
import '../../../support/fake_connection_controller.dart';
import '../../../support/profile_store_support.dart';

const _profile = ProfileEntity(
  id: 'p1',
  name: 'p1',
  url: 'https://example.invalid/p1',
  active: true,
);

/// 运行时分组：内核重建的主选择组 `select` + 自动选择组 `auto`。
const _runtime = [
  OutboundGroup(
    tag: 'select',
    type: 'selector',
    selected: 'auto',
    items: [
      OutboundProxy(tag: 'auto', type: 'urltest'),
      OutboundProxy(tag: '香港01', type: 'vless'),
      OutboundProxy(tag: '狮城01', type: 'vless'),
    ],
  ),
  OutboundGroup(
    tag: 'auto',
    type: 'urltest',
    selected: '狮城01',
    items: [
      OutboundProxy(tag: '香港01', type: 'vless'),
      OutboundProxy(tag: '狮城01', type: 'vless'),
    ],
  ),
];

void main() {
  late FakeKernelPort port;
  late ProviderContainer container;
  late StreamController<List<OutboundGroup>> live;
  late SharedPreferences prefs;

  Future<void> setUpWith({
    required String stored,
    ConnectionPhase phase = ConnectionPhase.connected,
  }) async {
    SharedPreferences.setMockInitialValues({'proxy_selection_p1': stored});
    prefs = await SharedPreferences.getInstance();
    final profiles = await seededProfileStore(prefs, [_profile]);
    port = FakeKernelPort(
      initial: FakeKernelPort.snap(
        status: KernelStatus.started,
        attempt: 3,
        desired: Desired.on,
      ),
    );
    live = StreamController<List<OutboundGroup>>.broadcast();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        profileStoreProvider.overrideWith((_) => Future.value(profiles)),
        activeProfileProvider.overrideWith((_) async => _profile),
        kernelPortProvider.overrideWithValue(port),
        outboundGroupsProvider.overrideWith((_) => live.stream),
        connectionControllerProvider.overrideWith(
          (ref) => FakeConnectionController(
            ref,
            snapshot: ConnectionSnapshot(phase: phase, epoch: 'e', attempt: 3),
          ),
        ),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    await container.read(profileStoreProvider.future);
    await container.read(activeProfileProvider.future);
    container.read(proxySelectionStoreProvider);
    container.read(selectionStoreReconcilerProvider);
  }

  tearDown(() async {
    container.dispose();
    await live.close();
    await port.dispose();
  });

  Future<void> push(List<OutboundGroup> groups) async {
    live.add(groups);
    await pumpEventQueue();
    await container.read(selectionStoreReconcilerProvider).idle;
  }

  // 真机验收 BUG-1：升级用户的手选记在 `proxy` 组下（配置文件里的 tag，运行时
  // 不存在），重放每次都 selector not found，界面上的选择从未生效。
  test('旧记录迁到运行时主选择组：带当前 attempt 写内核，旧记录删除', () async {
    await setUpWith(stored: '{"proxy":"香港01"}');
    await push(_runtime);

    expect(port.selectCalls, [
      (group: 'select', tag: '香港01', expectedAttempt: 3),
    ]);
    expect(container.read(proxySelectionStoreProvider), {'select': '香港01'});
    expect(prefs.getString('proxy_selection_p1'), isNot(contains('proxy"')));
  });

  test('记录都在运行时里：不碰内核、不改存储', () async {
    await setUpWith(stored: '{"select":"狮城01"}');
    await push(_runtime);

    expect(port.selectCalls, isEmpty);
    expect(container.read(proxySelectionStoreProvider), {'select': '狮城01'});
  });

  test('重载中（不是稳定连接）：不做判断', () async {
    await setUpWith(
      stored: '{"proxy":"香港01"}',
      phase: ConnectionPhase.reconnecting,
    );
    await push(_runtime);

    expect(port.selectCalls, isEmpty);
    expect(container.read(proxySelectionStoreProvider), {'proxy': '香港01'});
  });
}
