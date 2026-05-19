import 'dart:async';
import 'dart:io';

import 'package:clashmiao/features/assets/model/geo_asset.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class GeoUpdateService {
  final _progressController = StreamController<double>.broadcast();
  Stream<double> get progress => _progressController.stream;

  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

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
