import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:rxdart/rxdart.dart';

typedef GoUint8 = UnsignedChar;

/// FFI 函数签名定义
typedef SetupNative =
    Pointer<Char> Function(
      Pointer<Char>,
      Pointer<Char>,
      Pointer<Char>,
      Int64,
      GoUint8,
    );
typedef SetupDart =
    Pointer<Char> Function(
      Pointer<Char>,
      Pointer<Char>,
      Pointer<Char>,
      int,
      int,
    );

typedef StartNative = Pointer<Char> Function(Pointer<Char>, GoUint8);
typedef StartDart = Pointer<Char> Function(Pointer<Char>, int);

typedef StopNative = Pointer<Char> Function();
typedef StopDart = Pointer<Char> Function();

typedef RestartNative = Pointer<Char> Function(Pointer<Char>, GoUint8);
typedef RestartDart = Pointer<Char> Function(Pointer<Char>, int);

typedef ParseNative =
    Pointer<Char> Function(Pointer<Char>, Pointer<Char>, GoUint8);
typedef ParseDart = Pointer<Char> Function(Pointer<Char>, Pointer<Char>, int);

typedef ChangeConfigOptionsNative = Pointer<Char> Function(Pointer<Char>);
typedef ChangeConfigOptionsDart = Pointer<Char> Function(Pointer<Char>);

typedef GenerateConfigNative = Pointer<Char> Function(Pointer<Char>);
typedef GenerateConfigDart = Pointer<Char> Function(Pointer<Char>);

typedef GenerateWarpConfigNative =
    Pointer<Char> Function(Pointer<Char>, Pointer<Char>, Pointer<Char>);
typedef GenerateWarpConfigDart =
    Pointer<Char> Function(Pointer<Char>, Pointer<Char>, Pointer<Char>);

typedef SelectOutboundNative =
    Pointer<Char> Function(Pointer<Char>, Pointer<Char>);
typedef SelectOutboundDart =
    Pointer<Char> Function(Pointer<Char>, Pointer<Char>);

typedef UrlTestNative = Pointer<Char> Function(Pointer<Char>);
typedef UrlTestDart = Pointer<Char> Function(Pointer<Char>);

typedef SetupOnceNative = Void Function(Pointer<Void>);
typedef SetupOnceDart = void Function(Pointer<Void>);

typedef StartCommandClientNative = Pointer<Char> Function(Int32, Int64);
typedef StartCommandClientDart = Pointer<Char> Function(int, int);

typedef StopCommandClientNative = Pointer<Char> Function(Int32);
typedef StopCommandClientDart = Pointer<Char> Function(int);

/// 桌面端 FFI 实现
///
/// macOS/Windows/Linux 通过 dart:ffi 直接加载 sing-box 动态库
class FFIBoxService implements BoxService {
  late final DynamicLibrary _lib;

  late final SetupDart _setup;
  late final StartDart _start;
  late final StopDart _stop;
  late final RestartDart _restart;
  late final ParseDart _parse;
  late final GenerateConfigDart _generateConfig;
  late final GenerateWarpConfigDart _generateWarpConfig;
  late final SelectOutboundDart _selectOutbound;
  late final UrlTestDart _urlTest;
  late final SetupOnceDart _setupOnce;
  late final StartCommandClientDart _startCommandClient;
  late final StopCommandClientDart _stopCommandClient;
  late final ChangeConfigOptionsDart _changeConfigOptions;

  late final ValueStream<BoxStatus> _status;
  late final ReceivePort _statusReceiver;
  Stream<BoxStats>? _statsStream;
  Stream<List<OutboundGroup>>? _groupsStream;

  final _networkChangedController = StreamController<void>.broadcast();

