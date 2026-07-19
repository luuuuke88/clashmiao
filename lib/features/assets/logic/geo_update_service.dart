import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/http_client/app_http_client.dart';
import 'package:clashmiao/features/assets/model/geo_asset.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class GeoUpdateService {
  /// [mixedPort] 只在没有显式传入 [dio] 时用于构造默认 Dio——来自
  /// `network_settings.dart` 的 `NetworkSettings.mixedPort`，调用方
  /// （`geo_update_notifier.dart`）负责读取当前实际配置值传进来；不传时
  /// 兜底用 [kDefaultMixedPort]（跟 `NetworkSettings` 的默认值一致）。
  GeoUpdateService({Dio? dio, int mixedPort = kDefaultMixedPort})
    : _dio =
          dio ??
          // GeoIP/GeoSite 资源文件由用户在设置页手动触发下载，CDN 在某些
          // 受限地区可能被墙——跟订阅刷新同样的道理，`preferTunnel: true`
          // 优先经本地 mixed 代理端口，连接失败（未连接 VPN / sing-box 未
          // 启动）时自动降级直连，不会比此前"永远直连"更差，但能覆盖
          // "只有连上 VPN 才能下到 CDN"的场景。
          createAppHttpClient(
            preferTunnel: true,
            mixedPort: mixedPort,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 60),
          );

  final _progressController = StreamController<double>.broadcast();
  Stream<double> get progress => _progressController.stream;

  final Dio _dio;

  Future<void> update(GeoAsset asset) async {
    if (asset.cdnUrl.isEmpty) {
      throw Exception('CDN URL 未配置，请通过 --dart-define=GEOIP_CDN_URL=... 注入');
    }
    final workDir = await getApplicationDocumentsDirectory();
    final tmpFile = File('${workDir.path}/${asset.filename}.tmp');

    await _dio.download(
      asset.cdnUrl,
      tmpFile.path,
      onReceiveProgress: (recv, total) {
        if (total > 0) _progressController.add(recv / total);
      },
    );

    try {
      final hashResp = await _dio.get<String>('${asset.cdnUrl}.sha256');
      final expected = (hashResp.data ?? '').trim();
      if (expected.isNotEmpty) {
        final actual = sha256.convert(await tmpFile.readAsBytes()).toString();
        if (actual != expected) {
          await tmpFile.delete();
          throw Exception('SHA256 校验失败，文件可能已损坏');
        }
      }
    } catch (e) {
      if (e.toString().contains('SHA256 校验失败')) rethrow;
    }

    final dest = File('${workDir.path}/${asset.filename}');
    await tmpFile.rename(dest.path);
    _progressController.add(1.0);
  }

  void dispose() => _progressController.close();
}
