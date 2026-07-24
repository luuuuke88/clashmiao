import 'package:clashmiao/core/config/build_config.dart';

enum GeoAssetType { geoip, geosite }

class GeoAsset {
  const GeoAsset({
    required this.type,
    required this.filename,
    required this.cdnUrl,
    this.lastUpdated,
    this.sizeBytes,
  });

  final GeoAssetType type;
  final String filename;
  final String cdnUrl;
  final DateTime? lastUpdated;
  final int? sizeBytes;

  /// 见 `core/config/build_config.dart`：所有编译期参数集中声明在那里。
  static const defaultGeoipUrl = geoipCdnUrl;
  static const defaultGeositeUrl = geositeCdnUrl;

  static GeoAsset get geoip => const GeoAsset(
    type: GeoAssetType.geoip,
    filename: 'geoip-cn.srs',
    cdnUrl: defaultGeoipUrl,
  );
  static GeoAsset get geosite => const GeoAsset(
    type: GeoAssetType.geosite,
    filename: 'geosite-cn.srs',
    cdnUrl: defaultGeositeUrl,
  );
}