  /// 加载动态库
  void _loadLibrary() {
    String libPath = '';
    if (Platform.isWindows) {
      libPath = p.join(libPath, 'libcore.dll');
    } else if (Platform.isMacOS) {
      libPath = p.join(libPath, 'libcore.dylib');
    } else {
      libPath = p.join(libPath, 'libcore.so');
    }
    _lib = DynamicLibrary.open(libPath);

    _setupOnce = _lib.lookupFunction<SetupOnceNative, SetupOnceDart>(
      'setupOnce',
    );
    _setup = _lib.lookupFunction<SetupNative, SetupDart>('setup');
    _start = _lib.lookupFunction<StartNative, StartDart>('start');
    _stop = _lib.lookupFunction<StopNative, StopDart>('stop');
    _restart = _lib.lookupFunction<RestartNative, RestartDart>('restart');
    _parse = _lib.lookupFunction<ParseNative, ParseDart>('parse');
    _generateConfig = _lib
        .lookupFunction<GenerateConfigNative, GenerateConfigDart>(
          'generateConfig',
        );
    _generateWarpConfig = _lib
        .lookupFunction<GenerateWarpConfigNative, GenerateWarpConfigDart>(
          'generateWarpConfig',
        );
    _selectOutbound = _lib
        .lookupFunction<SelectOutboundNative, SelectOutboundDart>(
          'selectOutbound',
        );
    _urlTest = _lib.lookupFunction<UrlTestNative, UrlTestDart>('urlTest');
    _startCommandClient = _lib
        .lookupFunction<StartCommandClientNative, StartCommandClientDart>(
          'startCommandClient',
        );
    _stopCommandClient = _lib
        .lookupFunction<StopCommandClientNative, StopCommandClientDart>(
          'stopCommandClient',
        );
    _changeConfigOptions = _lib
        .lookupFunction<ChangeConfigOptionsNative, ChangeConfigOptionsDart>(
          'changeConfigOptions',
        );
  }

  @override
  Future<void> init() async {
    _loadLibrary();

    _statusReceiver = ReceivePort('service status');
    final source = _statusReceiver
        .asBroadcastStream()
        .map((event) => jsonDecode(event as String))
        .map(_parseStatus);
    _status = ValueConnectableStream.seeded(
      source,
      const BoxStopped(),
    ).autoConnect();
  }

  @override
  Future<void> changeConfigOptions(String jsonOptions) async {
    final err = _changeConfigOptions(
      jsonOptions.toNativeUtf8().cast(),
    ).cast<Utf8>().toDartString();
    if (err.isNotEmpty) throw Exception('changeConfigOptions failed: $err');
  }

  @override
  Future<void> setup(AppDirectories directories, {bool debug = false}) async {
    _setupOnce(NativeApi.initializeApiDLData);
    final err = _setup(
      directories.baseDir.path.toNativeUtf8().cast(),
      directories.workingDir.path.toNativeUtf8().cast(),
      directories.tempDir.path.toNativeUtf8().cast(),
      _statusReceiver.sendPort.nativePort,
      debug ? 1 : 0,
    ).cast<Utf8>().toDartString();

    if (err.isNotEmpty) {
      throw Exception('setup failed: $err');
    }
  }

  @override
  Future<String?> validateConfig(
    String path,
    String tempPath, {
    bool debug = false,
  }) async {
    final err = _parse(
      path.toNativeUtf8().cast(),
      tempPath.toNativeUtf8().cast(),
      debug ? 1 : 0,
    ).cast<Utf8>().toDartString();

    if (err.isNotEmpty) return err;
    return null;
  }

  @override
  Future<void> start(String configPath, {String name = ''}) async {
    final err = _start(
      configPath.toNativeUtf8().cast(),
      0,
    ).cast<Utf8>().toDartString();

    if (err.isNotEmpty) throw Exception('start failed: $err');
  }

  @override
  Future<void> stop() async {
    final err = _stop().cast<Utf8>().toDartString();
    if (err.isNotEmpty) throw Exception('stop failed: $err');
  }

  @override
  Future<void> restart(String configPath, {String name = ''}) async {
    final err = _restart(
      configPath.toNativeUtf8().cast(),
      0,
    ).cast<Utf8>().toDartString();

    if (err.isNotEmpty) throw Exception('restart failed: $err');
  }

  @override
  Future<void> selectOutbound(String groupTag, String outboundTag) async {
    final err = _selectOutbound(
      groupTag.toNativeUtf8().cast(),
      outboundTag.toNativeUtf8().cast(),
    ).cast<Utf8>().toDartString();

    if (err.isNotEmpty) throw Exception('selectOutbound failed: $err');
  }

