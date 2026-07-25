import 'package:clashmiao/core/model/advanced_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdvancedConfig', () {
    test('default values', () {
      const cfg = AdvancedConfig();
      expect(cfg.remoteDnsOverride, isNull);
      expect(cfg.muxEnabled, isFalse);
      expect(cfg.muxProtocol, 'h2mux');
      expect(cfg.muxConcurrency, 4);
      expect(cfg.fragmentEnabled, isFalse);
      expect(cfg.fragmentRange, isNull);
    });

    test('toJson/fromJson round-trip with all fields', () {
      const original = AdvancedConfig(
        remoteDnsOverride: 'tcp://8.8.8.8',
        muxEnabled: true,
        muxProtocol: 'smux',
        muxConcurrency: 8,
        fragmentEnabled: true,
        fragmentRange: '10-50',
      );

      final json = original.toJson();
      final decoded = AdvancedConfig.fromJson(json);

      expect(decoded.remoteDnsOverride, original.remoteDnsOverride);
      expect(decoded.muxEnabled, original.muxEnabled);
      expect(decoded.muxProtocol, original.muxProtocol);
      expect(decoded.muxConcurrency, original.muxConcurrency);
      expect(decoded.fragmentEnabled, original.fragmentEnabled);
      expect(decoded.fragmentRange, original.fragmentRange);
    });

    test('toJson omits null fields', () {
      const cfg = AdvancedConfig();
      final json = cfg.toJson();
      expect(json.containsKey('remoteDnsOverride'), isFalse);
      expect(json.containsKey('fragmentRange'), isFalse);
    });

    test('fromJson uses defaults for missing fields', () {
      final cfg = AdvancedConfig.fromJson({});
      expect(cfg.muxEnabled, isFalse);
      expect(cfg.muxProtocol, 'h2mux');
      expect(cfg.muxConcurrency, 4);
      expect(cfg.fragmentEnabled, isFalse);
    });
  });
}
