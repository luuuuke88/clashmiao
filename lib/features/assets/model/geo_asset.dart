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

  static const defaultGeoipUrl = String.fromEnvironment(
    'GEOIP_CDN_URL',
    defaultValue: '',
  );
  static const defaultGeositeUrl = String.fromEnvironment(
    'GEOSITE_CDN_URL',
    defaultValue: '',
  );

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
