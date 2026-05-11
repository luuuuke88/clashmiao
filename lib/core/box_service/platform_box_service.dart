import 'dart:convert';

import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';

/// 移动端 PlatformChannel 实现
///
/// iOS / Android 上 sing-box 核心需要通过原生层管理（NetworkExtension / VpnService），
/// 因此使用 Flutter Platform Channel 进行跨端通信
class PlatformBoxService implements BoxService {
  static const _channelPrefix = 'com.clashmiao.app';

  static const _methodChannel = MethodChannel('$_channelPrefix/method');
  static const _statusChannel = EventChannel(
    '$_channelPrefix/service.status',
    JSONMethodCodec(),
  );
  static const _statsChannel = EventChannel(
    '$_channelPrefix/stats',
    JSONMethodCodec(),
  );
  static const _groupsChannel = EventChannel('$_channelPrefix/groups');
  static const _logsChannel = EventChannel('$_channelPrefix/service.logs');

  late final ValueStream<BoxStatus> _status;

  @override
  Future<void> init() async {
    final statusStream = _statusChannel.receiveBroadcastStream().map(
      _parseStatus,
    );

    _status = ValueConnectableStream(statusStream).autoConnect();
    await _status.first;
  }

  @override
  Future<void> setup(AppDirectories directories, {bool debug = false}) async {
    await _methodChannel.invokeMethod('setup');
  }

  @override
  Future<void> changeConfigOptions(String jsonOptions) async {
    await _methodChannel.invokeMethod('change_config_options', jsonOptions);
  }

  @override
  Future<String?> validateConfig(
    String path,
    String tempPath, {
    bool debug = false,
  }) async {
    final message = await _methodChannel.invokeMethod<String>('parse_config', {
      'path': path,
      'tempPath': tempPath,
      'debug': debug,
    });
    if (message == null || message.isEmpty) return null;
    return message;
  }

  @override
  Future<void> start(String configPath, {String name = ''}) async {
    await _methodChannel.invokeMethod('start', {
      'path': configPath,
      'name': name,
    });
  }

  @override
  Future<void> stop() async {
    await _methodChannel.invokeMethod('stop');
  }

  @override
  Future<void> restart(String configPath, {String name = ''}) async {
    await _methodChannel.invokeMethod('restart', {
      'path': configPath,
      'name': name,
    });
  }

  @override
  Future<void> selectOutbound(String groupTag, String outboundTag) async {
    await _methodChannel.invokeMethod('select_outbound', {
      'groupTag': groupTag,
      'outboundTag': outboundTag,
    });
  }

  @override
  Future<void> urlTest(String groupTag) async {
    await _methodChannel.invokeMethod('url_test', {'groupTag': groupTag});
  }

  @override
  Stream<BoxStatus> watchStatus() => _status;

  @override
  Stream<BoxStats> watchStats() {
    return _statsChannel.receiveBroadcastStream().map((event) {
      if (event is Map<String, dynamic>) {
        return BoxStats.fromJson(event);
      }
      return BoxStats.empty;
    });
  }

  @override
  Stream<List<OutboundGroup>> watchGroups() {
    return _groupsChannel.receiveBroadcastStream().map((event) {
      if (event is String) {
        final list = jsonDecode(event) as List;
        return list
            .map((e) => OutboundGroup.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return <OutboundGroup>[];
    });
  }

  @override
  Future<String?> generateFullConfig(String path) async {
    return await _methodChannel.invokeMethod<String>('generate_config', {
      'path': path,
    });
  }

  @override
  Future<void> clearLogs() async {
    await _methodChannel.invokeMethod('clear_logs');
  }

  @override
  Stream<List<String>> watchLogs(String path) {
    return _logsChannel.receiveBroadcastStream().map(
      (event) => (event as List).map((e) => e as String).toList(),
    );
  }

  /// 解析状态事件。原生侧推过来的是 Status enum 的 .name，
  /// Android 用 PascalCase（"Started"），iOS / 桌面可能不同——统一小写后匹配。
  BoxStatus _parseStatus(dynamic event) {
    if (event is Map) {
      final status = (event['status'] as String?)?.toLowerCase();
      return switch (status) {
        'started' => const BoxStarted(),
        'starting' => const BoxStarting(),
        'stopping' => const BoxStopping(),
        _ => const BoxStopped(),
      };
    }
    return const BoxStopped();
  }
}