  @override
  Future<void> urlTest(String groupTag) async {
    final err = _urlTest(
      groupTag.toNativeUtf8().cast(),
    ).cast<Utf8>().toDartString();
    if (err.isNotEmpty) throw Exception('urlTest failed: $err');
  }

  @override
  Stream<BoxStatus> watchStatus() => _status;

  @override
  Stream<BoxAlert> watchAlerts() => const Stream.empty();

  @override
  Stream<BoxStats> watchStats() {
    if (_statsStream != null) return _statsStream!;

    final receiver = ReceivePort('stats');
    final stream = receiver
        .asBroadcastStream(
          onCancel: (_) {
            _stopCommandClient(1).cast<Utf8>().toDartString();
            receiver.close();
            _statsStream = null;
          },
        )
        .map((event) {
          if (event is String) {
            return BoxStats.fromJson(jsonDecode(event) as Map<String, dynamic>);
          }
          return BoxStats.empty;
        });

    final err = _startCommandClient(
      1,
      receiver.sendPort.nativePort,
    ).cast<Utf8>().toDartString();
    if (err.isNotEmpty) throw Exception('watchStats failed: $err');

    return _statsStream = stream;
  }

  @override
  Stream<List<OutboundGroup>> watchGroups() {
    if (_groupsStream != null) return _groupsStream!;

    final receiver = ReceivePort('groups');
    final stream = receiver
        .asBroadcastStream(
          onCancel: (_) {
            _stopCommandClient(5).cast<Utf8>().toDartString();
            receiver.close();
            _groupsStream = null;
          },
        )
        .map((event) {
          if (event is String) {
            final list = jsonDecode(event) as List;
            return list
                .map((e) => OutboundGroup.fromJson(e as Map<String, dynamic>))
                .toList();
          }
          return <OutboundGroup>[];
        });

    try {
      final err = _startCommandClient(
        5,
        receiver.sendPort.nativePort,
      ).cast<Utf8>().toDartString();
      if (err.isNotEmpty) throw Exception('watchGroups failed: $err');
    } catch (e) {
      receiver.close();
      rethrow;
    }

    return _groupsStream = stream;
  }

  @override
  Future<String?> generateFullConfig(String path) async {
    final response = _generateConfig(
      path.toNativeUtf8().cast(),
    ).cast<Utf8>().toDartString();
    if (response.startsWith('error')) {
      return null;
    }
    return response;
  }

  @override
  Future<String?> generateWarpConfig({
    required String licenseKey,
    String? previousAccountId,
    String? previousAccessToken,
  }) async {
    final response = _generateWarpConfig(
      licenseKey.toNativeUtf8().cast(),
      (previousAccountId ?? '').toNativeUtf8().cast(),
      (previousAccessToken ?? '').toNativeUtf8().cast(),
    ).cast<Utf8>().toDartString();
    if (response.startsWith('error')) {
      return null;
    }
    return response;
  }

  @override
  Future<void> clearLogs() async {
    // 桌面端日志由文件管理，直接清空内存缓存即可
  }

  @override
  Stream<List<String>> watchLogs(String path) async* {
    // 桌面端通过文件监听来读取日志
    final file = File(path);
    if (!await file.exists()) {
      yield [];
      return;
    }
    final content = await file.readAsString();
    yield const LineSplitter().convert(content);
  }

  @override
  Stream<void> watchNetworkChanged() => _networkChangedController.stream;

  @override
  Future<void> resetTunnel() async {}

  BoxStatus _parseStatus(dynamic event) {
    debugPrint('sing-box 推送原始数据: $event');
    if (event is Map) {
      final status = event['status'] as String?;
      return switch (status) {
        'Started' => const BoxStarted(),
        'Starting' => const BoxStarting(),
        'Stopping' => const BoxStopping(),
        'Stopped' => const BoxStopped(),
        // 兼容小写
        'started' => const BoxStarted(),
        'starting' => const BoxStarting(),
        'stopping' => const BoxStopping(),
        'stopped' => const BoxStopped(),
        _ => const BoxStopped(),
      };
    }
    return const BoxStopped();
  }
}
